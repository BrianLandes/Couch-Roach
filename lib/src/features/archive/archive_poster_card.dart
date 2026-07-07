import 'package:flutter/material.dart';

import '../../services/acquisition/archive_browse_service.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/poster_art.dart';

/// A portrait poster card for an Internet Archive pick on the landing rail.
/// Mirrors [DiscoverPosterCard] but paints IA's thumbnail and shows the year.
class ArchivePosterCard extends StatelessWidget {
  const ArchivePosterCard({
    super.key,
    required this.item,
    this.onPressed,
    this.autofocus = false,
  });

  final ArchiveItem item;
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
                PosterArt(imageUrl: item.thumbnailUrl, seed: item.identifier),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge,
                        ),
                        if (item.year != null)
                          Text(
                            '${item.year}',
                            style: text.labelSmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                      ],
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
