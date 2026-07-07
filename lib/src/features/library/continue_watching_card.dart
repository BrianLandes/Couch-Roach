import 'package:flutter/material.dart';

import '../../data/repositories/watch_history_repository.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/poster_art.dart';

/// A landscape card in the Continue Watching rail: placeholder art, title,
/// SxxExx, time remaining, and a resume progress bar.
class ContinueWatchingCard extends StatelessWidget {
  const ContinueWatchingCard({
    super.key,
    required this.entry,
    this.onPressed,
    this.autofocus = false,
  });

  final ContinueWatchingEntry entry;
  final VoidCallback? onPressed;
  final bool autofocus;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = entry.item;
    final title = item.tmdbName ?? item.title;

    final badge = item.season != null && item.episode != null
        ? 'S${item.season} · E${item.episode}'
        : null;
    final remaining = entry.remaining;
    final progress = (entry.durationSec != null && entry.durationSec! > 0)
        ? (entry.resumePositionSec / entry.durationSec!).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 300,
      child: FocusableCard(
        onPressed: onPressed,
        autofocus: autofocus,
        child: ClipRRect(
          borderRadius: AppRadii.rLg,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterArt(posterPath: item.tmdbPosterPath, seed: title),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xDD05060A)],
                      stops: [0.4, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          if (badge != null)
                            Text(
                              badge,
                              style: text.labelMedium
                                  ?.copyWith(color: AppColors.secondary),
                            ),
                          const Spacer(),
                          if (remaining != null)
                            Text(
                              '${_fmt(remaining)} left',
                              style: text.labelMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: AppRadii.rPill,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: AppColors.glassStroke,
                          valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
                        ),
                      ),
                    ],
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
