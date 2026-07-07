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
    final text = Theme.of(context).textTheme;
    final title = item.tmdbName ?? item.title;
    final badge = item.season != null && item.episode != null
        ? 'S${item.season} · E${item.episode}'
        : (item.mediaType == 'movie' ? 'Movie' : null);

    return FocusableCard(
      onPressed: onPressed,
      autofocus: autofocus,
      child: ClipRRect(
        borderRadius: AppRadii.rLg,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterArt(posterPath: item.tmdbPosterPath, seed: title),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC05060A)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badge != null) ...[
                      Text(
                        badge,
                        style: text.labelMedium?.copyWith(color: AppColors.secondary),
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
      ),
    );
  }
}
