import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/tmdb/tmdb_images.dart';
import '../theme/theme.dart';

/// A poster background: the TMDB image when matched, otherwise a deterministic
/// placeholder gradient (stable per title). Falls back to the gradient on load
/// error too, so a flaky network never leaves a blank tile.
class PosterArt extends StatelessWidget {
  const PosterArt({super.key, required this.posterPath, required this.seed});

  final String? posterPath;
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

    final url = TmdbImages.poster(posterPath);
    if (url == null) return fallback;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
