import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/poster_art.dart';
import '../discover/show_detail_screen.dart';
import '../player/player_screen.dart';

/// Profile/detail page for a local library title (per the "tiles open a profile
/// page, not the player" rule). Shows the poster, file info and watch state, and
/// starts playback from the Play button here. TMDB-matched series also link out
/// to the full show page.
class LibraryDetailScreen extends StatefulWidget {
  const LibraryDetailScreen({super.key, required this.item});
  final LibraryItem item;

  @override
  State<LibraryDetailScreen> createState() => _LibraryDetailScreenState();
}

class _LibraryDetailScreenState extends State<LibraryDetailScreen> {
  late bool _keep = widget.item.keep;

  LibraryItem get item => widget.item;
  bool get _isMatchedTv => item.tmdbId != null && item.mediaType == 'tv';

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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
                  Expanded(child: _Hero(item: item)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (item.missing)
                Text(
                  "This file isn't on disk right now — its drive may be "
                  'disconnected, or it was cleaned up after watching.',
                  style: text.bodyMedium?.copyWith(color: AppColors.warning),
                )
              else
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
                  ],
                ),
              if (_keep && !item.missing) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Kept — exempt from auto-cleanup after watching.',
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item});
  final LibraryItem item;

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
                child: PosterArt(
                    posterPath: item.tmdbPosterPath, seed: title),
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
