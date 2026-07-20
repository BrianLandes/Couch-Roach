import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../injection.dart';
import '../../services/cleanup/media_deleter.dart';
import '../../theme/theme.dart';

/// Confirm, then permanently delete [items] from disk (video + English
/// sidecars) and forget them (rows + watch history), sharing one destructive
/// dialog and result snackbar across the movie / show / episode delete controls.
///
/// [what] describes what's going ("this episode", "Season 3", the movie title).
/// Returns the number of files actually deleted (0 when cancelled, nothing to
/// delete, or every delete failed) so the caller can navigate/refresh on success.
Future<int> confirmAndDelete(
  BuildContext context, {
  required String what,
  required List<LibraryItem> items,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (items.isEmpty) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to delete — no files here.')));
    return 0;
  }

  final count = items.length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete from disk?'),
      content: Text(
        'Permanently delete $what — $count file${count == 1 ? '' : 's'} and '
        'their subtitles. This frees the space and forgets the watch history; '
        'it can’t be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return 0;

  final removed = await getIt<MediaDeleter>().deleteItems(items);
  messenger.showSnackBar(SnackBar(
    content: Text(removed == 0
        ? "Couldn't delete those files — see the error log."
        : 'Deleted $removed file${removed == 1 ? '' : 's'}.'),
  ));
  return removed;
}
