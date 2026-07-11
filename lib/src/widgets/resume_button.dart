import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/db/database.dart';
import '../data/repositories/watch_history_repository.dart';
import '../features/library/library_providers.dart';
import '../features/player/player_screen.dart';
import '../router/app_router.dart';

/// A "Resume" button for a detail page. When the show (by [tmdbId]) or a single
/// title (by [libraryItemId]) has an in-progress video in Continue Watching, it
/// plays the most recently watched one from its saved position. Renders nothing
/// when there's nothing to resume. Live off the Continue Watching stream, so it
/// appears and updates as watch history changes.
class ResumeButton extends ConsumerWidget {
  const ResumeButton({super.key, this.tmdbId, this.libraryItemId})
      : assert(tmdbId != null || libraryItemId != null,
            'ResumeButton needs a show tmdbId or a libraryItemId');

  /// Match any in-progress episode of this show (its most recent one wins).
  final int? tmdbId;

  /// Match this exact library title (for a movie / single title).
  final int? libraryItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(continueWatchingProvider).asData?.value ?? const [];
    // The feed is ordered most-recent-first, so the first match is the video the
    // user was last watching.
    ContinueWatchingEntry? entry;
    for (final e in entries) {
      if ((tmdbId != null && e.item.tmdbId == tmdbId) ||
          (libraryItemId != null && e.item.id == libraryItemId)) {
        entry = e;
        break;
      }
    }
    if (entry == null) return const SizedBox.shrink();
    final item = entry.item;

    // A primary filled button (its own accent color) so it stands out among the
    // outlined actions it shares a row with.
    return FilledButton.icon(
      onPressed: () => context.push(
        Routes.player,
        extra: PlayerArgs(
          filePath: item.filePath,
          title: item.tmdbName ?? item.title,
          libraryItemId: item.id,
        ),
      ),
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(_label(item)),
    );
  }

  String _label(LibraryItem item) {
    final s = item.season, e = item.episode;
    if (s != null && e != null) {
      final code = 'S${s.toString().padLeft(2, '0')}'
          'E${e.toString().padLeft(2, '0')}';
      return 'Resume $code';
    }
    return 'Resume';
  }
}
