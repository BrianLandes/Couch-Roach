import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/tmdb/tmdb_images.dart';
import '../theme/theme.dart';

/// A poster background: a network image when available, otherwise a
/// deterministic placeholder gradient (stable per title). Falls back to the
/// gradient on load error too, so a flaky network never leaves a blank tile.
///
/// Pass a TMDB [posterPath] (resolved to a TMDB image URL) or a ready-made
/// [imageUrl] (e.g. an Internet Archive thumbnail); [imageUrl] wins if both are
/// given.
class PosterArt extends StatelessWidget {
  const PosterArt({
    super.key,
    this.posterPath,
    required this.seed,
    this.imageUrl,
  });

  final String? posterPath;
  final String? imageUrl;
  final String seed;

  static const _gradients = <List<Color>>[
    [Color(0xFF2B1B5A), AppColors.primary],
    [Color(0xFF10313A), AppColors.secondary],
    [Color(0xFF3A1030), AppColors.tertiary],
    [Color(0xFF06212A), AppColors.success],
    [Color(0xFF1A1140), AppColors.primaryBright],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[seed.hashCode.abs() % _gradients.length];
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
    );

    final url = imageUrl ?? TmdbImages.poster(posterPath);
    if (url == null) return fallback;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // Decode at roughly poster-tile size (~150 logical px at 2x DPR) instead
      // of holding a full-resolution bitmap per tile — the dominant RAM cost on
      // the landing/library grids. Height follows from the 2:3 aspect.
      memCacheWidth: 320,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// The bottom fade laid over [PosterArt] so overlaid title text stays legible
/// against arbitrary artwork. Always stacked directly on top of the poster in a
/// `Stack` — never used on its own.
///
/// Two strengths: the default suits a 2:3 poster tile carrying a title, and
/// [PosterScrim.strong] suits a wide card whose overlay stacks a title,
/// subtitle and progress bar. Anything else means a new token, not a one-off
/// gradient at the call site.
class PosterScrim extends StatelessWidget {
  const PosterScrim({super.key})
      : _color = AppColors.posterScrim,
        _start = 0.45;

  const PosterScrim.strong({super.key})
      : _color = AppColors.posterScrimStrong,
        _start = 0.4;

  /// The opaque end of the ramp; the top end is always [AppColors.posterScrimClear].
  final Color _color;

  /// Where the fade begins, as a fraction of the poster's height.
  final double _start;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.posterScrimClear, _color],
          stops: [_start, 1],
        ),
      ),
    );
  }
}
