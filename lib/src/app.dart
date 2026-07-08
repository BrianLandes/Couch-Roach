import 'package:flutter/material.dart';

import 'core/app_scroll_behavior.dart';
import 'router/app_router.dart';
import 'theme/theme.dart';

/// Root of the app. Dark "liquid glass" theme (see docs/STYLE.md), meant to run
/// fullscreen on a TV and be driven by an arrow-key remote — focus traversal and
/// large targets are first-class.
class CouchRoachApp extends StatelessWidget {
  const CouchRoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Couch Roach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      scrollBehavior: const AppScrollBehavior(),
      routerConfig: appRouter,
    );
  }
}
