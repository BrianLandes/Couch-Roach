import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/settings/settings_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/season_pack_source_repository.dart';
import '../../data/tmdb/season.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/acquisition/acquisition_session.dart';
import '../../services/discovery/tmdb_client.dart';
import '../../services/vpn/vpn_service.dart';
import '../discover/new_episodes.dart' show isAired;
import '../library/library_match_service.dart';
import '../player/player_screen.dart';
import 'preparing_dialog.dart';

/// Rough download-size estimates for disk-target selection, before we know the
/// real release size (the resolver hands back a handle, not a size).
const int _episodeEstimateBytes = 2 * 1024 * 1024 * 1024; // ~2 GB
const int _movieEstimateBytes = 5 * 1024 * 1024 * 1024; // ~5 GB
const int _seasonPackEstimateBytes = 25 * 1024 * 1024 * 1024; // ~25 GB
const int _showPackEstimateBytes = 120 * 1024 * 1024 * 1024; // ~120 GB

/// The two daemon keys one request can live under: its own [episode] key (an
/// episode, or a movie/whole-show key), and — for an episode — the [season] key
/// a season pack serving it is tagged with.
typedef AcquireKeys = ({String episode, String? season});

/// [AcquireKeys] for a title / episode. Pure.
AcquireKeys acquireKeysFor(ShowMeta meta, int? season, int? episode) => (
      episode: acquisitionDedupeKey(
          tmdbId: meta.tmdbId,
          title: meta.title,
          season: season,
          episode: episode),
      season: (season != null && episode != null)
          ? acquisitionDedupeKey(
              tmdbId: meta.tmdbId, title: meta.title, season: season)
          : null,
    );

/// Sources not to hand out for [keys]: what this episode already tried, plus
/// any season pack rejected for its season (so a bad pack isn't picked straight
/// back up by the next episode).
Set<String> _excludedFor(AcquireKeys keys) {
  final session = getIt<AcquisitionSession>();
  return {
    ...session.triedFor(keys.episode),
    if (keys.season != null) ...session.rejectedPacksFor(keys.season!),
  };
}

/// Prepare a not-local title for playback through the [AcquisitionResolver] seam
/// (Internet Archive, then the user's own Jackett indexers). Reattaches to a
/// running download for this title if one exists (no re-resolve/re-add), else
/// resolves + adds it; waits until enough is buffered to stream; registers a
/// library item (so the player records watch history + it surfaces in Continue
/// Watching); and returns the streamable file.
///
/// [bindProgress] is handed the torrent's 0..1 progress stream so the caller can
/// display it live (the inline Download control, or the archive PreparingDialog).
Future<Prepared> prepareForPlayback({
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
  required void Function(Stream<double>) bindProgress,
}) async {
  final keys = acquireKeysFor(meta, season, episode);
  // Remember how this title was requested so "try another source" can re-run the
  // same resolve later (incl. from the Downloads screen, which only has the
  // torrent). Keyed by the episode/movie identity.
  final request =
      AcquireRequest(title: title, meta: meta, season: season, episode: episode);
  getIt<AcquisitionSession>().recordRequest(keys.episode, request);

  // Tier 0 — reattach to an already-running download for this episode, or to a
  // season pack that holds it (its file is extracted below); else resolve a
  // source and add it.
  final daemon = getIt<TorrentDaemon>();
  final own = await daemon.taskForDedupeKey(keys.episode);
  if (own != null) return _finishPrepared(own, request, bindProgress);

  var allowPack = true;
  if (keys.season != null) {
    final pack = await daemon.taskForDedupeKey(keys.season!);
    if (pack != null) {
      final path = await pack.selectEpisode(
          season: season!, episode: episode!, wait: const Duration(seconds: 60));
      if (path != null) {
        return _finishPrepared(pack, request, bindProgress);
      }
      // The pack in the client doesn't have this episode (an incomplete pack) —
      // a pack can't help; fetch the single episode.
      allowPack = false;
    }
  }
  final added = await _resolveAndAdd(request, keys, allowPack: allowPack);
  return _finishPrepared(added.task, request, bindProgress,
      addedNow: added.addedNow);
}

