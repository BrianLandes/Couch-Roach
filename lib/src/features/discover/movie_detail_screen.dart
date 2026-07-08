import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/poster_art.dart';
import '../player/player_screen.dart';
import 'discover_providers.dart';
import 'discover_tile.dart';
import 'trailer_picker.dart';

/// Metadata page for a TMDB **movie** (the movie counterpart to the TV show
/// detail page). Shows poster, year, rating and overview; if the movie is
/// already in the local library it can be played from here. Acquiring a movie
/// you don't own isn't wired yet — that arrives with the generalized play flow.
class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({super.key, required this.tile});
  final DiscoverTile tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final local = ref.watch(localTitleProvider(tile.tmdbId)).asData?.value;
    final trailerUrl =
        ref.watch(trailerUrlProvider((tile.tmdbId, false))).asData?.value;

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.md,
              AppSpacing.screenPadding,
              AppSpacing.screenPadding,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppBackButton(),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _Hero(tile: tile)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  if (local != null)
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => context.push(
                        Routes.player,
                        extra: PlayerArgs(
                          filePath: local.filePath,
                          title: local.tmdbName ?? local.title,
                          libraryItemId: local.id,
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  if (trailerUrl != null)
                    OutlinedButton.icon(
                      autofocus: local == null,
                      onPressed: () => showTrailerPicker(
                        context,
                        tmdbId: tile.tmdbId,
                        isTv: false,
                        title: tile.title,
                      ),
                      icon: const Icon(Icons.movie_outlined),
                      label: const Text('Trailers'),
                    ),
                ],
              ),
              if (local == null) ...[
                const SizedBox(height: AppSpacing.md),
                GlassSurface(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 20, color: AppColors.textTertiary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          "Not in your library yet — you can't download this one "
                          'from here for now.',
                          style: text.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (tile.overview.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(tile.overview,
                    style: text.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.tile});
  final DiscoverTile tile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meta = [
      if (tile.year != null) '${tile.year}',
      if (tile.voteAverage != null && tile.voteAverage! > 0)
        '★ ${tile.voteAverage!.toStringAsFixed(1)}',
    ].join('  ·  ');

    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: AppRadii.rMd,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: PosterArt(posterPath: tile.posterPath, seed: tile.title),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tile.title, style: text.headlineSmall),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(meta,
                      style: text.labelLarge
                          ?.copyWith(color: AppColors.secondary)),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text('Movie · TMDB',
                    style: text.labelSmall
                        ?.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
