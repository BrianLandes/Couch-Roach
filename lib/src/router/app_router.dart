import 'package:go_router/go_router.dart';

import '../features/dev/style_showcase_page.dart';
import '../features/library/library_screen.dart';

/// Route paths — one constant per screen. Never hardcode a path string at a
/// call site; navigate with `context.go(Routes.x)` / `context.push(...)`.
/// Register a new screen by adding a [GoRoute] here (see CLAUDE.md → Navigation).
abstract class Routes {
  static const home = '/';

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
      path: Routes.styleShowcase,
      builder: (context, state) => const StyleShowcasePage(),
    ),
  ],
);
