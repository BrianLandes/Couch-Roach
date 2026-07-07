import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window setup for the TV: launch fullscreen, with F11 to toggle
/// (dev/exit affordance) and [minimizeWindow] for a remote-friendly "drop to
/// desktop". No-ops off desktop so tests and other platforms are unaffected.
bool get _isDesktop => Platform.isWindows || Platform.isLinux;

Future<void> initFullscreenWindow() async {
  if (!_isDesktop) return;

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    title: 'Couch Roach',
    fullScreen: true,
    // Normal title bar so windowed mode (F11) still has OS controls; fullscreen
    // hides it anyway.
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  HardwareKeyboard.instance.addHandler(_onKey);
}

bool _onKey(KeyEvent event) {
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
    toggleFullscreen();
    return true;
  }
  return false;
}

Future<void> toggleFullscreen() async {
  if (!_isDesktop) return;
  final full = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!full);
}

Future<void> minimizeWindow() async {
  if (!_isDesktop) return;
  await windowManager.minimize();
}
