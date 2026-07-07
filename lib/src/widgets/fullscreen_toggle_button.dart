import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/window/window_service.dart';

/// Toggles the OS window between fullscreen and windowed, reflecting the real
/// window state (so it stays correct whether the window came up fullscreen, was
/// toggled with F11, or from another button). `window_manager` is the single
/// source of truth for fullscreen — we don't use media_kit's separate flag.
class FullscreenToggleButton extends StatefulWidget {
  const FullscreenToggleButton({super.key, this.color, this.iconSize});

  final Color? color;
  final double? iconSize;

  @override
  State<FullscreenToggleButton> createState() => _FullscreenToggleButtonState();
}

class _FullscreenToggleButtonState extends State<FullscreenToggleButton>
    with WindowListener {
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _sync();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final full = await windowManager.isFullScreen();
      if (mounted) setState(() => _fullscreen = full);
    } catch (_) {
      // Plugin unavailable (tests / non-desktop) — leave the default.
    }
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullscreen = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        await toggleFullscreen();
        await _sync();
      },
      icon: Icon(
        _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      ),
      color: widget.color,
      iconSize: widget.iconSize,
      tooltip: _fullscreen ? 'Windowed (F11)' : 'Fullscreen (F11)',
    );
  }
}
