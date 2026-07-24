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
import '../discover/taste.dart';
import '../discover/taste_providers.dart';
import '../../services/alexa/alexa_inbox_service.dart';
import '../settings/storage_providers.dart';
import '../vpn/vpn_status_chip.dart';
import '../player/player_screen.dart';
import 'continue_watching_card.dart';
import 'library_grouping.dart';
import 'library_match_service.dart';
import 'library_providers.dart';
import 'library_service.dart';
import 'library_tile.dart';
import 'saved_titles_providers.dart';
import 'unmatched_show_sheet.dart';
import '../../services/subtitles/subtitle_service.dart';

/// The landing page: a Continue Watching rail (when there's anything to resume)
/// over the full library grid. It's the nav root, so it has no back button.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with RouteAware {
  // Owned so the always-visible vertical scrollbar (AppScrollBehavior) has a
  // live controller to attach its thumb to.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // First entry: drain anything queued by voice (throttled, so it harmlessly
    // coalesces with the startup drain in main()).
    _drainInbox();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  /// Fired when a screen pushed on top of the landing page is popped and this
  /// page becomes visible again — the second Alexa drain trigger.
  @override
  void didPopNext() => _drainInbox();

  /// Drain the Alexa inbox, fire-and-forget. Self-throttled and silent; a
  /// failure is logged, never surfaced (a queued title just waits for the next
  /// trigger).
  void _drainInbox() {
    unawaited(getIt<AlexaInboxService>().drain());
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _scrollController.dispose();
    super.dispose();
  }

  /// Hide a personalized genre row (persisted) and refresh the row list.
  Future<void> _hideGenre(String key) async {
    await getIt<SettingsService>().hideGenre(key);
    ref.invalidate(personalGenreRowsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final continueAsync = ref.watch(continueWatchingProvider);
    final itemsAsync = ref.watch(libraryItemsProvider);
    // Library roots, so the folder fold skips files sitting loose in a root.
    final rootPaths = <String>{
      for (final r in ref.watch(storageRootsProvider).asData?.value ?? const [])
        r.path,
    };
    final trending = ref.watch(trendingTvProvider).asData?.value ?? const [];
    final recommended =
        ref.watch(recommendedProvider).asData?.value ?? const [];
    final popularMovies =
        ref.watch(trendingMoviesProvider).asData?.value ?? const [];
    // Personalized "Because you watch …" genre rows (empty when off / no signal).
    final personalGenres =
        ref.watch(personalGenreRowsProvider).asData?.value ??
            const <GenreScore>[];
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
          // Header sits above the scroll body (not overlaid) so the always-on
          // vertical scrollbar spans only the tiles and stays grabbable top to
          // bottom — it no longer runs up behind the opaque header bar.
          child: Column(
            children: [
              const _Header(),
              Expanded(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
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
                        tiles: recommended,
                      ),
                    ),
                  // Personalized genre rows, inferred from what you watch/save.
                  for (final g in personalGenres)
                    SliverToBoxAdapter(
                      child: _PersonalGenreRail(
                        genre: g,
                        onHide: () => _hideGenre(g.key),
                      ),
                    ),
                  // The user's own library sits above the generic discovery
                  // rails (TV Shows / Movies).
                  ..._librarySlivers(context, itemsAsync,
                      autofocusFirst: resumable.isEmpty,
                      rootPaths: rootPaths),
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
                  if (archivePicks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ArchiveRail(items: archivePicks),
                    ),
                  ],
                ),
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
  Set<String> rootPaths = const {},
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
      // Split the library into its own TV and movie rails (shows/unmatched
      // groups are TV; a loose movie file is a movie).
      final entries = groupLibraryItems(items, rootPaths: rootPaths);
      final tv = [for (final e in entries) if (_isTvEntry(e)) e];
      final movies = [for (final e in entries) if (!_isTvEntry(e)) e];
      return [
        if (tv.isNotEmpty)
          SliverToBoxAdapter(
            child: _LibraryRail(
              label: 'My TV Shows',
              entries: tv,
              autofocusFirst: autofocusFirst,
            ),
          ),
        if (movies.isNotEmpty)
          SliverToBoxAdapter(
            child: _LibraryRail(
              label: 'My Movies',
              entries: movies,
              autofocusFirst: autofocusFirst && tv.isEmpty,
            ),
          ),
      ];
    },
  );
}