/// The shared tail of a prepare: bind progress, extract this episode's file from
/// the (possibly multi-file/season-pack) torrent, register a library row — stamp
/// the known TMDB id + canonical name *now* so the next-episode feature works
/// immediately rather than racing the async match — and kick off that metadata
/// match (fire-and-forget; the tile updates live off the drift stream).
///
/// When the file isn't in the torrent at all and we only just added it
/// ([addedNow]), the torrent is removed again: nothing else asked for it, and
/// left alone it would download every file it has.
Future<Prepared> _finishPrepared(
  TorrentTask task,
  AcquireRequest request,
  void Function(Stream<double>) bindProgress, {
  bool addedNow = false,
}) async {
  bindProgress(task.progress);
  final String file;
  try {
    file =
        await task.prepareFile(season: request.season, episode: request.episode);
  } on TorrentDaemonException catch (e) {
    if (addedNow && e.kind == TorrentErrorKind.noVideo) {
      await _removeQuietly(task, reason: 'no file for "${request.title}"');
    }
    rethrow;
  }

  final library = getIt<LibraryRepository>();
  await library.upsert(ScannedFile(
    filePath: file,
    title: request.title,
    mediaType: request.meta.mediaType,
    season: request.season,
    episode: request.episode,
    tmdbId: request.meta.tmdbId,
    tmdbName: request.meta.tmdbId == null ? null : request.meta.title,
    managed: true, // app-acquired → surfaces on "Recently Downloaded"
  ));
  final libraryItemId = (await library.findByPath(file))?.id;
  if (libraryItemId != null) {
    unawaited(getIt<LibraryMatchService>().matchItem(libraryItemId));
  }
  return (filePath: file, libraryItemId: libraryItemId);
}

/// Ranked, deduped sources for the "Choose source" picker — episode releases and
/// the season packs that contain the episode, minus packs already rejected for
/// the season. Empty when nothing verifies or Jackett isn't up.
Future<List<SourceCandidate>> sourceCandidates({
  required ShowMeta meta,
  int? season,
  int? episode,
}) {
  final keys = acquireKeysFor(meta, season, episode);
  return getIt<AcquisitionResolver>().candidates(meta, season, episode,
      exclude: keys.season == null
          ? const {}
          : getIt<AcquisitionSession>().rejectedPacksFor(keys.season!));
}

/// Download a **specific** chosen source (from the picker) instead of the
/// auto-ranked best: discard whatever's currently downloading for this episode,
/// add the chosen handle, and prepare it. Records it as tried so a later blind
/// "try another source" skips it. Throws [TorrentDaemonException] on no disk space.
Future<Prepared> prepareChosenSource({
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
  required TorrentHandle handle,
  required void Function(Stream<double>) bindProgress,
}) async {
  await releaseCurrentSource(meta, season, episode, title: title, reject: true);
  final keys = acquireKeysFor(meta, season, episode);
  final request =
      AcquireRequest(title: title, meta: meta, season: season, episode: episode);
  getIt<AcquisitionSession>().recordRequest(keys.episode, request);
  final added = await _addSource(request, keys, handle);
  return _finishPrepared(added.task, request, bindProgress,
      addedNow: added.addedNow);
}

/// Resolve a source for an episode, **cache- and pack-first**: a season pack
/// already remembered for this show+season is reused directly — so other
/// episodes share one consistent, well-seeded source, we skip re-searching, and
/// the reuse survives a restart / the pack leaving the client. Otherwise the
/// resolver is asked (it prefers a season pack over a single episode). [exclude]
/// drops sources already tried for this episode and packs rejected for the
/// season. [allowPack] false resolves the single episode only. Movie /
/// unscoped requests bypass the cache.
Future<TorrentHandle?> _resolveEpisodeSource(
  AcquireRequest request, {
  required Set<String> exclude,
  bool allowPack = true,
}) async {
  final meta = request.meta;
  final season = request.season, episode = request.episode;
  final resolver = getIt<AcquisitionResolver>();
  if (season == null || episode == null || meta.tmdbId == null) {
    return resolver.resolve(meta, season, episode, exclude: exclude);
  }
  if (!allowPack) {
    return resolver.resolve(meta, season, episode,
        exclude: exclude, allowSeasonPack: false);
  }

  // Reuse a remembered pack directly — the hot path for later episodes of a
  // season, and no air-date fetch needed (a pack is only remembered once one was
  // actually found/chosen for this season) — unless it's excluded.
  final cached =
      await getIt<SeasonPackSourceRepository>().find(meta.tmdbId!, season);
  if (cached != null && !exclude.contains(cached.downloadUrl)) {
    getIt<ErrorLogService>().info(
        'reusing remembered season pack for "${meta.title}" S$season: '
        '${cached.displayName ?? cached.downloadUrl}',
        source: 'AcquirePack');
    return TorrentHandle(
        magnetOrUrl: cached.downloadUrl,
        displayName: cached.displayName,
        seasonPack: true);
  }

  // No remembered pack: a still-airing season can't have a complete one, so skip
  // the (fruitless, slower) pack search and grab the single episode. Only when
  // TMDB gives us the season's episodes; otherwise keep the normal pack-first path.
  final details =
      await getIt<DiscoveryClient>().seasonDetails(meta.tmdbId!, season);
  if (!seasonPackWorthTrying(details?.episodes ?? const [], DateTime.now())) {
    getIt<ErrorLogService>().info(
        'season $season of "${meta.title}" is still airing — skipping the '
        'season-pack check, fetching the single episode',
        source: 'AcquirePack');
    return resolver.resolve(meta, season, episode,
        exclude: exclude, allowSeasonPack: false);
  }
  return resolver.resolve(meta, season, episode, exclude: exclude);
}

