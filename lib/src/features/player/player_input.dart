import 'package:flutter/services.dart';

/// Whether [key] is one of the OS media play/pause keys.
///
/// Keyboards and remotes disagree about which of the three they emit, so all
/// are treated the same.
bool isMediaPlayPauseKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.mediaPlayPause ||
    key == LogicalKeyboardKey.mediaPlay ||
    key == LogicalKeyboardKey.mediaPause;

/// The volume (0–100) after one mouse-wheel notch over the video: 5 per notch,
/// wheel up (negative [scrollDy]) louder, down quieter, clamped. Pure.
double volumeAfterScroll(double volume, double scrollDy) {
  if (scrollDy == 0) return volume;
  return (volume + (scrollDy < 0 ? 5.0 : -5.0)).clamp(0.0, 100.0);
}

/// A play/pause request from any media-key route.
enum MediaCommand { toggle, play, pause }

/// The command a raw media key asks for, or null for any other key.
MediaCommand? mediaCommandForKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.mediaPlayPause) return MediaCommand.toggle;
  if (key == LogicalKeyboardKey.mediaPlay) return MediaCommand.play;
  if (key == LogicalKeyboardKey.mediaPause) return MediaCommand.pause;
  return null;
}

/// The command an OS media-session button name ('play' / 'pause' / 'toggle')
/// asks for, or null for one we don't handle.
MediaCommand? mediaCommandForButton(String button) => switch (button) {
      'play' => MediaCommand.play,
      'pause' => MediaCommand.pause,
      'toggle' => MediaCommand.toggle,
      _ => null,
    };

/// Whether the player should be playing after [command], given it currently
/// [playing]. Explicit play/pause are idempotent; only toggle flips.
bool playingAfter(MediaCommand command, {required bool playing}) =>
    switch (command) {
      MediaCommand.play => true,
      MediaCommand.pause => false,
      MediaCommand.toggle => !playing,
    };

/// Collapses one physical Play/Pause press into one action.
///
/// On Windows a single press can reach the player by up to three routes: the
/// raw key event (when the Flutter view has keyboard focus), a `WM_APPCOMMAND`
/// (when focus is on the top-level window instead — common right after a
/// fullscreen switch), and the SMTC media-session button (when the OS picks
/// Couch Roach as the current media session). Which of them fire varies with
/// focus and with what else is playing, so the player listens to all three and
/// acts on whichever arrives **first**; the echoes inside [window] are dropped.
/// Acting on every route toggled twice (no visible effect), and acting on only
/// one route missed presses whenever that route didn't fire.
class MediaKeyDebouncer {
  MediaKeyDebouncer({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Echoes of one press land within a few tens of ms; a deliberate second
  /// press is well over this.
  static const window = Duration(milliseconds: 400);

  final DateTime Function() _clock;
  DateTime? _last;

  /// Whether this press should act (true) or is an echo of one just handled.
  bool accept() {
    final now = _clock();
    final last = _last;
    if (last != null && now.difference(last) < window) return false;
    _last = now;
    return true;
  }
}
