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
import '../../widgets/detail_scaffold.dart';
import '../../widgets/resume_button.dart';
import '../../widgets/poster_art.dart';
import '../../services/acquisition/acquisition.dart';
import '../library/save_title_buttons.dart';
import '../acquire/acquire_button.dart';
import '../acquire/acquire_play.dart';
import '../player/player_screen.dart';
import 'discover_providers.dart';
import 'new_episodes.dart';
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
    // The show name is known from the route args even before TMDB loads, so the
    // pinned header (and back button) are stable across all three states.
    return DetailScaffold(
      title: widget.args.name,
      children: [
        ...detailAsync.when(
          loading: () =>
              const [_CenteredNotice(child: CircularProgressIndicator())],
          error: (e, _) => const [
            _CenteredNotice(
              child: Text(
                'Could not load details — see the error log.',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
          data: (details) => details == null
              ? const [_CenteredNotice(child: Text('Not found on TMDB'))]
              : _contentChildren(details),
        ),
      ],
    );
  }

  List<Widget> _contentChildren(TvShowDetails details) {
    final seasons = details.seasons
        .where((s) => s.seasonNumber >= 1)
        .toList(growable: false);
    final selected =
        _season ?? (seasons.isNotEmpty ? seasons.first.seasonNumber : null);
    final trailerUrl =
        ref.watch(trailerUrlProvider((details.tmdbId, true))).asData?.value;

    return [
      _Hero(details: details),
      const SizedBox(height: AppSpacing.md),
      // Trailers + Favorite + Want-to-watch share one wrapping row.
      SaveTitleButtons(
        tmdbId: details.tmdbId,
        mediaType: 'tv',
        name: details.name,
        posterPath: details.posterPath,
        leading: [
          // Resume the most recently watched episode, if any (special accent).
          ResumeButton(tmdbId: details.tmdbId),
          if (trailerUrl != null)
            OutlinedButton.icon(
              onPressed: () => showTrailerPicker(
                context,
                tmdbId: details.tmdbId,
                isTv: true,
                title: details.name,
              ),
              icon: const Icon(Icons.movie_outlined),
              label: const Text('Trailers'),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
      if (seasons.isNotEmpty && selected != null) ...[
        _SeasonChips(
          seasons: seasons,
          selected: selected,
          onSelect: (n) => setState(() => _season = n),
        ),
        const SizedBox(height: AppSpacing.sm),
        _DownloadAllButton(
          tmdbId: details.tmdbId,
          showName: details.name,
          selectedSeason: selected,
          seasonNumbers: [for (final s in seasons) s.seasonNumber],
        ),
        const SizedBox(height: AppSpacing.md),
        _EpisodeList(
          tmdbId: details.tmdbId,
          seasonNumber: selected,
          showName: details.name,
        ),
      ],
    ];
  }
}

/// A loading/error/empty notice, dropped a little below the pinned header so it
/// isn't tucked under it in the detail scaffold's scroll body.
class _CenteredNotice extends StatelessWidget {
  const _CenteredNotice({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl * 2),
      child: Center(child: child),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.details});
  final TvShowDetails details;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final year =
        details.firstAirDate != null && details.firstAirDate!.length >= 4
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
                child: PosterArt(
                    posterPath: details.posterPath, seed: details.name),
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
                      for (final g in details.genres) Chip(label: Text(g.name)),
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

enum _DownloadScope { season, all }

/// "Download…" for a whole show: asks whether to grab every aired episode of the
/// selected season or of all seasons, then queues them as background downloads
/// through the acquisition seam (skipping ones already local / downloading).
class _DownloadAllButton extends StatelessWidget {
  const _DownloadAllButton({
    required this.tmdbId,
    required this.showName,
    required this.selectedSeason,
    required this.seasonNumbers,
  });

  final int tmdbId;
  final String showName;
  final int selectedSeason;
  final List<int> seasonNumbers;

  Future<void> _run(BuildContext context) async {
    final scope = await showDialog<_DownloadScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download episodes'),
        content: Text(
          'Download every aired episode of Season $selectedSeason, or of all '
          '${seasonNumbers.length} season${seasonNumbers.length == 1 ? '' : 's'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DownloadScope.season),
            child: Text('Season $selectedSeason'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _DownloadScope.all),
            child: const Text('All seasons'),
          ),
        ],
      ),
    );
    if (scope == null || !context.mounted) return;
    if (!await ensureStreamingVpn(context) || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Queuing downloads…')),
    );
    final queued = switch (scope) {
      _DownloadScope.season => await downloadSeason(
          showName: showName, tmdbId: tmdbId, season: selectedSeason),
      _DownloadScope.all => await downloadAllSeasons(
          showName: showName, tmdbId: tmdbId, seasonNumbers: seasonNumbers),
    };
    messenger.showSnackBar(SnackBar(
      content: Text(queued == 0
          ? 'Nothing new — those episodes are already here or downloading.'
          : 'Queued $queued episode${queued == 1 ? '' : 's'} to download.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => _run(context),
        icon: const Icon(Icons.download_rounded),
        label: const Text('Download…'),
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

    // Not local and not yet aired → there's nothing to acquire; show when it's
    // due instead of a dead Download button.
    final airDate =
        episode.airDate == null ? null : DateTime.tryParse(episode.airDate!);
    if (!isAired(airDate, DateTime.now())) {
      return _UnreleasedBadge(airDate: airDate);
    }

    // Aired but not local → inline Download → progress → Play.
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

/// Shown in place of the Download button for an episode that hasn't aired yet:
/// its air date when TMDB has one, otherwise a plain "not yet released".
class _UnreleasedBadge extends StatelessWidget {
  const _UnreleasedBadge({this.airDate});
  final DateTime? airDate;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final date = airDate;
    final label = date == null
        ? 'Not yet released'
        : 'Airs ${_months[date.month - 1]} ${date.day}, ${date.year}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule_rounded,
            size: 16, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Text(label,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}
