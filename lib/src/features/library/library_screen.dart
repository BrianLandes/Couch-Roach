import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/window/window_service.dart';
import '../../data/db/database.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../data/tmdb/tv_show_summary.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/fullscreen_toggle_button.dart';
import '../archive/archive_play.dart';
import '../archive/archive_poster_card.dart';
import '../archive/archive_providers.dart';
import '../../services/acquisition/archive_browse_service.dart';
import '../discover/discover_poster_card.dart';
import '../discover/discover_providers.dart';
import '../discover/show_detail_screen.dart';
import '../player/player_screen.dart';
import 'continue_watching_card.dart';
import 'library_match_service.dart';
import 'library_providers.dart';
import 'library_service.dart';
import 'library_tile.dart';
import '../../services/subtitles/subtitle_service.dart';

/// The landing page: a Continue Watching rail (when there's anything to resume)
/// over the full library grid. It's the nav root, so it has no back button.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueAsync = ref.watch(continueWatchingProvider);
    final itemsAsync = ref.watch(libraryItemsProvider);
    final trending = ref.watch(trendingTvProvider).asData?.value ?? const [];
    final recommended = ref.watch(recommendedProvider).asData?.value ?? const [];
    final archivePicks = ref.watch(archivePicksProvider).asData?.value ?? const [];
    final resumable = continueAsync.asData?.value ?? const [];

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          // The header is pinned as a translucent overlay so the buttons + search
          // stay reachable at any scroll depth; the tiles scroll up under it.
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  // Spacer so the first rail starts below the floating header.
                  const SliverToBoxAdapter(
                      child: SizedBox(height: _kHeaderHeight)),
                  if (resumable.isNotEmpty)
                    SliverToBoxAdapter(
                        child: _ContinueWatchingRail(entries: resumable)),
                  if (recommended.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'Recommended For You',
                        shows: recommended,
                      ),
                    ),
                  if (trending.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'What to Watch Next',
                        shows: trending,
                      ),
                    ),
                  if (archivePicks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ArchiveRail(items: archivePicks),
                    ),
                  ..._librarySlivers(context, itemsAsync,
                      autofocusFirst: resumable.isEmpty),
                ],
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _Header(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the player for [item], resuming from saved watch history.
void _openPlayer(BuildContext context, LibraryItem item) {
  context.push(
    Routes.player,
    extra: PlayerArgs(
      filePath: item.filePath,
      title: item.title,
      libraryItemId: item.id,
    ),
  );
}

List<Widget> _librarySlivers(
  BuildContext context,
  AsyncValue<List<LibraryItem>> itemsAsync, {
  required bool autofocusFirst,
}) {
  return itemsAsync.when(
    loading: () => const [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
    error: (e, _) => const [
      SliverFillRemaining(
        hasScrollBody: false,
        child: _Message('Library error — see the error log.', color: AppColors.danger),
      ),
    ],
    data: (items) {
      if (items.isEmpty) {
        return const [
          SliverFillRemaining(hasScrollBody: false, child: _EmptyState()),
        ];
      }
      return [
        const SliverToBoxAdapter(child: _SectionLabel('Library')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: AppSpacing.lg,
              mainAxisSpacing: AppSpacing.lg,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return LibraryTile(
                item: item,
                autofocus: autofocusFirst && i == 0,
                onPressed: () => _openPlayer(context, item),
              );
            },
          ),
        ),
      ];
    },
  );
}

/// Height of the pinned single-row landing header. The scroll view reserves
/// this much up top; the header floats over the rest.
const double _kHeaderHeight = 96;

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final library = getIt<LibraryService>();
    return SizedBox(
      height: _kHeaderHeight,
      child: GlassSurface(
        strong: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.md,
          AppSpacing.screenPadding,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Couch Roach',
                style: text.headlineMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Scrolls horizontally (right-aligned) if too narrow to show every
            // control, so the header never overflows.
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => context.push(Routes.search),
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Search'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    ValueListenableBuilder<bool>(
                      valueListenable: library.scanning,
                      builder: (context, scanning, _) => OutlinedButton.icon(
                        onPressed: scanning
                            ? null
                            : () async {
                                await library.rescan();
                                await getIt<LibraryMatchService>()
                                    .matchUnmatched();
                                // Kick the quota-aware subtitle queue in the
                                // background so it never hammers the daily quota
                                // on a big first scan.
                                if (const AppConfig().hasOpenSubtitlesKey) {
                                  unawaited(
                                      getIt<SubtitleService>().processQueue());
                                }
                              },
                        icon: scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(scanning ? 'Scanning…' : 'Rescan'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => context.push(Routes.downloads),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Downloads'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => context.push(Routes.storageSettings),
                      icon: const Icon(Icons.folder_rounded),
                      label: const Text('Manage storage'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const FullscreenToggleButton(),
                    const IconButton(
                      onPressed: minimizeWindow,
                      icon: Icon(Icons.remove_rounded),
                      tooltip: 'Minimize to desktop',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueWatchingRail extends StatelessWidget {
  const _ContinueWatchingRail({required this.entries});
  final List<ContinueWatchingEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Continue Watching'),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return ContinueWatchingCard(
                entry: entry,
                autofocus: i == 0,
                onPressed: () => _openPlayer(context, entry.item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DiscoverRail extends StatelessWidget {
  const _DiscoverRail({required this.label, required this.shows});
  final String label;
  final List<TvShowSummary> shows;

  @override
  Widget build(BuildContext context) {
    final top = shows.take(10).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            itemCount: top.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final show = top[i];
              return DiscoverPosterCard(
                show: show,
                onPressed: () => context.push(
                  Routes.showDetail,
                  extra: ShowDetailArgs(tmdbId: show.tmdbId, name: show.name),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArchiveRail extends StatelessWidget {
  const _ArchiveRail({required this.items});
  final List<ArchiveItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Free to Watch · Public-Domain Classics'),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final item = items[i];
              return ArchivePosterCard(
                item: item,
                onPressed: () => playArchiveItem(context, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.md,
        AppSpacing.screenPadding,
        AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1.5,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: GlassSurface(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_outlined,
                size: 44, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text('Your library is empty', style: text.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add a library folder, then rescan to pull in your media.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => context.push(Routes.storageSettings),
              icon: const Icon(Icons.folder_rounded),
              label: const Text('Manage storage'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 16),
      ),
    );
  }
}
