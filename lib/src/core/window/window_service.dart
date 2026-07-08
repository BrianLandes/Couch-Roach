import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window setup for the TV: launch windowed, with F11 (or the in-app
/// button) to toggle fullscreen and [minimizeWindow] for a remote-friendly
/// "drop to desktop". No-ops off desktop so tests and other platforms are
/// unaffected.
bool get _isDesktop => Platform.isWindows || Platform.isLinux;

/// Registered by [initFullscreenWindow] and invoked when the window is closing,
/// so the caller can shut down child processes (the qBittorrent-nox daemon)
/// before the app exits. No-op if unset.
Future<void> Function()? _onCloseHook;

Future<void> initFullscreenWindow({Future<void> Function()? onClose}) async {
  if (!_isDesktop) return;
  _onCloseHook = onClose;

  await windowManager.ensureInitialized();
  if (onClose != null) {
    windowManager.addListener(_CouchRoachWindowListener());
    await windowManager.setPreventClose(true);
  }
  const options = WindowOptions(
    title: 'Couch Roach',
    // Normal title bar so windowed mode has OS controls; fullscreen (F11 or the
    // in-app button) hides it anyway.
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

/// Runs the close hook (sidecar shutdown) then hard-exits the process. We set
/// `preventClose` so the children are killed before the app dies, then call
/// `exit(0)` instead of `windowManager.destroy()`.
///
/// Why `exit()` and not `destroy()`: on Linux `destroy()` tears down the Flutter
/// view and its GL context (`FlutterEngineRemoveView`), and media_kit/libmpv's
/// compositor cleanup then runs with no current GL context and aborts the whole
/// process (epoxy "Couldn't find current GLX or EGL context"). We're quitting
/// anyway and the sidecars are already stopped, so exiting the process directly
/// lets the OS reclaim the window/GL/native state — no fragile teardown, no
/// crash, and the sidecar children are guaranteed dead rather than orphaned.
class _CouchRoachWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    final hook = _onCloseHook;
    // Always exit, even if the shutdown hook throws — otherwise preventClose
    // stays on and the window can't be closed.
    try {
      if (hook != null) await hook();
    } finally {
      exit(0);
    }
  }
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
