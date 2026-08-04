import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../../data/tmdb/season.dart';
import '../../data/tmdb/tmdb_images.dart';
import '../../data/tmdb/tv_show_details.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/detail_scaffold.dart';
import '../../widgets/resume_button.dart';
import '../../widgets/poster_art.dart';
import '../../services/acquisition/acquisition.dart';
import '../library/delete_actions.dart';
import '../library/save_title_buttons.dart';
import '../library/saved_titles_providers.dart';
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

  /// Pin/unpin this whole show as "keep" (SavedTitles, per-show) so auto-cleanup
  /// spares its episodes — current *and* any downloaded later. The live
  /// savedTitleProvider stream flips the button between Keep/Kept.
  Future<void> _toggleShowKeep(TvShowDetails details, bool keep) async {
    await getIt<SavedTitlesRepository>().setKeep(
      tmdbId: details.tmdbId,
      mediaType: 'tv',
      name: details.name,
      posterPath: details.posterPath,
      value: keep,
    );
  }

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
          // A TMDB fetch failure (offline, rate-limited, no key) shouldn't strand
          // files that are already on disk — fall back to a playable list of what
          // we have, and only show the bare notice when there's nothing local.
          error: (e, _) => [
            _LocalOnlyFallback(
              tmdbId: widget.args.tmdbId,
              name: widget.args.name,
              notice: 'Could not load details — see the error log.',
            ),
          ],
          data: (details) => details == null
              ? [
                  _LocalOnlyFallback(
                    tmdbId: widget.args.tmdbId,
                    name: widget.args.name,
                    notice: 'Not found on TMDB.',
                  ),
                ]
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
    // Own any episodes of this show? If so, offer a show-level "Keep" that pins
    // the whole show against auto-cleanup — the TV counterpart to a movie's
    // Keep. The pin lives on SavedTitles (per-show), so it also spares episodes
    // downloaded after pinning; "Kept" reflects that show-level flag.
    final local =
        ref.watch(localEpisodesProvider(details.tmdbId)).asData?.value ??
            const <(int, int), LibraryItem>{};
    final owned = local.isNotEmpty;
    final kept = ref
            .watch(savedTitleProvider(
                (tmdbId: details.tmdbId, mediaType: 'tv')))
            .asData
            ?.value
            ?.keptAt !=
        null;

    return [
      _Hero(details: details),
      const SizedBox(height: AppSpacing.md),
      // Trailers + Keep + Favorite + Want-to-watch share one wrapping row.
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
          // Pin the whole show so auto-cleanup never reaps its episodes after a
          // watch (uses the app's "pin" icon, as in the Settings cleanup queue).
          if (owned)
            OutlinedButton.icon(
              onPressed: () => _toggleShowKeep(details, !kept),
              icon: Icon(
                  kept ? Icons.push_pin_rounded : Icons.push_pin_outlined),
              label: Text(kept ? 'Kept' : 'Keep'),
            ),
          // Download whole seasons — shares the row rather than sitting on its
          // own line above the episode list.
          if (seasons.isNotEmpty && selected != null)
            _DownloadAllButton(
              tmdbId: details.tmdbId,
              showName: details.name,
              selectedSeason: selected,
              seasonNumbers: [for (final s in seasons) s.seasonNumber],
            ),
          // Delete downloaded episodes — a season or the whole show.
          if (owned)
            _DeleteShowButton(
              tmdbId: details.tmdbId,
              showName: details.name,
              posterPath: details.posterPath,
              local: local,
              selectedSeason: selected,
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
      if (seasons.isNotEmpty && selected != null) ...[
        _SeasonChips(
          seasons: seasons,
          selected: selected,
          local: local,
          onSelect: (n) => setState(() => _season = n),
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

/// Shown when TMDB details won't load (offline, rate-limited, no key, or a stale
/// match) but the show still has files on disk: a minimal poster/name header and
/// a playable list of the local episodes, using the name/poster the library row
/// already cached. Falls back to [notice] only when there's nothing local to
/// play, so a genuinely-unmatched show still reads as such.
class _LocalOnlyFallback extends ConsumerWidget {
  const _LocalOnlyFallback({
    required this.tmdbId,
    required this.name,
    required this.notice,
  });

  final int tmdbId;
  final String name;
  final String notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final itemsAsync = ref.watch(localShowItemsProvider(tmdbId));
    final items = itemsAsync.asData?.value ?? const <LibraryItem>[];

    if (itemsAsync.isLoading) {
      return const _CenteredNotice(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return _CenteredNotice(child: Text(notice));
    }

    final posterPath =
        items.map((i) => i.tmdbPosterPath).firstWhere((p) => p != null,
            orElse: () => null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassSurface(
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
                    child: PosterArt(posterPath: posterPath, seed: name),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: text.headlineSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      "Couldn't load full details from TMDB — here are the "
                      'episodes you have downloaded.',
                      style: text.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _LocalItemRow(item: item, showName: name),
          ),
      ],
    );
  }
}

/// One playable local file in the [_LocalOnlyFallback] list: its SxxExx (or the
/// filename title when it isn't a parsed episode) and a Play button.
class _LocalItemRow extends StatelessWidget {
  const _LocalItemRow({required this.item, required this.showName});

  final LibraryItem item;
  final String showName;

  String get _label {
    final s = item.season, e = item.episode;
    if (s != null && e != null) {
      return 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';
    }
    return item.tmdbName ?? item.title;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(_label,
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton.icon(
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
          ),
        ],
      ),
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
    final result = switch (scope) {
      _DownloadScope.season => await downloadSeason(
          showName: showName, tmdbId: tmdbId, season: selectedSeason),
      _DownloadScope.all => await downloadAllSeasons(
          showName: showName, tmdbId: tmdbId, seasonNumbers: seasonNumbers),
    };
    messenger.showSnackBar(SnackBar(content: Text(_downloadMessage(result))));
  }

  /// Snackbar wording for what actually queued — a pack (one torrent covering
  /// many episodes) reads differently from N individual episodes.
  String _downloadMessage(BulkDownloadResult r) {
    if (r.isEmpty) {
      return 'Nothing new — those episodes are already here or downloading.';
    }
    final parts = [
      if (r.packs > 0) '${r.packs} pack${r.packs == 1 ? '' : 's'}',
      if (r.episodes > 0)
        '${r.episodes} episode${r.episodes == 1 ? '' : 's'}',
    ];
    return 'Queued ${parts.join(' + ')} to download.';
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _run(context),
      icon: const Icon(Icons.download_rounded),
      label: const Text('Download…'),
    );
  }
}

enum _DeleteScope { season, all }

/// "Delete…" for a downloaded show: asks whether to delete the selected season's
/// episodes or every downloaded episode, confirms, then removes the files +
/// rows. A whole-show delete also clears the show-level "keep" pin so it doesn't
/// silently re-keep a future re-download.
class _DeleteShowButton extends ConsumerWidget {
  const _DeleteShowButton({
    required this.tmdbId,
    required this.showName,
    required this.posterPath,
    required this.local,
    required this.selectedSeason,
  });

  final int tmdbId;
  final String showName;
  final String? posterPath;
  final Map<(int, int), LibraryItem> local;
  final int? selectedSeason;

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final scope = await showDialog<_DeleteScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete downloads'),
        content: Text(selectedSeason != null
            ? 'Delete the downloaded episodes of Season $selectedSeason, or '
                'every downloaded episode of this show?'
            : 'Delete every downloaded episode of this show?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (selectedSeason != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, _DeleteScope.season),
              child: Text('Season $selectedSeason'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, _DeleteScope.all),
            child: const Text('All episodes'),
          ),
        ],
      ),
    );
    if (scope == null || !context.mounted) return;

    final items = switch (scope) {
      _DeleteScope.season => [
          for (final e in local.entries)
            if (e.key.$1 == selectedSeason) e.value,
        ],
      _DeleteScope.all => local.values.toList(),
    };
    final what = scope == _DeleteScope.season
        ? 'Season $selectedSeason of $showName'
        : 'all of $showName';
    final removed = await confirmAndDelete(context, what: what, items: items);
    if (removed == 0) return;

    // A whole-show delete clears the per-show keep pin (no stale pin left to
    // silently re-keep a future re-download).
    if (scope == _DeleteScope.all) {
      await getIt<SavedTitlesRepository>().setKeep(
          tmdbId: tmdbId,
          mediaType: 'tv',
          name: showName,
          posterPath: posterPath,
          value: false);
    }
    ref.invalidate(localEpisodesProvider(tmdbId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => _run(context, ref),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
      icon: const Icon(Icons.delete_outline_rounded),
      label: const Text('Delete…'),
    );
  }
}

