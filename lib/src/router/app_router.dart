import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/dev/style_showcase_page.dart';
import '../features/discover/movie_detail_screen.dart';
import '../features/discover/discover_tile.dart';
import '../features/discover/show_detail_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/library/library_detail_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_results_screen.dart';
import '../features/player/player_screen.dart';
import '../features/settings/settings_screen.dart';
import '../data/db/database.dart';
import '../features/archive/archive_detail_screen.dart';
import '../services/acquisition/archive_browse_service.dart';

/// Route paths — one constant per screen. Never hardcode a path string at a
/// call site; navigate with `context.go(Routes.x)` / `context.push(...)`.
/// Register a new screen by adding a [GoRoute] here (see CLAUDE.md → Navigation).
abstract class Routes {
  static const home = '/';

  /// Embedded player. Pass a [PlayerArgs] as the route `extra`.
  static const player = '/player';

  /// TMDB show detail. Pass a [ShowDetailArgs] as the route `extra`.
  static const showDetail = '/show';

  /// TMDB movie detail. Pass a [DiscoverTile] (a movie) as the route `extra`.
  static const movieDetail = '/movie';

  /// Profile page for a local library title. Pass a [LibraryItem] as `extra`.
  static const libraryDetail = '/title';

  /// Profile page for an Internet Archive title. Pass an [ArchiveItem] as `extra`.
  static const archiveDetail = '/archive';

  /// App settings: library folders, feature toggles, cleanup grace period.
  static const settings = '/settings';

  /// Live activity for the background torrent daemon (progress + ETA).
  static const downloads = '/downloads';

  /// Internet Archive search. Optionally pass a query string as the route
  /// `extra` to pre-fill it; otherwise it opens ready for the user to type.
  static const search = '/search';

  /// Living component gallery for the design system (dev/reference).
  static const styleShowcase = '/style';
}

/// Observes route pushes/pops so screens can react to becoming visible again.
/// The landing page subscribes as a [RouteAware] to drain the Alexa inbox when
/// the user navigates back to it (see `LibraryScreen`).
final routeObserver = RouteObserver<PageRoute<dynamic>>();

final appRouter = GoRouter(
  observers: [routeObserver],
  routes: [
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: Routes.player,
      builder: (context, state) {
        final args = state.extra as PlayerArgs;
        return PlayerScreen(
          filePath: args.filePath,
          title: args.title,
          libraryItemId: args.libraryItemId,
          startAt: args.startAt,
        );
      },
    ),
    GoRoute(
      path: Routes.showDetail,
      builder: (context, state) =>
          ShowDetailScreen(args: state.extra as ShowDetailArgs),
    ),
    GoRoute(
      path: Routes.movieDetail,
      builder: (context, state) =>
          MovieDetailScreen(tile: state.extra as DiscoverTile),
    ),
    GoRoute(
      path: Routes.libraryDetail,
      builder: (context, state) =>
          LibraryDetailScreen(item: state.extra as LibraryItem),
    ),
    GoRoute(
      path: Routes.archiveDetail,
      builder: (context, state) =>
          ArchiveDetailScreen(item: state.extra as ArchiveItem),
    ),
    GoRoute(
      path: Routes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: Routes.downloads,
      builder: (context, state) => const DownloadsScreen(),
    ),
    GoRoute(
      path: Routes.search,
      builder: (context, state) =>
          SearchResultsScreen(query: state.extra as String? ?? ''),
    ),
    GoRoute(
      path: Routes.styleShowcase,
      builder: (context, state) => const StyleShowcasePage(),
    ),
  ],
);
