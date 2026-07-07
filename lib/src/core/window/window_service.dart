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
    // NB: do NOT set `fullScreen: true` here. Launching fullscreen leaves
    // window_manager's internal state out of sync with the Win32 window style
    // on Windows, so the first *exit* from fullscreen produces a broken frame
    // (window visible but click-through / unfocusable). Instead we come up
    // windowed and toggle fullscreen on explicitly below, which keeps the
    // enter/exit bookkeeping consistent.
    //
    // Normal title bar so windowed mode (F11) still has OS controls; fullscreen
    // hides it anyway.
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setFullScreen(true);
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
  final wasFull = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!wasFull);
  if (wasFull) {
    // We just LEFT fullscreen. On Windows, setFullScreen(false) leaves the
    // window unable to receive input (clicks pass through, can't focus) until
    // it's re-activated. A minimize/restore cycle is what actually repairs it —
    // the minimize button already recovers a working window this way — so do the
    // same repair here rather than leaving a dead window on screen.
    await _repairAfterFullscreenExit();
  }
}

/// Force Windows to re-composite and re-activate the window after leaving
/// fullscreen. A brief minimize→restore is the reliable repair (a plain focus()
/// doesn't rebuild the hit-test regions). No-op on other platforms.
Future<void> _repairAfterFullscreenExit() async {
  if (!Platform.isWindows) return;
  await windowManager.minimize();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await windowManager.restore();
  await windowManager.focus();
}

Future<void> minimizeWindow() async {
  if (!_isDesktop) return;
  // Windows won't minimize a window that's still in the fullscreen state, so
  // drop to windowed first — otherwise the button silently does nothing.
  if (await windowManager.isFullScreen()) {
    await windowManager.setFullScreen(false);
  }
  await windowManager.minimize();
}
