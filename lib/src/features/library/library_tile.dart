import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/poster_art.dart';

/// A poster tile in the library grid. Shows the matched TMDB poster once
/// available, falling back to a placeholder gradient; title + SxxExx sit on a
/// scrim for legibility.
class LibraryTile extends StatelessWidget {
  const LibraryTile({
    super.key,
    required this.item,
    this.onPressed,
    this.autofocus = false,
  });

  final LibraryItem item;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final title = item.tmdbName ?? item.title;
    final badge = item.season != null && item.episode != null
        ? 'S${item.season} · E${item.episode}'
        : (item.mediaType == 'movie' ? 'Movie' : null);
    return FocusableCard(
      onPressed: onPressed,
      autofocus: autofocus,
      child: _PosterTile(
          posterPath: item.tmdbPosterPath, seed: title, title: title, badge: badge),
    );
  }
}

/// A library tile that stands in for a whole TV show — its matched poster, name,
/// and an episode-count badge — collapsing every downloaded episode into one.
class ShowLibraryTile extends StatelessWidget {
  const ShowLibraryTile({
    super.key,
    required this.name,
    required this.posterPath,
    required this.episodeCount,
    this.onPressed,
    this.autofocus = false,
  });

  final String name;
  final String? posterPath;
  final int episodeCount;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onPressed: onPressed,
      autofocus: autofocus,
      child: _PosterTile(
        posterPath: posterPath,
        seed: name,
        title: name,
        badge: '$episodeCount episode${episodeCount == 1 ? '' : 's'}',
      ),
    );
  }
}

/// Shared poster body: the 2:3 art with a bottom scrim, an optional accent
/// [badge] line, and the [title].
class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.posterPath,
    required this.seed,
    required this.title,
    this.badge,
  });

  final String? posterPath;
  final String seed;
  final String title;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: AppRadii.rLg,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PosterArt(posterPath: posterPath, seed: seed),
            const PosterScrim(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badge != null) ...[
                    Text(
                      badge!,
                      style: text.labelMedium
                          ?.copyWith(color: AppColors.secondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