bool _isTvEntry(LibraryEntry e) => switch (e) {
      ShowEntry() => true,
      UnmatchedShowEntry() => true,
      ItemEntry(:final item) => item.mediaType == 'tv',
    };

/// One library tile for a grouped [entry].
Widget _libraryTile(BuildContext context, LibraryEntry entry,
    {bool autofocus = false}) {
  return switch (entry) {
    ItemEntry(:final item) => LibraryTile(
        item: item,
        autofocus: autofocus,
        onPressed: () => context.push(Routes.libraryDetail, extra: item),
      ),
    ShowEntry(:final tmdbId, :final name) => ShowLibraryTile(
        name: name,
        posterPath: entry.posterPath,
        episodeCount: entry.episodeCount,
        autofocus: autofocus,
        onPressed: () => openShowDetail(context, tmdbId: tmdbId, name: name),
      ),
    UnmatchedShowEntry(:final name, :final items) => ShowLibraryTile(
        name: name,
        posterPath: null,
        episodeCount: items.length,
        autofocus: autofocus,
        onPressed: () => showUnmatchedShowSheet(context, name, items),
      ),
  };
}

/// A horizontal rail of library tiles (TV or movies), matching the discovery
/// rails' dimensions so the landing page reads as one consistent set of rows.
class _LibraryRail extends StatelessWidget {
  const _LibraryRail({
    required this.label,
    required this.entries,
    this.autofocusFirst = false,
  });
  final String label;
  final List<LibraryEntry> entries;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
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
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) => SizedBox(
              width: 150,
              child: _libraryTile(context, entries[i],
                  autofocus: autofocusFirst && i == 0),
            ),
          ),
        ),
      ],
    );
  }
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
                      // A manual rescan also drains the Alexa voice queue — an
                      // explicit "refresh everything" gesture, so bypass the
                      // throttle. Independent of the disk scan, so fire it in
                      // parallel rather than awaiting it.
                      unawaited(getIt<AlexaInboxService>()
                          .drain(minGap: Duration.zero));
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

class _DiscoverRail extends ConsumerWidget {
  const _DiscoverRail({
    required this.label,
    required this.tiles,
    this.limit = 10,
    this.onHide,
  });
  final String label;
  final List<DiscoverTile> tiles;

  /// Max tiles to show; null shows all (the user's own lists shouldn't be
  /// truncated the way the algorithmic discovery rails are).
  final int? limit;

  /// When set, a small "hide" button sits by the label (personalized rows).
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Drop "not interested" titles from every discovery rail (one place, so all
    // rails honor it); if that empties the rail, don't render it at all.
    final hidden = ref.watch(notInterestedProvider).asData?.value ?? const {};
    final visible = hidden.isEmpty
        ? tiles
        : [
            for (final t in tiles)
              if (!hidden.contains(notInterestedKey(t.tmdbId, t.mediaType))) t,
          ];
    if (visible.isEmpty) return const SizedBox.shrink();
    final lim = limit;
    final top =
        lim == null ? visible : visible.take(lim).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onHide == null)
          _SectionLabel(label)
        else
          Row(
            children: [
              Expanded(child: _SectionLabel(label)),
              IconButton(
                onPressed: onHide,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textTertiary,
                tooltip: 'Hide this row',
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
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

/// A personalized "Because you watch <genre>" rail. Watches its own genre-tiles
/// provider so each row loads independently; renders nothing until it has tiles.
class _PersonalGenreRail extends ConsumerWidget {
  const _PersonalGenreRail({required this.genre, required this.onHide});
  final GenreScore genre;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref
            .watch(genreTilesProvider(
                (mediaType: genre.mediaType, genreId: genre.genreId)))
            .asData
            ?.value ??
        const <DiscoverTile>[];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return _DiscoverRail(
      label: 'Because you watch ${genre.name}',
      tiles: tiles,
      onHide: onHide,
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
