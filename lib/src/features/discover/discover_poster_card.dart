import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/poster_art.dart';
import 'discover_tile.dart';

/// A portrait poster card for a discovery item (trending / recommendations /
/// search), for either a TV show or a movie.
class DiscoverPosterCard extends StatelessWidget {
  const DiscoverPosterCard({
    super.key,
    required this.tile,
    this.onPressed,
    this.autofocus = false,
  });

  final DiscoverTile tile;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 150,
      child: FocusableCard(
        onPressed: onPressed,
        autofocus: autofocus,
        child: ClipRRect(
          borderRadius: AppRadii.rLg,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterArt(posterPath: tile.posterPath, seed: tile.title),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC05060A)],
                      stops: [0.5, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      tile.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
