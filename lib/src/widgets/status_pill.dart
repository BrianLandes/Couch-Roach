import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A small rounded status pill: a colored dot + label on a tinted, outlined
/// background. Used for the localhost-sidecar online/offline indicators
/// (torrent daemon, Jackett indexer). See docs/STYLE.md.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  /// Maps a health tri-state to a pill: connected / not / still checking (null).
  factory StatusPill.health({
    Key? key,
    required bool? alive,
    required String onlineLabel,
    required String offlineLabel,
  }) {
    final (label, color) = switch (alive) {
      true => (onlineLabel, AppColors.success),
      false => (offlineLabel, AppColors.danger),
      null => ('Checking…', AppColors.textSecondary),
    };
    return StatusPill(key: key, label: label, color: color);
  }

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.rPill,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(label,
              style:
                  Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}