/// How much of a season is on disk, for the season chip's download indicator.
enum SeasonDownloadState { none, some, all }

/// Classify a season from its [downloaded] episode count against [total] (the
/// season's episode count, or null when TMDB doesn't report it — then any
/// downloaded reads as "some", never "all"). Pure + tested.
SeasonDownloadState seasonDownloadState({required int downloaded, int? total}) {
  if (downloaded <= 0) return SeasonDownloadState.none;
  if (total != null && total > 0 && downloaded >= total) {
    return SeasonDownloadState.all;
  }
  return SeasonDownloadState.some;
}

class _SeasonChips extends StatelessWidget {
  const _SeasonChips({
    required this.seasons,
    required this.selected,
    required this.local,
    required this.onSelect,
  });

  final List<SeasonSummary> seasons;
  final int selected;

  /// The downloaded episodes for this show, keyed (season, episode) — drives the
  /// per-season "downloaded" indicator.
  final Map<(int, int), LibraryItem> local;
  final ValueChanged<int> onSelect;

  /// Small leading icon on a chip: filled download-done (green) when the whole
  /// season is on disk, a plain download arrow (muted) when only some is, and
  /// nothing when none is.
  Widget? _indicator(SeasonDownloadState state) => switch (state) {
        SeasonDownloadState.none => null,
        SeasonDownloadState.some => const Icon(Icons.download_rounded,
            size: 16, color: AppColors.textSecondary),
        SeasonDownloadState.all => const Icon(Icons.download_done_rounded,
            size: 16, color: AppColors.success),
      };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final s in seasons)
          _seasonChip(s),
      ],
    );
  }

  Widget _seasonChip(SeasonSummary s) {
    final downloaded =
        local.keys.where((k) => k.$1 == s.seasonNumber).length;
    final state = seasonDownloadState(
        downloaded: downloaded, total: s.episodeCount);
    final chip = ChoiceChip(
      label: Text(s.name),
      avatar: _indicator(state),
      // Our avatar is the download indicator; the selected state shows via the
      // chip's fill, so drop the default selected checkmark to avoid two icons.
      showCheckmark: false,
      selected: s.seasonNumber == selected,
      onSelected: (_) => onSelect(s.seasonNumber),
    );
    if (state == SeasonDownloadState.none) return chip;
    final total = s.episodeCount;
    final message = state == SeasonDownloadState.all
        ? 'All episodes downloaded'
        : total != null
            ? '$downloaded of $total downloaded'
            : '$downloaded downloaded';
    return Tooltip(message: message, child: chip);
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
    final watched = ref.watch(completedEpisodesProvider(tmdbId)).asData?.value ??
        const <(int, int)>{};

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
                  watched: watched.contains((seasonNumber, ep.episodeNumber)),
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
    this.watched = false,
  });
  final EpisodeSummary episode;
  final int tmdbId;
  final int seasonNumber;
  final String showName;
  final LibraryItem? local;

  /// Whether this episode has been watched (played to completion) — shows a check.
  final bool watched;

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
                Row(
                  children: [
                    if (watched) ...[
                      const Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.success),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Text(
                        '${episode.episodeNumber}. ${episode.name}',
                        style: text.titleMedium?.copyWith(
                          color: watched ? AppColors.textSecondary : null,
                        ),
                      ),
                    ),
                  ],
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

class _Availability extends ConsumerWidget {
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

  /// Delete this one downloaded episode (from the Play button's overflow menu),
  /// then refresh the row so it drops back to a Download control.
  Future<void> _deleteEpisode(
      BuildContext context, WidgetRef ref, LibraryItem item) async {
    final s = seasonNumber.toString().padLeft(2, '0');
    final e = episode.episodeNumber.toString().padLeft(2, '0');
    final removed =
        await confirmAndDelete(context, what: '$showName S${s}E$e', items: [item]);
    if (removed > 0) ref.invalidate(localEpisodesProvider(tmdbId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = local;
    // Already on disk → play it from the library (records watch history), with
    // an overflow menu to delete it (mirrors the acquire button's "more" menu).
    if (item != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: FilledButton.icon(
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
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon:
                    const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: () => _deleteEpisode(context, ref, item),
                child: const Text('Delete episode'),
              ),
            ],
            builder: (context, controller, _) => IconButton(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More options',
            ),
          ),
        ],
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
