import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/settings_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
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
  final isEpisode = season != null && episode != null;
  final episodeKey = acquisitionDedupeKey(
    tmdbId: meta.tmdbId,
    title: meta.title,
    season: season,
    episode: episode,
  );
  // A season-scoped key tags a whole-season pack, so a second episode reuses the
  // same download instead of re-fetching it (Tier 0).
  final seasonKey = isEpisode
      ? acquisitionDedupeKey(
          tmdbId: meta.tmdbId, title: meta.title, season: season)
      : null;

  // Tier 0 — reattach to an already-running download for this episode, or to a
  // season pack we already fetched (extract this episode's file from it below);
  // else resolve a source and add it.
  final daemon = getIt<TorrentDaemon>();
  var task = await daemon.taskForDedupeKey(episodeKey);
  if (task == null && seasonKey != null) {
    task = await daemon.taskForDedupeKey(seasonKey);
  }
  if (task == null) {
    final handle =
        await getIt<AcquisitionResolver>().resolve(meta, season, episode);
    if (handle == null) {
      throw TorrentDaemonException(
        'no source found for "$title"',
        kind: TorrentErrorKind.sourceNotFound,
      );
    }
    final savePath = await getIt<StorageManager>().chooseTarget(
      estimatedBytes: isEpisode ? _episodeEstimateBytes : _movieEstimateBytes,
    );
    if (savePath == null) {
      throw TorrentDaemonException(
        'not enough free disk space to download this',
        kind: TorrentErrorKind.generic,
      );
    }
    // A season-pack fallback is keyed per-season so every episode played out of
    // it shares one download; a single episode is keyed per-episode.
    final addKey = handle.seasonPack ? seasonKey! : episodeKey;
    task = await daemon.add(handle, savePath: savePath, dedupeKey: addKey);
  }
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

/// Open the blocking "preparing" dialog for a title and play it the moment it's
/// ready to stream. Reattaches to the in-progress download (see
/// [prepareForPlayback]), so it rides the same download the inline control
/// started rather than kicking off a second one. Cancelling the dialog leaves
/// the download running in the background.
Future<void> playWhenReady(
  BuildContext context, {
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
}) async {
  if (!await ensureStreamingVpn(context) || !context.mounted) return;

  final prepared = await showDialog<Prepared>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PreparingDialog(
      subtitle: title,
      prepare: ({required bindProgress}) => prepareForPlayback(
        title: title,
        meta: meta,
        season: season,
        episode: episode,
        bindProgress: bindProgress,
      ),
    ),
  );
  if (prepared == null || !context.mounted) return;

  context.push(
    Routes.player,
    extra: PlayerArgs(
      filePath: prepared.filePath,
      title: title,
      libraryItemId: prepared.libraryItemId,
    ),
  );
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
