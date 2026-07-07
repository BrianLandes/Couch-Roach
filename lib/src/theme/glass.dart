import 'dart:ui';

import 'package:flutter/material.dart';

import 'colors.dart';
import 'radii.dart';

/// Blur/opacity constants for frosted surfaces.
abstract final class AppGlass {
  static const double blur = 24; // standard frosted panel
  static const double blurStrong = 40; // nav bars / modal scrims
  static const double blurThin = 12; // chips / small controls
}

/// The core building block of the look: a translucent, blurred, hairline-bordered
/// panel that refracts whatever ambient color sits behind it. Wrap content in this
/// instead of a plain `Card`/`Container` to get the liquid-glass surface.
///
/// Must have something colorful behind it (see [AmbientBackground]) or the blur
/// has nothing to work with and it reads as flat grey.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = AppRadii.rLg,
    this.blur = AppGlass.blur,
    this.padding,
    this.fill = AppColors.glassFill,
    this.strong = false,
    this.highlight = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color fill;
  final bool strong;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                strong ? AppColors.glassFillStrong : fill,
                fill,
              ],
            ),
            border: Border.all(color: AppColors.glassStroke, width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 12)),
            ],
          ),
          child: Stack(
            children: [
              // Top-edge sheen that sells the "glass" refraction.
              if (highlight)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x00FFFFFF), AppColors.glassHighlight, Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
              if (padding != null) Padding(padding: padding!, child: child) else child,
            ],
          ),
        ),
      ),
    );
  }
}

/// The stage the glass sits on: the dark base plus a few soft, out-of-focus color
/// blobs so frosted surfaces have something to refract. Put one behind each screen.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.bg),
      child: Stack(
        children: [
          const _Blob(color: AppColors.glowViolet, alignment: Alignment(-0.9, -0.9), size: 520),
          const _Blob(color: AppColors.glowCyan, alignment: Alignment(1.1, -0.3), size: 460),
          const _Blob(color: AppColors.glowIndigo, alignment: Alignment(-0.2, 1.1), size: 600),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.alignment, required this.size});

  final Color color;
  final Alignment alignment;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
