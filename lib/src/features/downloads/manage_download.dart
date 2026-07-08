import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/error_log_service.dart';
import '../../injection.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/acquisition/acquisition_session.dart';
import '../../theme/theme.dart';
import '../acquire/acquire_play.dart';
import 'downloads_providers.dart';

/// Actions offered for a torrent on the Downloads screen.
enum ManageAction {
  stop,
  resume,
  tryAnotherSource,
  removeKeepFiles,
  removeDeleteFiles,
}

/// The acquisition request behind [torrent], if it was started this session
/// (mapped from its [acquisitionTag] via [AcquisitionSession]) — enables "try
/// another source". Null for a plain/imported torrent or one from a prior run.
AcquireRequest? _requestFor(TorrentStatus torrent) {
  for (final tag in torrent.tags) {
    final key = dedupeKeyFromTag(tag);
    if (key == null) continue;
    final request = getIt<AcquisitionSession>().requestFor(key);
    if (request != null) return request;
  }
  return null;
}

/// Whether a raw qBittorrent state string means the torrent is paused/stopped.
bool isPausedState(String state) {
  final s = state.toLowerCase();
  return s.contains('paused') || s.contains('stopped');
}

/// Open the manage sheet for [torrent], run the chosen action against the daemon,
/// and refresh the list. Surfaces failures via a snackbar (also logged).
Future<void> showManageDownload(
  BuildContext context,
  WidgetRef ref,
  TorrentStatus torrent,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // Retry is only offered when we can reconstruct what was searched for.
  final request = _requestFor(torrent);
  final action = await showDialog<ManageAction>(
    context: context,
    builder: (_) =>
        _ManageDownloadDialog(torrent: torrent, canRetry: request != null),
  );
  if (action == null) return;

  final daemon = getIt<TorrentDaemon>();
  try {
    switch (action) {
      case ManageAction.stop:
        await daemon.setPaused(hash: torrent.hash, paused: true);
      case ManageAction.resume:
        await daemon.setPaused(hash: torrent.hash, paused: false);
      case ManageAction.tryAnotherSource:
        // Discard this source and swap in the next-best, in the background —
        // the replacement download appears in the list.
        await retrySourceInBackground(
          title: request!.title,
          meta: request.meta,
          season: request.season,
          episode: request.episode,
        );
        messenger.showSnackBar(const SnackBar(
          content: Text('Swapped in another source — see the new download.'),
        ));
      case ManageAction.removeKeepFiles:
        await daemon.remove(hash: torrent.hash, deleteFiles: false);
      case ManageAction.removeDeleteFiles:
        await daemon.remove(hash: torrent.hash, deleteFiles: true);
    }
    ref.invalidate(downloadsProvider); // reflect the change immediately
  } on TorrentDaemonException catch (e) {
    getIt<ErrorLogService>()
        .logError(e, source: 'ManageDownload.${action.name}');
    messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
  } catch (e, st) {
    getIt<ErrorLogService>()
        .logError(e, stackTrace: st, source: 'ManageDownload.${action.name}');
    messenger.showSnackBar(
      const SnackBar(content: Text('Action failed — see the error log.')),
    );
  }
}

class _ManageDownloadDialog extends StatelessWidget {
  const _ManageDownloadDialog({required this.torrent, this.canRetry = false});
  final TorrentStatus torrent;

  /// Whether "Try another source" is available (we know how to re-resolve this).
  final bool canRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final paused = isPausedState(torrent.state);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Manage download', style: text.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              torrent.name,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Stop/resume only matters while it's still downloading.
            if (!torrent.isComplete)
              OutlinedButton.icon(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(
                    paused ? ManageAction.resume : ManageAction.stop),
                icon: Icon(paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded),
                label: Text(paused ? 'Resume' : 'Stop'),
              ),
            // "This torrent's no good" — discard it and pull the next-best.
            if (canRetry) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(ManageAction.tryAnotherSource),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try another source'),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              autofocus: torrent.isComplete,
              onPressed: () =>
                  Navigator.of(context).pop(ManageAction.removeKeepFiles),
              icon: const Icon(Icons.playlist_remove_rounded),
              label: const Text('Remove from list, keep files'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: () =>
                  Navigator.of(context).pop(ManageAction.removeDeleteFiles),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Remove & delete files from disk'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