/// Persist a chosen season pack for a show's season so other episodes reuse it.
Future<void> _rememberSeasonPack(
    ShowMeta meta, int season, TorrentHandle handle) async {
  if (meta.tmdbId == null || !handle.seasonPack) return;
  await getIt<SeasonPackSourceRepository>().remember(
    tmdbId: meta.tmdbId!,
    season: season,
    downloadUrl: handle.magnetOrUrl,
    displayName: handle.displayName,
  );
}

/// Resolve the next-best source for [request] (skipping [_excludedFor] its
/// keys) and add it — see [_addSource]. Throws [TorrentDaemonException] when
/// nothing resolves or there's no disk space.
Future<({TorrentTask task, bool addedNow})> _resolveAndAdd(
  AcquireRequest request,
  AcquireKeys keys, {
  bool allowPack = true,
  bool focusPackEpisode = false,
}) async {
  final handle = await _resolveEpisodeSource(request,
      exclude: _excludedFor(keys), allowPack: allowPack);
  if (handle == null) {
    throw TorrentDaemonException(
      'no source found for "${request.title}"',
      kind: TorrentErrorKind.sourceNotFound,
    );
  }
  return _addSource(request, keys, handle,
      focusPackEpisode: focusPackEpisode);
}

/// Add [handle] to the daemon for [request]: record it as tried, pick a disk
/// target, and add it under the right key. A season pack serving one episode is
/// keyed **per season** (so every episode played out of it shares one
/// download), remembered for the season, and has its request mirrored under
/// that key (so a retry from the Downloads screen, which only knows the tag, can
/// map it back).
///
/// The foreground prepare focuses the pack on its episode itself
/// ([TorrentTask.prepareFile]); a background add has nothing that would, so
/// with [focusPackEpisode] the episode's file is selected here — otherwise a
/// pack added for one episode downloads the whole season.
Future<({TorrentTask task, bool addedNow})> _addSource(
  AcquireRequest request,
  AcquireKeys keys,
  TorrentHandle handle, {
  bool focusPackEpisode = false,
}) async {
  final session = getIt<AcquisitionSession>();
  final daemon = getIt<TorrentDaemon>();
  session.markTried(keys.episode, handle.magnetOrUrl);

  final savePath = await getIt<StorageManager>().chooseTarget(
    estimatedBytes:
        keys.season != null ? _episodeEstimateBytes : _movieEstimateBytes,
  );
  if (savePath == null) {
    throw TorrentDaemonException(
      'not enough free disk space to download this',
      kind: TorrentErrorKind.generic,
    );
  }

  final asPack = handle.seasonPack && keys.season != null;
  final addKey = asPack ? keys.season! : keys.episode;
  if (asPack) {
    session.recordRequest(addKey, request);
    // Chosen again (e.g. picked by hand) → no longer rejected for the season.
    session.unrejectPack(addKey, handle.magnetOrUrl);
    await _rememberSeasonPack(request.meta, request.season!, handle);
  }
  final existed = await daemon.taskForDedupeKey(addKey) != null;
  final task = await daemon.add(handle, savePath: savePath, dedupeKey: addKey);
  if (asPack && focusPackEpisode) {
    unawaited(_focusPackEpisode(task, request, removeIfMissing: !existed));
  }
  return (task: task, addedNow: !existed);
}

