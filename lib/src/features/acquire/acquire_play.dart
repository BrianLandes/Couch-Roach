import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/settings/settings_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/acquisition/acquisition_session.dart';
import '../../services/vpn/vpn_service.dart';
import '../player/player_screen.dart';
import 'preparing_dialog.dart';

/// Rough download-size estimates for disk-target selection, before we know the
/// real release size (the resolver hands back a handle, not a size).
const int _episodeEstimateBytes = 2 * 1024 * 1024 * 1024; // ~2 GB
const int _movieEstimateBytes = 5 * 1024 * 1024 * 1024; // ~5 GB

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
  bindProgress(task.progress);

  // Pass season/episode so a multi-file (season-pack) torrent hands back this
  // exact episode's file rather than the largest video.
  final file = await task.prepareFile(season: season, episode: episode);

  // Register as a library item (upsert dedupes on the file path) so the player
  // records watch history / resume and it surfaces in Continue Watching. The
  // TMDB link (tmdbId) is filled in later by the library matcher.
  final library = getIt<LibraryRepository>();
  await library.upsert(ScannedFile(
    filePath: file,
    title: title,
    mediaType: meta.mediaType,
    season: season,
    episode: episode,
  ));
  final libraryItemId = (await library.findByPath(file))?.id;
  return (filePath: file, libraryItemId: libraryItemId);
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
  final handle = await getIt<AcquisitionResolver>().resolve(
    request.meta,
    request.season,
    request.episode,
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
  }
  getIt<ErrorLogService>().info(
      'retry: discarded current source for "$title" — resolving next-best',
      source: 'AcquireRetry');
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
  session.recordRequest(
      episodeKey,
      AcquireRequest(
          title: showName, meta: meta, season: season, episode: episode));
  final handle = await getIt<AcquisitionResolver>()
      .resolve(meta, season, episode, exclude: session.triedFor(episodeKey));
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
