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

/// Download-and-watch a title the user doesn't have locally, sourced through the
/// [AcquisitionResolver] seam (Internet Archive, then the user's own Jackett
/// indexers — see CompositeAcquisitionResolver). Resolves [meta] (with optional
/// [season]/[episode]) to a torrent, streams it once enough is buffered,
/// registers a library item so it gets watch history + Continue Watching, then
/// opens the player. Cancelling leaves the download running in the background.
Future<void> acquireAndPlay(
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
      prepare: ({required bindProgress}) => _prepare(
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

Future<Prepared> _prepare({
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
  required void Function(Stream<double>) bindProgress,
}) async {
  final isEpisode = season != null && episode != null;

  final handle = await getIt<AcquisitionResolver>().resolve(meta, season, episode);
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

  // Stable per logical title/episode so re-selecting reattaches to the running
  // download instead of adding a duplicate.
  final dedupeKey = 'cr-tmdb-${meta.tmdbId ?? meta.title}'
      '${isEpisode ? '-s${season}e$episode' : ''}';
  final task = await getIt<TorrentDaemon>().add(
    handle,
    savePath: savePath,
    dedupeKey: dedupeKey,
  );
  bindProgress(task.progress);

  final file = await task.prepareFile();

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