/// Background half of a pack add: once its metadata arrives, select the
/// requested episode's file (and only that, on a fresh add). A pack that turns
/// out not to contain the episode is removed again if we only just added it.
Future<void> _focusPackEpisode(
  TorrentTask task,
  AcquireRequest request, {
  required bool removeIfMissing,
}) async {
  final log = getIt<ErrorLogService>();
  try {
    final path = await task.selectEpisode(
        season: request.season!, episode: request.episode!);
    if (path != null) {
      log.info('pack: downloading only $path', source: 'AcquirePack');
    } else if (removeIfMissing) {
      await _removeQuietly(task,
          reason: 'pack has no file for "${request.title}"');
    }
  } catch (e, st) {
    log.logError(e, stackTrace: st, source: 'AcquirePack.focusEpisode');
  }
}

/// Remove [task] from the client, keeping whatever is on disk (it may share
/// files with episodes already in the library). Best-effort, logged.
Future<void> _removeQuietly(TorrentTask task, {required String reason}) async {
  final log = getIt<ErrorLogService>();
  log.warn('removing torrent ${task.hash}: $reason', source: 'AcquireCleanup');
  try {
    await getIt<TorrentDaemon>().remove(hash: task.hash, deleteFiles: false);
  } catch (e, st) {
    log.logError(e, stackTrace: st, source: 'AcquireCleanup.remove');
  }
}

/// Abandon the current download for a title/episode and prepare its **next-best**
/// source instead ("that torrent didn't work — try another one"). Releases the
/// current source (see [releaseCurrentSource]) so the resolve doesn't just
/// reattach to it; the source it was using is already recorded as tried this
/// session, so the resolver returns the next candidate. Then runs the normal
/// [prepareForPlayback] (which buffers and returns the streamable file). Throws
/// [TorrentErrorKind.sourceNotFound] when nothing else resolves.
Future<Prepared> retryWithNextSource({
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
  required void Function(Stream<double>) bindProgress,
}) async {
  await releaseCurrentSource(meta, season, episode, title: title, reject: true);
  return prepareForPlayback(
    title: title,
    meta: meta,
    season: season,
    episode: episode,
    bindProgress: bindProgress,
  );
}

/// Background variant of [retryWithNextSource] for the Downloads screen: discard
/// the current source and resolve + add the next-best, but don't wait/buffer or
/// play — the swapped-in download just appears in the list. Throws
/// [TorrentDaemonException] when nothing else resolves (surface it to the user).
Future<void> retrySourceInBackground({
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
}) async {
  await releaseCurrentSource(meta, season, episode, title: title, reject: true);
  final keys = acquireKeysFor(meta, season, episode);
  final request =
      AcquireRequest(title: title, meta: meta, season: season, episode: episode);
  getIt<AcquisitionSession>().recordRequest(keys.episode, request);
  await _resolveAndAdd(request, keys, focusPackEpisode: true);
}

/// Let go of the current download for one title/episode — "try another source"
/// ([reject] true) or "cancel" ([reject] false).
///
/// * The episode's **own** torrent is removed with its files, and any library
///   row pointing at them is flagged missing.
/// * An episode served from a **season pack** only drops *its* file: the file
///   stops downloading and is deleted, and the pack itself is removed (keeping
///   files) only when nothing else in it is still wanted. Deleting the whole
///   pack's files here used to wipe out every other episode already downloaded
///   from it.
/// * [reject] additionally forgets the remembered pack for the season and
///   rejects it for the rest of the session, so the next episode doesn't reuse
///   the same bad pack.
Future<void> releaseCurrentSource(
  ShowMeta meta,
  int? season,
  int? episode, {
  required String title,
  required bool reject,
}) async {
  final keys = acquireKeysFor(meta, season, episode);
  final daemon = getIt<TorrentDaemon>();
  final log = getIt<ErrorLogService>();

  final own = await daemon.taskForDedupeKey(keys.episode);
  if (own != null) {
    final paths = await _filePathsOf(own);
    await daemon.remove(hash: own.hash, deleteFiles: true);
    await _markRowsMissing(paths);
  } else if (keys.season != null) {
    final pack = await daemon.taskForDedupeKey(keys.season!);
    final drop =
        await pack?.dropEpisode(season: season!, episode: episode!);
    if (pack != null && drop != null) {
      if (!drop.othersWanted) {
        await daemon.remove(hash: pack.hash, deleteFiles: false);
      }
      await _deleteQuietly(drop.path);
      await _markRowsMissing([drop.path]);
    }
    if (reject && meta.tmdbId != null) {
      final packs = getIt<SeasonPackSourceRepository>();
      final remembered = await packs.find(meta.tmdbId!, season!);
      if (remembered != null) {
        getIt<AcquisitionSession>()
            .rejectPack(keys.season!, remembered.downloadUrl);
        await packs.forget(meta.tmdbId!, season);
      }
    }
  }
  log.info(
      '${reject ? 'retry' : 'cancel'}: released current source for "$title"',
      source: 'AcquireRelease');
}

