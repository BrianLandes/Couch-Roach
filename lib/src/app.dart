import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/app_scroll_behavior.dart';
import 'core/input/input_mode.dart';
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
      // Flip to pointer mode on a deliberate pointer action — a click or a
      // scroll, never mere movement — so cursor drift while arrow-navigating
      // can't switch modes. Keyboard mode is set by the global key handler
      // (main.dart). This ancestor Listener sees descendant pointer-downs
      // regardless of which gesture wins the arena.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => inputMode.onPointerAction(),
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) inputMode.onPointerAction();
        },
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
