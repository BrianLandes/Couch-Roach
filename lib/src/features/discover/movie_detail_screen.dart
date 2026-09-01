import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
import '../../theme/theme.dart';
import '../../widgets/detail_scaffold.dart';
import '../../widgets/poster_art.dart';
import 'resume_button.dart';
import '../library/save_title_buttons.dart';
import '../acquire/acquire_button.dart';
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
    // The tile we were pushed with may be sparse — a saved / Alexa-queued /
    // recently-downloaded title carries only what its local row cached. Fetch
    // the full profile by id and fill in the gaps; until it lands, `full` is
    // just the tile we already have, so the page paints immediately.
    final full = hydrateTile(
      tile,
      ref.watch(movieTileProvider(tile.tmdbId)).asData?.value,
    );

    return DetailScaffold(
      title: full.title,
      children: [
        _Hero(tile: full),
        const SizedBox(height: AppSpacing.lg),
        // Resume + Play/Acquire + Trailers + Favorite + Want-to-watch share one
        // wrapping row (the save toggles live in SaveTitleButtons).
        SaveTitleButtons(
          tmdbId: tile.tmdbId,
          mediaType: 'movie',
          name: full.title,
          posterPath: full.posterPath,
          leading: [
            // Resume the in-progress movie, if any (special accent color).
            ResumeButton(tmdbId: tile.tmdbId),
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
              )
            else
              AcquireButton(
                autofocus: true,
                title: full.title,
                meta: ShowMeta(
                  title: full.title,
                  tmdbId: tile.tmdbId,
                  mediaType: 'movie',
                ),
              ),
            if (trailerUrl != null)
              OutlinedButton.icon(
                onPressed: () => showTrailerPicker(
                  context,
                  tmdbId: tile.tmdbId,
                  isTv: false,
                  title: full.title,
                ),
                icon: const Icon(Icons.movie_outlined),
                label: const Text('Trailers'),
              ),
          ],
        ),
        if (full.overview.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(full.overview,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ],
      ],
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
