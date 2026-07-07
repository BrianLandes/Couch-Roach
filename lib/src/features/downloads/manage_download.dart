import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/acquisition/acquisition.dart';
import '../../theme/theme.dart';
import 'downloads_providers.dart';

/// Actions offered for a torrent on the Downloads screen.
enum ManageAction { stop, resume, removeKeepFiles, removeDeleteFiles }

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
  final action = await showDialog<ManageAction>(
    context: context,
    builder: (_) => _ManageDownloadDialog(torrent: torrent),
  );
  if (action == null) return;

  final daemon = getIt<TorrentDaemon>();
  try {
    switch (action) {
      case ManageAction.stop:
        await daemon.setPaused(hash: torrent.hash, paused: true);
      case ManageAction.resume:
        await daemon.setPaused(hash: torrent.hash, paused: false);
      case ManageAction.removeKeepFiles:
        await daemon.remove(hash: torrent.hash, deleteFiles: false);
      case ManageAction.removeDeleteFiles:
        await daemon.remove(hash: torrent.hash, deleteFiles: true);
    }
    ref.invalidate(downloadsProvider); // reflect the change immediately
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Action failed — see the error log.')),
    );
  }
}

class _ManageDownloadDialog extends StatelessWidget {
  const _ManageDownloadDialog({required this.torrent});
  final TorrentStatus torrent;

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
