import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/settings/settings_service.dart';
import '../../core/window/window_service.dart';
import '../../data/db/database.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/fullscreen_toggle_button.dart';
import '../archive/archive_poster_card.dart';
import '../archive/archive_providers.dart';
import '../../services/acquisition/archive_browse_service.dart';
import '../discover/discover_nav.dart';
import '../discover/discover_poster_card.dart';
import '../discover/discover_providers.dart';
import '../discover/discover_tile.dart';
import '../vpn/vpn_status_chip.dart';
import '../player/player_screen.dart';
import 'continue_watching_card.dart';
import 'library_grouping.dart';
import 'library_match_service.dart';
import 'library_providers.dart';
import 'library_service.dart';
import 'library_tile.dart';
import 'saved_titles_providers.dart';
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
    final recommended =
        ref.watch(recommendedProvider).asData?.value ?? const [];
    final popularMovies =
        ref.watch(trendingMoviesProvider).asData?.value ?? const [];
    final documentaries =
        ref.watch(documentaryMoviesProvider).asData?.value ?? const [];
    // Internet Archive is opt-in (default off); only fetch/show its rail when on.
    final iaEnabled = ref.watch(internetArchiveEnabledProvider);
    final archivePicks = iaEnabled
        ? (ref.watch(archivePicksProvider).asData?.value ??
            const <ArchiveItem>[])
        : const <ArchiveItem>[];
    final newEpisodes =
        ref.watch(newEpisodesProvider).asData?.value ?? const [];
    final favorites =
        ref.watch(favoritesProvider).asData?.value ?? const <SavedTitle>[];
    final wantToWatch =
        ref.watch(wantToWatchProvider).asData?.value ?? const <SavedTitle>[];
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
                  if (favorites.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'Favorites',
                        tiles: favorites.map(_savedTile).toList(),
                        limit: null,
                      ),
                    ),
                  if (wantToWatch.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'Want to Watch',
                        tiles: wantToWatch.map(_savedTile).toList(),
                        limit: null,
                      ),
                    ),
                  if (newEpisodes.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'New Episodes For You',
                        tiles: newEpisodes,
                      ),
                    ),
                  if (recommended.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'Recommended For You',
                        tiles: recommended.map(DiscoverTile.fromTv).toList(),
                      ),
                    ),
                  // The user's own library sits above the generic discovery
                  // rails (TV Shows / Movies / Documentaries).
                  ..._librarySlivers(context, itemsAsync,
                      autofocusFirst: resumable.isEmpty),
                  if (trending.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'TV Shows',
                        tiles: trending.map(DiscoverTile.fromTv).toList(),
                      ),
                    ),
                  if (popularMovies.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'Movies',
                        tiles: popularMovies,
                      ),
                    ),
                  if (documentaries.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DiscoverRail(
                        label: 'Documentaries',
                        tiles: documentaries,
                      ),
                    ),
                  if (archivePicks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ArchiveRail(items: archivePicks),
                    ),
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

/// Maps a saved Favorites/Want-to-watch row to the shared poster-tile
/// view-model, so those rails reuse the discovery rail + tap-to-detail routing.
DiscoverTile _savedTile(SavedTitle s) => DiscoverTile(
      tmdbId: s.tmdbId,
      title: s.name,
      mediaType: s.mediaType,
      posterPath: s.posterPath,
    );

/// Opens the detail page for a Continue Watching [item]: a matched TV episode
/// goes to its show detail (seasons/episodes), everything else to the single
/// library-title detail — mirroring the library grid's navigation.
void _openDetail(BuildContext context, LibraryItem item) {
  if (item.mediaType == 'tv' && item.tmdbId != null) {
    openShowDetail(
      context,
      tmdbId: item.tmdbId!,
      name: item.tmdbName ?? item.title,
    );
  } else {
    context.push(Routes.libraryDetail, extra: item);
  }
}

/// Drops [item] from the Continue Watching rail (the drift watch query updates
/// the rail on its own). Best-effort; a failure is logged, never surfaced as a
/// blocking error for a dismiss gesture.
void _dismissContinueWatching(LibraryItem item) {
  unawaited(
    getIt<WatchHistoryRepository>()
        .dismissFromContinueWatching(item.id)
        .catchError((Object e, StackTrace st) {
      getIt<ErrorLogService>().logError(e,
          stackTrace: st, source: 'LibraryScreen.dismissContinueWatching');
    }),
  );
}

