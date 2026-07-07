import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';

/// A poster tile in the library grid. Artwork is a placeholder gradient until
/// TMDB lands in M2; the title + SxxExx sit on a scrim for legibility.
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

  // Deterministic placeholder art so a title keeps the same look between builds.
  static const _gradients = <List<Color>>[
    [Color(0xFF2B1B5A), AppColors.primary],
    [Color(0xFF10313A), AppColors.secondary],
    [Color(0xFF3A1030), AppColors.tertiary],
    [Color(0xFF06212A), AppColors.success],
    [Color(0xFF1A1140), AppColors.primaryBright],
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = _gradients[item.title.hashCode.abs() % _gradients.length];
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
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
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
                      item.title,
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
