import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/acquisition/archive_browse_service.dart';
import '../../services/acquisition/internet_archive_resolver.dart';
import '../acquire/acquire_play.dart';
import '../acquire/preparing_dialog.dart';
import '../player/player_screen.dart';

/// Download-and-watch an Internet Archive title: bring up the VPN if required,
/// show the shared "preparing" dialog that adds the item's torrent (reattaching
/// if it's already downloading), waits for enough buffer to stream, registers it
/// as a library item so it gets watch history + Continue Watching, then opens the
/// player. Cancelling leaves the download running in the background.
///
/// [file] picks a specific video out of a multi-file item (an IA bundle or whole
/// season); when null the item's largest/primary video is played.
Future<void> playArchiveItem(
  BuildContext context,
  ArchiveItem item, {
  ArchiveVideoFile? file,
}) async {
  final title = file?.displayName ?? item.title;
  if (!await ensureStreamingVpn(context) || !context.mounted) return;

  final prepared = await showDialog<Prepared>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PreparingDialog(
      subtitle: title,
      prepare: ({required bindProgress}) =>
          _prepare(item: item, file: file, bindProgress: bindProgress),
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
  required ArchiveItem item,
  required ArchiveVideoFile? file,
  required void Function(Stream<double>) bindProgress,
}) async {
  // Estimate against the specific file when playing one out of a multi-file
  // item, else the whole item.
  final estimate = (file != null && file.sizeBytes > 0)
      ? file.sizeBytes
      : item.sizeBytes;
  final savePath =
      await getIt<StorageManager>().chooseTarget(estimatedBytes: estimate);
  if (savePath == null) {
    throw TorrentDaemonException(
      'not enough free disk space to download this',
      kind: TorrentErrorKind.generic,
    );
  }

  final task = await getIt<TorrentDaemon>().add(
    TorrentHandle(
      magnetOrUrl: internetArchiveTorrentUrl(item.identifier),
      displayName: item.title,
    ),
    savePath: savePath,
    // Selecting the same title again reattaches instead of re-downloading.
    dedupeKey: item.identifier,
  );
  bindProgress(task.progress);

  // Prepare the chosen file (or the primary video when none is specified).
  final path = await task.prepareFile(name: file?.name);

  // Register the downloaded file as a library item (upsert dedupes on the unique
  // file path — safe on replays). A specific file gets its own row keyed by its
  // path, so each episode tracks resume independently.
  final library = getIt<LibraryRepository>();
  await library.upsert(ScannedFile(
    filePath: path,
    title: file?.displayName ?? item.title,
    mediaType: 'movie',
    managed: true, // app-acquired (Internet Archive)
  ));
  final libraryItemId = (await library.findByPath(path))?.id;
  return (filePath: path, libraryItemId: libraryItemId);
}
