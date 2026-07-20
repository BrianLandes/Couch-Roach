import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/detail_scaffold.dart';
import '../../widgets/poster_art.dart';
import '../discover/discover_providers.dart';
import '../discover/show_detail_screen.dart';
import '../discover/trailer_picker.dart';
import '../player/player_screen.dart';
import 'delete_actions.dart';

/// Profile/detail page for a local library title (per the "tiles open a profile
/// page, not the player" rule). Shows the poster, file info and watch state, and
/// starts playback from the Play button here. A TMDB-matched title is enriched
/// with the same profile discovery shows — rating, overview and trailers, all
/// fetched by id (the row itself only cached id/name/poster) — and a matched
/// series also links out to the full show page.
class LibraryDetailScreen extends ConsumerStatefulWidget {
  const LibraryDetailScreen({super.key, required this.item});
  final LibraryItem item;

  @override
  ConsumerState<LibraryDetailScreen> createState() =>
      _LibraryDetailScreenState();
}

class _LibraryDetailScreenState extends ConsumerState<LibraryDetailScreen> {
  late bool _keep = widget.item.keep;

  LibraryItem get item => widget.item;
  bool get _isMatched => item.tmdbId != null;
  bool get _isMovie => item.mediaType == 'movie';
  bool get _isMatchedTv => _isMatched && item.mediaType == 'tv';

  void _play() {
    context.push(
      Routes.player,
      extra: PlayerArgs(
        filePath: item.filePath,
        title: item.tmdbName ?? item.title,
        libraryItemId: item.id,
      ),
    );
  }

  Future<void> _toggleKeep() async {
    final next = !_keep;
    setState(() => _keep = next); // optimistic
    await getIt<LibraryRepository>().setKeep(item.id, next);
  }

  /// Delete this title's file (or forget a missing one), then leave the now-gone
  /// detail page for the library.
  Future<void> _delete() async {
    final removed = await confirmAndDelete(
      context,
      what: item.tmdbName ?? item.title,
      items: [item],
    );
    if (removed > 0 && mounted) context.pop();
  }

  Widget get _deleteButton => OutlinedButton.icon(
        onPressed: _delete,
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
        icon: const Icon(Icons.delete_outline_rounded),
        label: Text(item.missing ? 'Remove from library' : 'Delete'),
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // Enrich a matched title with the TMDB profile its library row never stored
    // (rating, overview, trailer) — fetched by id, cheap and provider-cached.
    var overview = '';
    String? ratingMeta;
    if (_isMatched) {
      if (_isMovie) {
        final t = ref.watch(movieTileProvider(item.tmdbId!)).asData?.value;
        if (t != null) {
          overview = t.overview;
          ratingMeta = _metaLine(year: t.year, rating: t.voteAverage);
        }
      } else {
        final d = ref.watch(tvDetailsProvider(item.tmdbId!)).asData?.value;
        if (d != null) {
          overview = d.overview;
          ratingMeta =
              _metaLine(year: _yearOf(d.firstAirDate), rating: d.voteAverage);
        }
      }
    }
    final trailerUrl = _isMatched
        ? ref.watch(trailerUrlProvider((item.tmdbId!, !_isMovie))).asData?.value
        : null;

    return DetailScaffold(
      title: item.tmdbName ?? item.title,
      children: [
        _Hero(item: item, ratingMeta: ratingMeta),
        const SizedBox(height: AppSpacing.lg),
        if (item.missing) ...[
          Text(
            "This file isn't on disk right now — its drive may be "
            'disconnected, or it was cleaned up after watching.',
            style: text.bodyMedium?.copyWith(color: AppColors.warning),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(alignment: Alignment.centerLeft, child: _deleteButton),
        ] else
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              FilledButton.icon(
                autofocus: true,
                onPressed: _play,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
              // Pin as "keep" so auto-cleanup never deletes it after a
              // watch — for the couple of rewatch titles.
              OutlinedButton.icon(
                onPressed: _toggleKeep,
                icon: Icon(_keep
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded),
                label: Text(_keep ? 'Kept' : 'Keep'),
              ),
              if (trailerUrl != null)
                OutlinedButton.icon(
                  onPressed: () => showTrailerPicker(
                    context,
                    tmdbId: item.tmdbId!,
                    isTv: !_isMovie,
                    title: item.tmdbName ?? item.title,
                  ),
                  icon: const Icon(Icons.movie_outlined),
                  label: const Text('Trailers'),
                ),
              if (_isMatchedTv)
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    Routes.showDetail,
                    extra: ShowDetailArgs(
                      tmdbId: item.tmdbId!,
                      name: item.tmdbName ?? item.title,
                    ),
                  ),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('View full show'),
                ),
              _deleteButton,
            ],
          ),
        if (overview.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(overview,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ],
        if (_keep && !item.missing) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Kept — exempt from auto-cleanup after watching.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// "2008  ·  ★ 8.1" from a year and/or rating, or null when neither is present.
String? _metaLine({int? year, double? rating}) {
  final parts = [
    if (year != null) '$year',
    if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}',
  ];
  return parts.isEmpty ? null : parts.join('  ·  ');
}

/// The four-digit year from a TMDB `YYYY-MM-DD` date, or null.
int? _yearOf(String? date) =>
    (date != null && date.length >= 4) ? int.tryParse(date.substring(0, 4)) : null;

class _Hero extends StatelessWidget {
  const _Hero({required this.item, this.ratingMeta});
  final LibraryItem item;

  /// TMDB year/rating line for a matched title, shown under the badge.
  final String? ratingMeta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = item.tmdbName ?? item.title;
    final badge = item.season != null && item.episode != null
        ? 'Season ${item.season} · Episode ${item.episode}'
        : (item.mediaType == 'movie' ? 'Movie' : null);
    final tech = [
      if (item.container != null) item.container!.toUpperCase(),
      if (item.videoCodec != null) item.videoCodec!,
      if (item.hasEmbeddedEnSub) 'Subtitles',
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
                child: PosterArt(posterPath: item.tmdbPosterPath, seed: title),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.headlineSmall),
                if (badge != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(badge,
                      style: text.labelLarge
                          ?.copyWith(color: AppColors.secondary)),
                ],
                if (ratingMeta != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(ratingMeta!,
                      style: text.labelLarge
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
                if (tech.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(tech,
                      style: text.labelMedium
                          ?.copyWith(color: AppColors.textTertiary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