/// Absolute paths of every file in [task] (empty if the daemon can't say).
Future<List<String>> _filePathsOf(TorrentTask task) async {
  final daemon = getIt<TorrentDaemon>();
  final status = (await daemon.listTorrents())
      .where((t) => t.hash == task.hash)
      .firstOrNull;
  if (status == null || status.savePath.isEmpty) return const [];
  return [
    for (final f in await daemon.torrentFiles(task.hash))
      if (f['name'] is String) p.join(status.savePath, f['name'] as String),
  ];
}

/// Flag the library rows for [paths] missing (their files are being deleted),
/// so the show page stops offering "Play" on a file that's gone. Watch history
/// is kept, as with any reaped file.
Future<void> _markRowsMissing(List<String> paths) async {
  final library = getIt<LibraryRepository>();
  for (final path in paths) {
    final row = await library.findByPath(path);
    if (row != null && !row.missing) await library.markMissing(row.id);
  }
}

/// Delete one file, tolerating it being absent or still locked. Best-effort.
Future<void> _deleteQuietly(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (e) {
    getIt<ErrorLogService>().warn(
        'could not delete dropped episode file $path: $e',
        source: 'AcquireRelease');
  }
}

/// Stop and remove the in-progress download for this title/episode, deleting its
/// partial file — the user cancelled it from the inline control's menu. See
/// [releaseCurrentSource]; the remembered season pack is left intact (cancelling
/// isn't "this source is bad", just "not now"), so a later play can reuse it.
Future<void> cancelDownload({
  required ShowMeta meta,
  int? season,
  int? episode,
  required String title,
}) =>
    releaseCurrentSource(meta, season, episode, title: title, reject: false);

/// Start downloading an episode in the **background** if it isn't already
/// downloading — used to prefetch the next episode while the current one plays.
/// Fire-and-forget: resolves + adds the torrent but never waits, buffers, or
/// plays. When a season pack holding the episode is already in the client, its
/// file is selected there instead of fetching anything new. Returns whether a
/// download for the episode is now running; false (logged) when a VPN is
/// required but down, the episode hasn't aired, nothing resolves, or the add
/// fails. The caller checks the library first, so this only handles sourcing.
Future<bool> prefetchEpisode({
  required String showName,
  required int tmdbId,
  required int season,
  required int episode,
}) async {
  final log = getIt<ErrorLogService>();
  // Nothing to fetch for an episode that hasn't aired: no release exists, so the
  // resolver round-trip is wasted at best and latches onto a mislabelled fake at
  // worst. Guarded here rather than at the call sites because both the manual
  // "Download Next Episode" button and the automatic halfway-mark prefetch come
  // through this one function.
  if (!await episodeHasAired(tmdbId, season, episode)) {
    log.info('prefetch skipped: S${season}E$episode of "$showName" has not aired',
        source: 'AcquirePrefetch');
    return false;
  }
  if (getIt<SettingsService>().requireVpn) {
    final state = await getIt<VpnService>().ensureConnected();
    if (!state.isConnected) {
      log.info('prefetch skipped: VPN required but not connected',
          source: 'AcquirePrefetch');
      return false;
    }
  }

  final meta = ShowMeta(title: showName, tmdbId: tmdbId, mediaType: 'tv');
  final keys = acquireKeysFor(meta, season, episode);
  final request = AcquireRequest(
      title: showName, meta: meta, season: season, episode: episode);
  getIt<AcquisitionSession>().recordRequest(keys.episode, request);

  try {
    final daemon = getIt<TorrentDaemon>();
    if (await daemon.taskForDedupeKey(keys.episode) != null) return true;

    // A pack for this season is already in the client: want this episode's file
    // in it. (It used to count as "already downloading" and do nothing — but a
    // pack fetched for another episode has this one skipped, so it never came.)
    var allowPack = true;
    final pack = await daemon.taskForDedupeKey(keys.season!);
    if (pack != null) {
      final path = await pack.selectEpisode(
          season: season, episode: episode, wait: const Duration(seconds: 30));
      if (path != null) {
        log.info('prefetch: S${season}E$episode of "$showName" from the '
            'season pack already in the client', source: 'AcquirePrefetch');
        return true;
      }
      allowPack = false; // the pack doesn't have it
    }

    await _resolveAndAdd(request, keys,
        allowPack: allowPack, focusPackEpisode: true);
    log.info('prefetching S${season}E$episode of "$showName"',
        source: 'AcquirePrefetch');
    return true;
  } on TorrentDaemonException catch (e) {
    log.warn('prefetch: S${season}E$episode of "$showName" not started: '
        '${e.message}', source: 'AcquirePrefetch');
    return false;
  } catch (e, st) {
    log.logError(e, stackTrace: st, source: 'AcquirePrefetch');
    return false;
  }
}

