import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/acquisition/archive_browse_service.dart';
import '../../services/acquisition/internet_archive_resolver.dart';
import '../../theme/theme.dart';
import '../player/player_screen.dart';

/// A prepared Internet Archive playback: the streamable file plus the library
/// item it was registered as (so the player records watch history / resume).
typedef _Prepared = ({String filePath, int? libraryItemId});

/// Download-and-watch an Internet Archive title: show a "preparing" dialog that
/// adds the item's torrent (reattaching if it's already downloading), waits for
/// enough buffer to stream, registers it as a library item so it gets watch
/// history + Continue Watching, then opens the player. Cancelling leaves the
/// download running in the background (it shows up on the Downloads screen).
Future<void> playArchiveItem(BuildContext context, ArchiveItem item) async {
  final prepared = await showDialog<_Prepared>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ArchivePreparingDialog(item: item),
  );
  if (prepared == null || !context.mounted) return;
  context.push(
    Routes.player,
    extra: PlayerArgs(
      filePath: prepared.filePath,
      title: item.title,
      libraryItemId: prepared.libraryItemId,
    ),
  );
}

class _ArchivePreparingDialog extends StatefulWidget {
  const _ArchivePreparingDialog({required this.item});
  final ArchiveItem item;

  @override
  State<_ArchivePreparingDialog> createState() =>
      _ArchivePreparingDialogState();
}

class _ArchivePreparingDialogState extends State<_ArchivePreparingDialog> {
  double _progress = 0;
  String? _error;
  StreamSubscription<double>? _progressSub;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final savePath = await getIt<StorageManager>()
          .chooseTarget(estimatedBytes: widget.item.sizeBytes);
      if (savePath == null) {
        _fail('Not enough free disk space to download this.');
        return;
      }
      final task = await getIt<TorrentDaemon>().add(
        TorrentHandle(
          magnetOrUrl: internetArchiveTorrentUrl(widget.item.identifier),
          displayName: widget.item.title,
        ),
        savePath: savePath,
        // Selecting the same title again reattaches instead of re-downloading.
        dedupeKey: widget.item.identifier,
      );
      _progressSub = task.progress.listen((p) {
        if (mounted) setState(() => _progress = p);
      });
      await task.readyToStream();
      final file = await task.primaryFile;

      // Register the downloaded file as a library item so the player records
      // watch history and it surfaces in Continue Watching (upsert dedupes on
      // the unique file path — safe on replays).
      final library = getIt<LibraryRepository>();
      await library.upsert(ScannedFile(
        filePath: file,
        title: widget.item.title,
        mediaType: 'movie',
      ));
      final libraryItemId = (await library.findByPath(file))?.id;

      if (mounted) {
        Navigator.of(context)
            .pop((filePath: file, libraryItemId: libraryItemId));
      }
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'ArchivePlay.prepare');
      // Show a plain-language reason when we have one; the technical detail is
      // in the log above.
      _fail(e is TorrentDaemonException
          ? e.userMessage
          : 'Something went wrong starting this video. Please try again.');
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final error = _error;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error == null ? 'Preparing to play' : 'Playback error',
              style: text.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.item.title,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (error != null)
              Text(error,
                  style: text.bodyMedium?.copyWith(color: AppColors.danger))
            else ...[
              ClipRRect(
                borderRadius: AppRadii.rSm,
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  backgroundColor: AppColors.glassFill,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.secondary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Getting it ready to play…',
                style:
                    text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(error == null ? 'Cancel' : 'Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
