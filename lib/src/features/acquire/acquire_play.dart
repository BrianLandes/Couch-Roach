import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  final episodeKey = acquisitionDedupeKey(
    tmdbId: meta.tmdbId,
    title: meta.title,
    season: season,
    episode: episode,
  );
  // A season-scoped key tags a whole-season pack, so a second episode reuses the
  // same download instead of re-fetching it (Tier 0).
  final seasonKey = (season != null && episode != null)
      ? acquisitionDedupeKey(
          tmdbId: meta.tmdbId, title: meta.title, season: season)
      : null;

  // Remember how this title was requested so "try another source" can re-run the
  // same resolve later (incl. from the Downloads screen, which only has the
  // torrent). Keyed by the episode/movie identity.
  final request =
      AcquireRequest(title: title, meta: meta, season: season, episode: episode);
  getIt<AcquisitionSession>().recordRequest(episodeKey, request);

  // Tier 0 — reattach to an already-running download for this episode, or to a
  // season pack we already fetched (extract this episode's file from it below);
  // else resolve a source and add it.
  final daemon = getIt<TorrentDaemon>();
  var task = await daemon.taskForDedupeKey(episodeKey);
  if (task == null && seasonKey != null) {
    task = await daemon.taskForDedupeKey(seasonKey);
  }
  task ??= await _resolveAndAdd(request,
      episodeKey: episodeKey, seasonKey: seasonKey);
  return _finishPrepared(task, request, bindProgress);
}

/// The shared tail of a prepare: bind progress, extract this episode's file from
/// the (possibly multi-file/season-pack) torrent, register a library row — stamp
/// the known TMDB id + canonical name *now* so the next-episode feature works
/// immediately rather than racing the async match — and kick off that metadata
/// match (fire-and-forget; the tile updates live off the drift stream).
Future<Prepared> _finishPrepared(
  TorrentTask task,
  AcquireRequest request,
  void Function(Stream<double>) bindProgress,
) async {
  bindProgress(task.progress);
  final file =
      await task.prepareFile(season: request.season, episode: request.episode);

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
/// the season packs that contain the episode. Empty when nothing verifies or
/// Jackett isn't up.
Future<List<SourceCandidate>> sourceCandidates({
  required ShowMeta meta,
  int? season,
  int? episode,
}) =>
    getIt<AcquisitionResolver>().candidates(meta, season, episode);

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
  await _discardCurrentSource(meta, season, episode, title: title);
  final episodeKey = acquisitionDedupeKey(
      tmdbId: meta.tmdbId, title: meta.title, season: season, episode: episode);
  final seasonKey = (season != null && episode != null)
      ? acquisitionDedupeKey(
          tmdbId: meta.tmdbId, title: meta.title, season: season)
      : null;
  final request =
      AcquireRequest(title: title, meta: meta, season: season, episode: episode);
  final session = getIt<AcquisitionSession>();
  session.recordRequest(episodeKey, request);
  session.markTried(episodeKey, handle.magnetOrUrl);

  final isEpisode = season != null && episode != null;
  final savePath = await getIt<StorageManager>().chooseTarget(
      estimatedBytes: isEpisode ? _episodeEstimateBytes : _movieEstimateBytes);
  if (savePath == null) {
    throw TorrentDaemonException('not enough free disk space to download this',
        kind: TorrentErrorKind.generic);
  }
  final addKey = (handle.seasonPack && seasonKey != null) ? seasonKey : episodeKey;
  if (addKey != episodeKey) session.recordRequest(addKey, request);
  // A pack the user picked from the source list becomes this season's remembered
  // pack, so other episodes reuse the same one.
  if (handle.seasonPack && season != null && episode != null) {
    await _rememberSeasonPack(meta, season, handle);
  }
  final task =
      await getIt<TorrentDaemon>().add(handle, savePath: savePath, dedupeKey: addKey);
  return _finishPrepared(task, request, bindProgress);
}