/// The TMDB air date of one episode, or null when TMDB doesn't list it.
Future<DateTime?> episodeAirDate(int tmdbId, int season, int episode) async {
  final details = await getIt<DiscoveryClient>().seasonDetails(tmdbId, season);
  for (final e in details?.episodes ?? const []) {
    if (e.episodeNumber == episode) {
      return e.airDate == null ? null : DateTime.tryParse(e.airDate!);
    }
  }
  return null;
}

/// Whether an episode has aired. **An episode TMDB doesn't list at all counts as
/// aired** — the lookup failing (offline, rate-limited, a show TMDB dates
/// poorly) must not block a download the user asked for. Only a date TMDB
/// actually gives us, in the future, blocks it.
Future<bool> episodeHasAired(int tmdbId, int season, int episode) async {
  try {
    final details = await getIt<DiscoveryClient>().seasonDetails(tmdbId, season);
    final listed = (details?.episodes ?? const [])
        .where((e) => e.episodeNumber == episode);
    if (listed.isEmpty) return true; // unknown → don't stand in the way
    final raw = listed.first.airDate;
    if (raw == null) return false; // listed but undated → not out yet
    final parsed = DateTime.tryParse(raw);
    return parsed == null || isAired(parsed, DateTime.now());
  } catch (_) {
    return true; // a failed lookup must never block the user
  }
}

/// Whether a whole-season pack is worth looking for, given a season's [episodes]:
/// only once *every* episode has aired by [now], since a complete pack can't
/// exist — nor contain a later episode — while the season is still airing. An
/// empty list (we can't tell) returns true, keeping the normal pack-first
/// behavior. Pure + tested.
bool seasonPackWorthTrying(List<EpisodeSummary> episodes, DateTime now) {
  if (episodes.isEmpty) return true;
  return episodes.every((e) => isAired(
      e.airDate == null ? null : DateTime.tryParse(e.airDate!), now));
}

/// The episode numbers in [episodes] that have aired by [now] — the ones with
/// real content to fetch (skip announced-but-unreleased entries). Pure + tested.
List<int> airedEpisodeNumbers(List<EpisodeSummary> episodes, DateTime now) => [
      for (final e in episodes)
        if (isAired(
            e.airDate == null ? null : DateTime.tryParse(e.airDate!), now))
          e.episodeNumber,
    ];

/// Queue background downloads for a batch of [episodes] ((season, episode)) of a
/// show — the show detail "Download All". Skips episodes already in the library;
/// [prefetchEpisode] itself reuses ones already downloading (or held by a season
/// pack in the client). Returns how many are now downloading.
Future<int> downloadEpisodes({
  required String showName,
  required int tmdbId,
  required List<(int, int)> episodes,
}) async {
  final local = await _localEpisodes(tmdbId);
  var queued = 0;
  for (final (season, episode) in episodes) {
    if (local.contains((season, episode))) continue;
    if (await prefetchEpisode(
        showName: showName, tmdbId: tmdbId, season: season, episode: episode)) {
      queued++;
    }
  }
  return queued;
}

/// What a bulk "Download" actually queued — a single pack torrent covers many
/// episodes, so the UI can say "a pack" vs "N episodes" accurately.
class BulkDownloadResult {
  const BulkDownloadResult({this.packs = 0, this.episodes = 0});

