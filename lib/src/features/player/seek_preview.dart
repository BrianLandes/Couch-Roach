import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/transcode/trickplay_service.dart';
import '../../theme/theme.dart';
import 'seek_preview_layout.dart';

/// The thumbnail shown above the seek bar while hovering or dragging it: the
/// frame nearest [at], cropped out of a pre-built preview sheet, with its
/// timestamp underneath. Nothing is decoded per hover — the sheet image is
/// cached by Flutter after the first use, and moving within it is a translate.
class SeekPreview extends StatelessWidget {
  const SeekPreview({super.key, required this.sheets, required this.at});

  final TrickplaySheets sheets;
  final Duration at;

  /// Tiles are stored small; shown a touch larger for a 10-foot screen.
  static const scale = 1.25;

  /// The preview's on-screen width, for centring it over the pointer.
  static double widthFor(TrickplaySheets sheets) =>
      sheets.manifest.tileWidth * scale;

  @override
  Widget build(BuildContext context) {
    final m = sheets.manifest;
    final tile = m.tileAt(at);
    final w = m.tileWidth * scale, h = m.tileHeight * scale;
    final sheetW = w * m.columns, sheetH = h * m.rows;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadii.rSm,
            border: Border.all(color: AppColors.glassHighlight),
            boxShadow: const [
              BoxShadow(color: AppColors.scrim, blurRadius: AppSpacing.md),
            ],
          ),
          child: ClipRRect(
            borderRadius: AppRadii.rSm,
            child: SizedBox(
              width: w,
              height: h,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: sheetW,
                maxWidth: sheetW,
                minHeight: sheetH,
                maxHeight: sheetH,
                child: Transform.translate(
                  offset: Offset(-tile.column * w, -tile.row * h),
                  child: Image.file(
                    File(sheets.sheetPath(tile.sheet)),
                    width: sheetW,
                    height: sheetH,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: AppColors.bgElevated),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.scrim,
            borderRadius: AppRadii.rPill,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs / 2),
            child: Text(
              formatPreviewTime(at),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
