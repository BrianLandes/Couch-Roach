import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database.dart';
import '../../data/tmdb/season.dart';
import '../../data/tmdb/tmdb_images.dart';
import '../../data/tmdb/tv_show_details.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/poster_art.dart';
import '../../services/acquisition/acquisition.dart';
import '../acquire/acquire_button.dart';
import '../player/player_screen.dart';
import 'discover_providers.dart';
import 'trailer_picker.dart';

/// Arguments for the show detail screen (passed via go_router `extra`).
class ShowDetailArgs {
  const ShowDetailArgs({required this.tmdbId, required this.name});
  final int tmdbId;
  final String name;
}

/// TMDB show detail: backdrop, synopsis/rating/genres, and a season → episode
/// list. Episodes present in the library get a Play button (acquisition of
/// missing ones comes with M4).
class ShowDetailScreen extends ConsumerStatefulWidget {
  const ShowDetailScreen({super.key, required this.args});
  final ShowDetailArgs args;

  @override
  ConsumerState<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends ConsumerState<ShowDetailScreen> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(tvDetailsProvider(widget.args.tmdbId));
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: detailAsync.when(
            loading: () => _framed(
              const Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _framed(
              const Center(
                child: Text(
                  'Could not load details — see the error log.',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ),
            data: (details) => details == null
                ? _framed(const Center(child: Text('Not found on TMDB')))
                : _content(details),
          ),
        ),
      ),
    );
  }

  // A back button over arbitrary body content (loading / error states).
  Widget _framed(Widget body) {
    return Stack(
      children: [
        Positioned.fill(child: body),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Align(alignment: Alignment.topLeft, child: AppBackButton()),
        ),
      ],
    );
  }

  Widget _content(TvShowDetails details) {
    final seasons =
        details.seasons.where((s) => s.seasonNumber >= 1).toList(growable: false);
    final selected = _season ??
        (seasons.isNotEmpty ? seasons.first.seasonNumber : null);
    final trailerUrl =
        ref.watch(trailerUrlProvider((details.tmdbId, true))).asData?.value;

    return ListView(
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
            Expanded(child: _Hero(details: details)),
          ],
        ),
        if (trailerUrl != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => showTrailerPicker(
                context,
                tmdbId: details.tmdbId,
                isTv: true,
                title: details.name,
              ),
              icon: const Icon(Icons.movie_outlined),
              label: const Text('Trailers'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (seasons.isNotEmpty && selected != null) ...[
          _SeasonChips(
            seasons: seasons,
            selected: selected,
            onSelect: (n) => setState(() => _season = n),
          ),
          const SizedBox(height: AppSpacing.md),
          _EpisodeList(
            tmdbId: details.tmdbId,
            seasonNumber: selected,
            showName: details.name,
          ),
        ],
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.details});
  final TvShowDetails details;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final year = details.firstAirDate != null && details.firstAirDate!.length >= 4
        ? details.firstAirDate!.substring(0, 4)
        : null;
    final meta = [
      if (year != null) year,
      if (details.numberOfSeasons != null)
        '${details.numberOfSeasons} season${details.numberOfSeasons == 1 ? '' : 's'}',
      if (details.voteAverage != null && details.voteAverage! > 0)
        '★ ${details.voteAverage!.toStringAsFixed(1)}',
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
                child: PosterArt(posterPath: details.posterPath, seed: details.name),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(details.name, style: text.headlineSmall),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(meta,
                      style: text.labelLarge
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
                if (details.genres.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final g in details.genres)
                        Chip(label: Text(g.name)),
                    ],
                  ),
                ],
                if (details.overview.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(details.overview, style: text.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonChips extends StatelessWidget {
  const _SeasonChips({
    required this.seasons,
    required this.selected,
    required this.onSelect,
  });

  final List<SeasonSummary> seasons;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final s in seasons)
          ChoiceChip(
            label: Text(s.name),
            selected: s.seasonNumber == selected,
            onSelected: (_) => onSelect(s.seasonNumber),
          ),
      ],
    );
  }
}

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({
    required this.tmdbId,
    required this.seasonNumber,
    required this.showName,
  });
  final int tmdbId;
  final int seasonNumber;
  final String showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonAsync = ref.watch(seasonProvider((tmdbId, seasonNumber)));
    final localAsync = ref.watch(localEpisodesProvider(tmdbId));
    final local = localAsync.asData?.value ?? const {};

    return seasonAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const Text(
        'Could not load episodes.',
        style: TextStyle(color: AppColors.danger),
      ),
      data: (season) {
        if (season == null || season.episodes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('No episodes listed.'),
          );
        }
        return Column(
          children: [
            for (final ep in season.episodes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _EpisodeRow(
                  episode: ep,
                  local: local[(seasonNumber, ep.episodeNumber)],
                  tmdbId: tmdbId,
                  seasonNumber: seasonNumber,
                  showName: showName,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.tmdbId,
    required this.seasonNumber,
    required this.showName,
    this.local,
  });
  final EpisodeSummary episode;
  final int tmdbId;
  final int seasonNumber;
  final String showName;
  final LibraryItem? local;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final still = TmdbImages.still(episode.stillPath);
    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: ClipRRect(
              borderRadius: AppRadii.rSm,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: still == null
                    ? const ColoredBox(color: AppColors.glassFill)
                    : CachedNetworkImage(
                        imageUrl: still,
                        fit: BoxFit.cover,
                        // Thumbnail-sized decode — the row is ~128px wide.
                        memCacheWidth: 320,
                        placeholder: (_, __) =>
                            const ColoredBox(color: AppColors.glassFill),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: AppColors.glassFill),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${episode.episodeNumber}. ${episode.name}',
                  style: text.titleMedium,
                ),
                if (episode.runtime != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('${episode.runtime} min',
                      style: text.labelMedium
                          ?.copyWith(color: AppColors.textTertiary)),
                ],
                if (episode.overview.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    episode.overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _Availability(
            local: local,
            tmdbId: tmdbId,
            seasonNumber: seasonNumber,
            episode: episode,
            showName: showName,
          ),
        ],
      ),
    );
  }
}

class _Availability extends StatelessWidget {
  const _Availability({
    required this.tmdbId,
    required this.seasonNumber,
    required this.episode,
    required this.showName,
    this.local,
  });
  final int tmdbId;
  final int seasonNumber;
  final EpisodeSummary episode;
  final String showName;
  final LibraryItem? local;

  @override
  Widget build(BuildContext context) {
    final item = local;
    // Already on disk → play it from the library (records watch history).
    if (item != null) {
      return FilledButton.icon(
        onPressed: () => context.push(
          Routes.player,
          extra: PlayerArgs(
            filePath: item.filePath,
            title: item.tmdbName ?? item.title,
            libraryItemId: item.id,
          ),
        ),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Play'),
      );
    }

    // Not local → inline Download → progress → Play.
    final s = seasonNumber.toString().padLeft(2, '0');
    final e = episode.episodeNumber.toString().padLeft(2, '0');
    return AcquireButton(
      title: '$showName — S${s}E$e'
          '${episode.name.isEmpty ? '' : ' · ${episode.name}'}',
      meta: ShowMeta(title: showName, tmdbId: tmdbId, mediaType: 'tv'),
      season: seasonNumber,
      episode: episode.episodeNumber,
    );
  }
}