  /// Whole season/series pack torrents queued (each covers many episodes).
  final int packs;

  /// Individual episode torrents queued (the per-episode fallback).
  final int episodes;

  bool get isEmpty => packs == 0 && episodes == 0;
}

/// "Download all" for one season, **pack-first**: try a whole-season pack (one
/// torrent), and only when none is found fall back to queuing the missing
/// episodes individually.
Future<BulkDownloadResult> downloadSeason({
  required String showName,
  required int tmdbId,
  required int season,
}) async {
  final details = await getIt<DiscoveryClient>().seasonDetails(tmdbId, season);
  final aired = airedEpisodeNumbers(details?.episodes ?? const [], DateTime.now());
  return _acquireSeason(
      showName: showName, tmdbId: tmdbId, season: season, aired: aired);
}

/// "Download all" across every season, **pack-first**: try one whole-series
/// pack; if none, fall through to each season (pack-first, else per-episode).
Future<BulkDownloadResult> downloadAllSeasons({
  required String showName,
  required int tmdbId,
  required List<int> seasonNumbers,
}) async {
  final now = DateTime.now();
  final aired = <int, List<int>>{};
  for (final season in seasonNumbers) {
    final details = await getIt<DiscoveryClient>().seasonDetails(tmdbId, season);
    aired[season] = airedEpisodeNumbers(details?.episodes ?? const [], now);
  }
  final local = await _localEpisodes(tmdbId);
  final anyMissing = aired.entries
      .any((e) => e.value.any((ep) => !local.contains((e.key, ep))));
  if (!anyMissing) return const BulkDownloadResult();

  // Whole-series pack first — one torrent for everything.
  final meta = ShowMeta(title: showName, tmdbId: tmdbId, mediaType: 'tv');
  final showKey = acquisitionDedupeKey(tmdbId: tmdbId, title: showName);
  final packed = await _tryPack(
    dedupeKey: showKey,
    request: AcquireRequest(title: showName, meta: meta),
    resolve: (exclude) =>
        getIt<AcquisitionResolver>().resolveShowPack(meta, exclude: exclude),
    estimateBytes: _showPackEstimateBytes,
    label: 'complete-series pack of "$showName"',
  );
  if (packed) return const BulkDownloadResult(packs: 1);

  // No series pack → each season (pack-first, else per-episode).
  var packs = 0, episodes = 0;
  for (final season in seasonNumbers) {
    final r = await _acquireSeason(
        showName: showName, tmdbId: tmdbId, season: season, aired: aired[season]!);
    packs += r.packs;
    episodes += r.episodes;
  }
  return BulkDownloadResult(packs: packs, episodes: episodes);
}

/// Pack-first acquisition for one season: try a season pack, else queue the
/// still-missing episodes one by one.
Future<BulkDownloadResult> _acquireSeason({
  required String showName,
  required int tmdbId,
  required int season,
  required List<int> aired,
}) async {
  final local = await _localEpisodes(tmdbId);
  final missing = [for (final e in aired) if (!local.contains((season, e))) e];
  if (missing.isEmpty) return const BulkDownloadResult();

  final meta = ShowMeta(title: showName, tmdbId: tmdbId, mediaType: 'tv');
  final seasonKey =
      acquisitionDedupeKey(tmdbId: tmdbId, title: showName, season: season);
  final packed = await _tryPack(
    dedupeKey: seasonKey,
    request: AcquireRequest(title: showName, meta: meta, season: season),
    resolve: (exclude) => getIt<AcquisitionResolver>()
        .resolveSeasonPack(meta, season, exclude: exclude),
    estimateBytes: _seasonPackEstimateBytes,
    label: 'season $season pack of "$showName"',
  );
  if (packed) return const BulkDownloadResult(packs: 1);

  final n = await downloadEpisodes(
      showName: showName,
      tmdbId: tmdbId,
      episodes: [for (final e in missing) (season, e)]);
  return BulkDownloadResult(episodes: n);
}

