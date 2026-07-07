import 'package:flutter/material.dart';

import 'router/app_router.dart';

/// Root of the app. Dark, 10-foot theme suitable for a TV. The whole app is
/// meant to run fullscreen and be driven by an arrow-key remote, so focus
/// traversal and large targets are first-class (see CLAUDE.md → Design system).
class CouchRoachApp extends StatelessWidget {
  const CouchRoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp.router(
      title: 'Couch Roach',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
        // High-contrast focus ring for remote navigation.
        focusColor: const Color(0xFF7C4DFF),
      ),
      routerConfig: appRouter,
    );
  }
}
