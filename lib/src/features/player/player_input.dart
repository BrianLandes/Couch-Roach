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
/// acts on whichever arrives **first**; the echoes are dropped.
/// Acting on every route toggled twice (no visible effect), and acting on only
/// one route missed presses whenever that route didn't fire.
///
/// The OS routes get a **longer** echo window after a raw key: SMTC can be slow
/// to deliver, and it picks Play-or-Pause from the session status *when it
/// delivers* — by which point the raw key has already flipped that status, so
/// a late echo arrives as the *opposite* command and undoes the press.
class MediaKeyDebouncer {
  MediaKeyDebouncer({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Echoes of one press land within a few tens of ms; a deliberate second
  /// press is well over this.
  static const window = Duration(milliseconds: 400);

  /// How long after a raw-key action an OS button is still taken as its echo.
  /// The raw key only fires when the window is focused, which is exactly when
  /// the OS routes duplicate it — so a press seen raw is never *also* a fresh
  /// OS press this soon after.
  static const osEchoWindow = Duration(milliseconds: 1500);

  final DateTime Function() _clock;
  DateTime? _last;
  DateTime? _lastKey;

  /// Whether this press should act (true) or is an echo of one just handled.
  /// [fromKey]: it came as a raw key event (vs an OS media-session route).
  bool accept({required bool fromKey}) {
    final now = _clock();
    final last = _last, lastKey = _lastKey;
    if (last != null && now.difference(last) < window) return false;
    if (!fromKey && lastKey != null && now.difference(lastKey) < osEchoWindow) {
      return false;
    }
    _last = now;
    if (fromKey) _lastKey = now;
    return true;
  }
}
