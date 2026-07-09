import 'package:flutter/material.dart';

import '../../data/repositories/watch_history_repository.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/poster_art.dart';

/// A landscape card in the Continue Watching rail: placeholder art, title,
/// SxxExx, time remaining, and a resume progress bar.
///
/// Primary press resumes playback ([onPressed]). On focus or hover the card
/// reveals two corner actions: open the show/movie details ([onOpenDetails])
/// and remove the title from the rail ([onRemove]).
class ContinueWatchingCard extends StatefulWidget {
  const ContinueWatchingCard({
    super.key,
    required this.entry,
    this.onPressed,
    this.onOpenDetails,
    this.onRemove,
    this.autofocus = false,
  });

  final ContinueWatchingEntry entry;
  final VoidCallback? onPressed;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onRemove;
  final bool autofocus;

  @override
  State<ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<ContinueWatchingCard> {
  // The overlay actions show while the card is focused *or* hovered. Focus is
  // tracked with a non-focusable ancestor [Focus] so it stays true while a
  // descendant action button holds focus (keyboard reach); hover with a
  // [MouseRegion] wrapping the whole card so moving onto a button keeps it up.
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  void _setFocused(bool v) {
    if (_focused != v) setState(() => _focused = v);
  }

  void _setHovered(bool v) {
    if (_hovered != v) setState(() => _hovered = v);
  }

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
    final item = widget.entry.item;
    final title = item.tmdbName ?? item.title;

    final badge = item.season != null && item.episode != null
        ? 'S${item.season} · E${item.episode}'
        : null;
    final remaining = widget.entry.remaining;
    final progress =
        (widget.entry.durationSec != null && widget.entry.durationSec! > 0)
            ? (widget.entry.resumePositionSec / widget.entry.durationSec!)
                .clamp(0.0, 1.0)
            : 0.0;

    return SizedBox(
      width: 300,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: _setFocused,
          child: FocusableCard(
            onPressed: widget.onPressed,
            autofocus: widget.autofocus,
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
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.secondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.xs,
                      left: AppSpacing.xs,
                      right: AppSpacing.xs,
                      child: _actions(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The reveal-on-focus/hover action row: details (left) and remove (right).
  /// Hidden and non-interactive (pointer *and* focus) while the card is idle so
  /// it neither shows over the art nor sits in the D-pad traversal path.
  Widget _actions() {
    if (widget.onOpenDetails == null && widget.onRemove == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      ignoring: !_active,
      child: ExcludeFocus(
        excluding: !_active,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          opacity: _active ? 1 : 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.onOpenDetails != null)
                _OverlayButton(
                  icon: Icons.info_outline_rounded,
                  tooltip: 'Go to details',
                  onPressed: widget.onOpenDetails!,
                )
              else
                const SizedBox.shrink(),
              if (widget.onRemove != null)
                _OverlayButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Remove from Continue Watching',
                  onPressed: widget.onRemove!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small scrimmed, circular icon button for the card's corner actions —
/// legible over poster art and reachable by both pointer and focus.
class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.scrim,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: Colors.white,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
