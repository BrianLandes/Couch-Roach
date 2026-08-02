import 'dart:io';

import 'package:flutter/services.dart';

import '../logging/error_log_service.dart';
import '../../injection.dart';

/// Dart side of the Windows System Media Transport Controls (SMTC) integration
/// (native half in `windows/runner/media_session.*`). While a video plays, the
/// player [enable]s the session and keeps [setPlaying] in sync; owning the OS
/// media session makes the hardware Play/Pause key control Couch Roach instead of
/// leaking to background media apps (Spotify/YouTube). The OS routes button
/// presses back through [onButton] ('play' / 'pause').
///
/// Windows-only: on other platforms the method channel has no handler, so every
/// call is a silently-swallowed no-op.
class MediaSessionController {
  MediaSessionController() {
    if (_supported) {
      _channel.setMethodCallHandler(_handle);
    }
  }

  static const _channel = MethodChannel('couch_roach/media_session');

  bool get _supported => Platform.isWindows;

  /// Called with the OS button name ('play' / 'pause') when the user presses the
  /// media key (or the on-screen OS media control). Set by the player.
  void Function(String button)? onButton;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'onButton') {
      final button = call.arguments as String?;
      if (button != null) onButton?.call(button);
    }
    return null;
  }

  /// Claim the OS media session for a now-playing video (optionally titled).
  Future<void> enable({String? title}) =>
      _invoke('enable', {if (title != null) 'title': title});

  /// Keep the OS session's status in step with the player.
  Future<void> setPlaying(bool playing) =>
      _invoke('setPlaybackStatus', {'playing': playing});

  /// Release the OS media session (playback ended / left the player).
  Future<void> disable() => _invoke('disable');

  /// Stop receiving button callbacks (call from the owner's dispose).
  void dispose() {
    onButton = null;
    if (_supported) _channel.setMethodCallHandler(null);
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'MediaSession.$method');
    }
  }
}