/// Resolve + queue a pack, keyed by [dedupeKey]. Returns true when a pack is now
/// downloading (already-running counts), false when none was found (so the
/// caller falls back to per-episode). Honors the VPN gate and skips a source
/// already tried this session. Fire-and-forget — never waits/plays.
Future<bool> _tryPack({
  required String dedupeKey,
  required AcquireRequest request,
  required Future<TorrentHandle?> Function(Set<String>) resolve,
  required int estimateBytes,
  required String label,
}) async {
  final log = getIt<ErrorLogService>();
  final daemon = getIt<TorrentDaemon>();
  // Already in the client → make sure all of it downloads: a pack first
  // fetched for a single episode has every other episode skipped.
  final existing = await daemon.taskForDedupeKey(dedupeKey);
  if (existing != null) {
    await existing.wantAll();
    return true;
  }

  if (getIt<SettingsService>().requireVpn) {
    final state = await getIt<VpnService>().ensureConnected();
    if (!state.isConnected) {
      log.info('pack skipped ($label): VPN required but not connected',
          source: 'AcquirePack');
      return false;
    }
  }

  final session = getIt<AcquisitionSession>();
  session.recordRequest(dedupeKey, request);
  final handle = await resolve(session.triedFor(dedupeKey));
  if (handle == null) {
    log.info('no $label — falling back to episodes', source: 'AcquirePack');
    return false;
  }
  session.markTried(dedupeKey, handle.magnetOrUrl);
  final savePath =
      await getIt<StorageManager>().chooseTarget(estimatedBytes: estimateBytes);
  if (savePath == null) return false;
  await daemon.add(handle, savePath: savePath, dedupeKey: dedupeKey);
  // Remember a season pack so single-episode plays of that season reuse it too
  // (a whole-series pack has no single season to key on).
  if (request.season != null) {
    await _rememberSeasonPack(request.meta, request.season!, handle);
  }
  log.info('queued $label: ${handle.displayName}', source: 'AcquirePack');
  return true;
}

/// The (season, episode) pairs already in the library for [tmdbId].
Future<Set<(int, int)>> _localEpisodes(int tmdbId) async => {
      for (final e in await getIt<LibraryRepository>().localEpisodes(tmdbId))
        if (e.season != null && e.episode != null) (e.season!, e.episode!),
    };

/// Open the blocking "preparing" dialog for a title and play it the moment it's
/// ready to stream. Reattaches to the in-progress download (see
/// [prepareForPlayback]), so it rides the same download the inline control
/// started rather than kicking off a second one. Cancelling the dialog leaves
/// the download running in the background. The dialog always offers "Try another
/// source" (a stalled or bad torrent → the next-best); when [retryFirst] is set
/// the *initial* action is that retry (used from the player: "this one's bad").
Future<void> playWhenReady(
  BuildContext context, {
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
  bool replace = false,
  bool retryFirst = false,
}) async {
  if (!await ensureStreamingVpn(context) || !context.mounted) return;

  Future<Prepared> next({
    required void Function(Stream<double>) bindProgress,
  }) =>
      retryWithNextSource(
        title: title,
        meta: meta,
        season: season,
        episode: episode,
        bindProgress: bindProgress,
      );

  final prepared = await showDialog<Prepared>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PreparingDialog(
      subtitle: title,
      prepare: retryFirst
          ? next
          : ({required bindProgress}) => prepareForPlayback(
                title: title,
                meta: meta,
                season: season,
                episode: episode,
                bindProgress: bindProgress,
              ),
      retry: next,
    ),
  );
  if (prepared == null || !context.mounted) return;

  final args = PlayerArgs(
    filePath: prepared.filePath,
    title: title,
    libraryItemId: prepared.libraryItemId,
  );
  // [replace] swaps the current player (e.g. a finished episode) for the next,
  // so Back doesn't return to the one that just ended.
  if (replace) {
    context.pushReplacement(Routes.player, extra: args);
  } else {
    context.push(Routes.player, extra: args);
  }
}

/// If the user requires a VPN for streaming, make sure the tunnel is up (bringing
/// it up if it's merely disconnected) before touching the network. Returns true
/// when it's safe to proceed; shows a snackbar and returns false otherwise.
/// Shared by every acquire-and-watch flow.
Future<bool> ensureStreamingVpn(BuildContext context) async {
  if (!getIt<SettingsService>().requireVpn) return true;
  final messenger = ScaffoldMessenger.of(context);
  final state = await getIt<VpnService>().ensureConnected();
  if (state.isConnected) return true;
  messenger.showSnackBar(const SnackBar(
    content: Text(
      'A VPN is required to stream, but it isn\'t connected. Connect it '
      '(or turn off "Require VPN" in Settings) and try again.',
    ),
  ));
  return false;
}
