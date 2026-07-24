import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/error_log_service.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../../injection.dart';
import '../../theme/theme.dart';
import 'saved_titles_providers.dart';

/// Toggles for a TMDB title's user lists: Favorite (heart), Want to watch
/// (bookmark) and Not interested (hides it from the landing rails). Reflects the
/// live saved-state and flips it on tap. Drop it on any detail page that knows
/// the title's tmdbId, mediaType, name and poster.
class SaveTitleButtons extends ConsumerWidget {
  const SaveTitleButtons({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    required this.name,
    this.posterPath,
    this.leading = const [],
  });

  final int tmdbId;
  final String mediaType;
  final String name;
  final String? posterPath;

  /// Extra action buttons (e.g. Play / Acquire, Trailers) laid out on the same
  /// wrapping row *before* the Favorite and Want-to-watch toggles, so a detail
  /// page's actions share one row instead of stacking and eating vertical space.
  final List<Widget> leading;

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

  Future<void> _toggleNotInterested(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await getIt<SavedTitlesRepository>().setNotInterested(
        tmdbId: tmdbId,
        mediaType: mediaType,
        name: name,
        posterPath: posterPath,
        value: value,
      );
    } catch (e, st) {
      getIt<ErrorLogService>().logError(e,
          stackTrace: st, source: 'SaveTitleButtons.notInterested');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't update Not interested")),
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
    final isNotInterested = saved?.notInterestedAt != null;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...leading,
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
        OutlinedButton.icon(
          onPressed: () => _toggleNotInterested(context, !isNotInterested),
          icon: Icon(isNotInterested
              ? Icons.visibility_off_rounded
              : Icons.not_interested_rounded),
          label: Text(isNotInterested ? 'Hidden' : 'Not interested'),
        ),
      ],
    );
  }
}