/// Resolve a source for an episode, **cache- and pack-first**: a season pack
/// already remembered for this show+season is reused directly — so other
/// episodes share one consistent, well-seeded source, we skip re-searching, and
/// the reuse survives a restart / the pack leaving the client. Otherwise the
/// resolver is asked (it prefers a season pack over a single episode), and a
/// freshly-found pack is remembered for the rest of the season. [exclude] drops
/// sources already tried this session, so a pack that just failed is neither
/// reused nor re-remembered. Movie / unscoped requests bypass the cache.
Future<TorrentHandle?> _resolveEpisodeSource(
  AcquireRequest request, {
  required Set<String> exclude,
}) async {
  final meta = request.meta;
  final season = request.season, episode = request.episode;
  final resolver = getIt<AcquisitionResolver>();
  if (season == null || episode == null || meta.tmdbId == null) {
    return resolver.resolve(meta, season, episode, exclude: exclude);
  }

  // Reuse a remembered pack directly — the hot path for later episodes of a
  // season, and no air-date fetch needed (a pack is only remembered once one was
  // actually found/chosen for this season) — unless it just failed this session.
  final packs = getIt<SeasonPackSourceRepository>();
  final cached = await packs.find(meta.tmdbId!, season);
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

  final handle = await resolver.resolve(meta, season, episode, exclude: exclude);
  if (handle != null && handle.seasonPack) {
    await _rememberSeasonPack(meta, season, handle);
  }
  return handle;
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

/// Resolve a source for [request] — excluding any already tried this session
/// ([AcquisitionSession]) so a retry picks the next-best — choose a disk target,
/// and add it to the daemon. Records the chosen source as tried and (for a
/// season pack, tagged per-season) mirrors the request under the add key so the
/// Downloads screen can retry it. Throws [TorrentDaemonException] when nothing
/// resolves or there's no disk space.
Future<TorrentTask> _resolveAndAdd(
  AcquireRequest request, {
  required String episodeKey,
  required String? seasonKey,
}) async {
  final session = getIt<AcquisitionSession>();
  final handle = await _resolveEpisodeSource(
    request,
    exclude: session.triedFor(episodeKey),
  );
  if (handle == null) {
    throw TorrentDaemonException(
      'no source found for "${request.title}"',
      kind: TorrentErrorKind.sourceNotFound,
    );
  }
  session.markTried(episodeKey, handle.magnetOrUrl);

  final isEpisode = request.season != null && request.episode != null;
  final savePath = await getIt<StorageManager>().chooseTarget(
    estimatedBytes: isEpisode ? _episodeEstimateBytes : _movieEstimateBytes,
  );
  if (savePath == null) {
    throw TorrentDaemonException(
      'not enough free disk space to download this',
      kind: TorrentErrorKind.generic,
    );
  }
  // A season-pack fallback is keyed per-season so every episode played out of it
  // shares one download; a single episode is keyed per-episode.
  final addKey =
      (handle.seasonPack && seasonKey != null) ? seasonKey : episodeKey;
  // So a retry from the Downloads screen (which only knows the torrent's tag)
  // can map a pack torrent back to a request.
  if (addKey != episodeKey) session.recordRequest(addKey, request);
  return getIt<TorrentDaemon>().add(handle, savePath: savePath, dedupeKey: addKey);
}

/// Abandon the current download for a title/episode and prepare its **next-best**
/// source instead ("that torrent didn't work — try another one"). Removes the
/// current torrent + its files so the resolve doesn't just reattach to it; the
/// source it was using is already recorded as tried this session, so the resolver
/// returns the next candidate. Then runs the normal [prepareForPlayback] (which
/// buffers and returns the streamable file). Throws
/// [TorrentErrorKind.sourceNotFound] when nothing else resolves.
Future<Prepared> retryWithNextSource({
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
  required void Function(Stream<double>) bindProgress,
}) async {
  await _discardCurrentSource(meta, season, episode, title: title);
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
  await _discardCurrentSource(meta, season, episode, title: title);
  final episodeKey = acquisitionDedupeKey(
      tmdbId: meta.tmdbId, title: meta.title, season: season, episode: episode);
  final seasonKey = (season != null && episode != null)
      ? acquisitionDedupeKey(tmdbId: meta.tmdbId, title: meta.title, season: season)
      : null;
  final request =
      AcquireRequest(title: title, meta: meta, season: season, episode: episode);
  getIt<AcquisitionSession>().recordRequest(episodeKey, request);
  await _resolveAndAdd(request, episodeKey: episodeKey, seasonKey: seasonKey);
}

/// Remove the current download for this title/episode (deleting its files). The
/// episode's own torrent is removed; only if there isn't one (the episode was
/// served from a season pack) is the pack discarded, so retrying one episode
/// doesn't needlessly nuke a pack that also has its own single-episode torrent.
Future<void> _discardCurrentSource(
  ShowMeta meta,
  int? season,
  int? episode, {
  required String title,
}) async {
  final daemon = getIt<TorrentDaemon>();
  final episodeKey = acquisitionDedupeKey(
      tmdbId: meta.tmdbId, title: meta.title, season: season, episode: episode);
  final hadEpisodeTorrent = await daemon.taskForDedupeKey(episodeKey) != null;
  await daemon.removeByDedupeKey(episodeKey, deleteFiles: true);
  if (!hadEpisodeTorrent && season != null && episode != null) {
    final seasonKey =
        acquisitionDedupeKey(tmdbId: meta.tmdbId, title: meta.title, season: season);
    await daemon.removeByDedupeKey(seasonKey, deleteFiles: true);
    // The episode was served from the remembered pack and it's being rejected —
    // forget it so the retry finds a genuinely different source (session-exclude
    // also blocks re-picking it), and so the whole season moves off a bad pack.
    if (meta.tmdbId != null) {
      await getIt<SeasonPackSourceRepository>().forget(meta.tmdbId!, season);
    }
  }
  getIt<ErrorLogService>().info(
      'retry: discarded current source for "$title" — resolving next-best',
      source: 'AcquireRetry');
}

/// Stop and remove the in-progress download for this title/episode, deleting its
/// partial files — the user cancelled it from the inline control's menu. Removes
/// the episode's own torrent; only if there isn't one (it was streaming from a
/// season pack) is the pack removed. No re-resolve — the control returns to idle.
/// The remembered season pack is left intact (cancelling isn't "this source is
/// bad", just "not now"), so a later play can still reuse it.
Future<void> cancelDownload({
  required ShowMeta meta,
  int? season,
  int? episode,
  required String title,
}) async {
  final daemon = getIt<TorrentDaemon>();
  final episodeKey = acquisitionDedupeKey(
      tmdbId: meta.tmdbId, title: meta.title, season: season, episode: episode);
  final hadEpisodeTorrent = await daemon.taskForDedupeKey(episodeKey) != null;
  await daemon.removeByDedupeKey(episodeKey, deleteFiles: true);
  if (!hadEpisodeTorrent && season != null && episode != null) {
    final seasonKey =
        acquisitionDedupeKey(tmdbId: meta.tmdbId, title: meta.title, season: season);
    await daemon.removeByDedupeKey(seasonKey, deleteFiles: true);
  }
  getIt<ErrorLogService>()
      .info('cancelled download for "$title"', source: 'AcquireCancel');
}

/// Start downloading an episode in the **background** if it isn't already
/// downloading — used to prefetch the next episode while the current one plays.
/// Fire-and-forget: resolves + adds the torrent but never waits, buffers, or
/// plays. No-op (logged) when a VPN is required but down, when a download for
/// this episode (or a season pack containing it) already exists, or when nothing
/// resolves. The caller checks the library first, so this only handles sourcing.
Future<void> prefetchEpisode({
  required String showName,
  required int tmdbId,
  required int season,
  required int episode,
}) async {
  final log = getIt<ErrorLogService>();
  if (getIt<SettingsService>().requireVpn) {
    final state = await getIt<VpnService>().ensureConnected();
    if (!state.isConnected) {
      log.info('prefetch skipped: VPN required but not connected',
          source: 'AcquirePrefetch');
      return;
    }
  }

  final daemon = getIt<TorrentDaemon>();
  final session = getIt<AcquisitionSession>();
  final meta = ShowMeta(title: showName, tmdbId: tmdbId, mediaType: 'tv');
  final episodeKey = acquisitionDedupeKey(
      tmdbId: tmdbId, title: showName, season: season, episode: episode);
  final seasonKey =
      acquisitionDedupeKey(tmdbId: tmdbId, title: showName, season: season);
  // Already downloading this episode, or a season pack that would contain it.
  if (await daemon.taskForDedupeKey(episodeKey) != null ||
      await daemon.taskForDedupeKey(seasonKey) != null) {
    return;
  }

  // Record how this episode was requested so "try another source" can retry it,
  // and skip any source already tried this session.
  final request = AcquireRequest(
      title: showName, meta: meta, season: season, episode: episode);
  session.recordRequest(episodeKey, request);
  final handle = await _resolveEpisodeSource(request,
      exclude: session.triedFor(episodeKey));
  if (handle == null) {
    log.info('prefetch: no source for S${season}E$episode of "$showName"',
        source: 'AcquirePrefetch');
    return;
  }
  session.markTried(episodeKey, handle.magnetOrUrl);
  final savePath = await getIt<StorageManager>()
      .chooseTarget(estimatedBytes: _episodeEstimateBytes);
  if (savePath == null) return;

  final addKey = handle.seasonPack ? seasonKey : episodeKey;
  if (addKey != episodeKey) {
    session.recordRequest(
        addKey,
        AcquireRequest(
            title: showName, meta: meta, season: season, episode: episode));
  }
  await daemon.add(handle, savePath: savePath, dedupeKey: addKey);
  log.info('prefetching next episode S${season}E$episode of "$showName"',
      source: 'AcquirePrefetch');
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
/// [prefetchEpisode] itself skips ones already downloading (or covered by a
/// season pack). Returns how many were asked to fetch (i.e. not already local).
Future<int> downloadEpisodes({
  required String showName,
  required int tmdbId,
  required List<(int, int)> episodes,
}) async {
  final local = {
    for (final e in await getIt<LibraryRepository>().localEpisodes(tmdbId))
      if (e.season != null && e.episode != null) (e.season!, e.episode!),
  };
  var queued = 0;
  for (final (season, episode) in episodes) {
    if (local.contains((season, episode))) continue;
    await prefetchEpisode(
        showName: showName, tmdbId: tmdbId, season: season, episode: episode);
    queued++;
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
  // Already downloading this pack → the episodes it holds are covered.
  if (await daemon.taskForDedupeKey(dedupeKey) != null) return true;

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
