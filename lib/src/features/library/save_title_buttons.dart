import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/error_log_service.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../../injection.dart';
import '../../theme/theme.dart';
import 'saved_titles_providers.dart';

/// A pair of toggles for a TMDB title's user lists: Favorite (heart) and Want to
/// watch (bookmark). Reflects the live saved-state and flips it on tap. Drop it
/// on any detail page that knows the title's tmdbId, mediaType, name and poster.
class SaveTitleButtons extends ConsumerWidget {
  const SaveTitleButtons({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    required this.name,
    this.posterPath,
  });

  final int tmdbId;
  final String mediaType;
  final String name;
  final String? posterPath;

  Future<void> _toggleFavorite(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await getIt<SavedTitlesRepository>().setFavorite(
        tmdbId: tmdbId,
        mediaType: mediaType,
        name: name,
        posterPath: posterPath,
        value: value,
      );
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'SaveTitleButtons.favorite');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't update Favorites")),
      );
    }
  }

  Future<void> _toggleWant(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await getIt<SavedTitlesRepository>().setWantToWatch(
        tmdbId: tmdbId,
        mediaType: mediaType,
        name: name,
        posterPath: posterPath,
        value: value,
      );
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'SaveTitleButtons.wantToWatch');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't update Want to Watch")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref
        .watch(savedTitleProvider((tmdbId: tmdbId, mediaType: mediaType)))
        .asData
        ?.value;
    final isFavorite = saved?.favoritedAt != null;
    final isWanted = saved?.wantToWatchAt != null;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        OutlinedButton.icon(
          onPressed: () => _toggleFavorite(context, !isFavorite),
          icon: Icon(isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded),
          label: Text(isFavorite ? 'Favorited' : 'Favorite'),
        ),
        OutlinedButton.icon(
          onPressed: () => _toggleWant(context, !isWanted),
          icon: Icon(isWanted
              ? Icons.bookmark_added_rounded
              : Icons.bookmark_add_outlined),
          label: Text(isWanted ? 'On your list' : 'Want to watch'),
        ),
      ],
    );
  }
}
