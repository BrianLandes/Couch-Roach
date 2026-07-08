import 'package:go_router/go_router.dart';

import '../features/dev/style_showcase_page.dart';
import '../features/discover/show_detail_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_results_screen.dart';
import '../features/player/player_screen.dart';
import '../features/settings/storage_settings_screen.dart';

/// Route paths — one constant per screen. Never hardcode a path string at a
/// call site; navigate with `context.go(Routes.x)` / `context.push(...)`.
/// Register a new screen by adding a [GoRoute] here (see CLAUDE.md → Navigation).
abstract class Routes {
  static const home = '/';

  /// Embedded player. Pass a [PlayerArgs] as the route `extra`.
  static const player = '/player';

  /// TMDB show detail. Pass a [ShowDetailArgs] as the route `extra`.
  static const showDetail = '/show';

  /// Manage the library folders content spreads across.
  static const storageSettings = '/settings/storage';

  /// Live activity for the background torrent daemon (progress + ETA).
  static const downloads = '/downloads';

  /// Internet Archive search. Optionally pass a query string as the route
  /// `extra` to pre-fill it; otherwise it opens ready for the user to type.
  static const search = '/search';

  /// Living component gallery for the design system (dev/reference).
  static const styleShowcase = '/style';
}

final appRouter = GoRouter(
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
      path: Routes.storageSettings,
      builder: (context, state) => const StorageSettingsScreen(),
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