List<Widget> _librarySlivers(
  BuildContext context,
  AsyncValue<List<LibraryItem>> itemsAsync, {
  required bool autofocusFirst,
}) {
  // The library now sits above the discovery rails, so its non-data states use
  // compact adapters (not SliverFillRemaining, which would shove those rails off
  // the screen).
  return itemsAsync.when(
    loading: () => const [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    ],
    error: (e, _) => const [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: _Message('Library error — see the error log.',
              color: AppColors.danger),
        ),
      ),
    ],
    data: (items) {
      if (items.isEmpty) {
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: _EmptyState(),
            ),
          ),
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
          sliver: Builder(builder: (context) {
            // Collapse each matched TV show's episodes into a single tile.
            final entries = groupLibraryItems(items);
            return SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: AppSpacing.lg,
                mainAxisSpacing: AppSpacing.lg,
              ),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final entry = entries[i];
                final autofocus = autofocusFirst && i == 0;
                return switch (entry) {
                  ItemEntry(:final item) => LibraryTile(
                      item: item,
                      autofocus: autofocus,
                      onPressed: () =>
                          context.push(Routes.libraryDetail, extra: item),
                    ),
                  ShowEntry(:final tmdbId, :final name) => ShowLibraryTile(
                      name: name,
                      posterPath: entry.posterPath,
                      episodeCount: entry.episodeCount,
                      autofocus: autofocus,
                      onPressed: () =>
                          openShowDetail(context, tmdbId: tmdbId, name: name),
                    ),
                };
              },
            );
          }),
        ),
      ];
    },
  );
}

/// Height of the pinned single-row landing header. The scroll view reserves
/// this much up top; the header stays fixed on top.
const double _kHeaderHeight = 84;

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final library = getIt<LibraryService>();
    return Container(
      height: _kHeaderHeight,
      // Opaque bar (no translucency) so it reads cleanly over scrolling tiles.
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.glassStroke)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
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
          const VpnStatusChip(),
          const SizedBox(width: AppSpacing.md),
          // Compact icon buttons — they all fit on one row, so nothing (least of
          // all Search) gets scrolled out of reach.
          IconButton(
            onPressed: () => context.push(Routes.search),
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search',
          ),
          ValueListenableBuilder<bool>(
            valueListenable: library.scanning,
            builder: (context, scanning, _) => IconButton(
              onPressed: scanning
                  ? null
                  : () async {
                      await library.rescan();
                      await getIt<LibraryMatchService>().matchUnmatched();
                      // Kick the quota-aware subtitle queue in the background so
                      // it never hammers the daily quota on a big first scan.
                      if (const AppConfig().hasOpenSubtitlesKey &&
                          getIt<SettingsService>().autoDownloadSubtitles) {
                        unawaited(getIt<SubtitleService>().processQueue());
                      }
                    },
              tooltip: scanning ? 'Scanning…' : 'Rescan',
              icon: scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          IconButton(
            onPressed: () => context.push(Routes.downloads),
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Downloads',
          ),
          IconButton(
            onPressed: () => context.push(Routes.settings),
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
          ),
          const FullscreenToggleButton(),
          const IconButton(
            onPressed: minimizeWindow,
            icon: Icon(Icons.remove_rounded),
            tooltip: 'Minimize to desktop',
          ),
        ],
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
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return ContinueWatchingCard(
                entry: entry,
                autofocus: i == 0,
                onPressed: () => _openPlayer(context, entry.item),
                onOpenDetails: () => _openDetail(context, entry.item),
                onRemove: () => _dismissContinueWatching(entry.item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DiscoverRail extends StatelessWidget {
  const _DiscoverRail({
    required this.label,
    required this.tiles,
    this.limit = 10,
  });
  final String label;
  final List<DiscoverTile> tiles;

  /// Max tiles to show; null shows all (the user's own lists shouldn't be
  /// truncated the way the algorithmic discovery rails are).
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final lim = limit;
    final top = lim == null ? tiles : tiles.take(lim).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            itemCount: top.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final tile = top[i];
              return DiscoverPosterCard(
                tile: tile,
                onPressed: () => openDiscoverTile(context, tile),
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
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final item = items[i];
              return ArchivePosterCard(
                item: item,
                onPressed: () =>
                    context.push(Routes.archiveDetail, extra: item),
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
              onPressed: () => context.push(Routes.settings),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open settings'),
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
