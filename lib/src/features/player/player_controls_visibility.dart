import 'dart:async';

/// What the widget must do to its idle-hide timer after feeding an event to
/// [ControlsVisibility]. The policy has no timer of its own — it only says what
/// the countdown should be doing, and the widget owns the [Timer].
enum IdleHide {
  /// Cancel any pending countdown and start a fresh one.
  restart,

  /// Cancel any pending countdown and don't start another.
  cancel,
}

/// The player's overlay (back button, title, Next Episode) auto-hide policy,
/// pulled out of the widget so it can be tested without a libmpv player.
///
/// The rules, in one place:
///
/// * Any user activity — pointer **or** keyboard/remote — reveals the overlay.
/// * The idle countdown that hides it again only ever arms **while playing**.
///   Paused or ended, the overlay stays up indefinitely: a remote emits key
///   events, not pointer motion, so an overlay hidden at the end of an episode
///   would leave a remote user with no way to get the back button back. This is
///   the "stranded overlay" failure mode, and it's why hiding is gated on
///   [playing] in three separate places rather than one.
/// * Pausing forces the overlay up even if it was hidden at the moment of the
///   pause — otherwise pausing to read something would be the one action that
///   can't summon the controls.
///
/// Mirrors media_kit's own controls timing so ours and theirs move in lockstep.
class ControlsVisibility {
  ControlsVisibility({bool playing = true, bool visible = false})
      : _playing = playing,
        _visible = visible;

  /// How long the overlay stays up after the last activity, matching
  /// media_kit's default `controlsHoverDuration`.
  static const hideDelay = Duration(seconds: 3);

  /// Fade duration, matching media_kit's `controlsTransitionDuration`, so our
  /// overlay and theirs cross-fade together.
  static const fade = Duration(milliseconds: 150);

  bool _playing;
  bool _visible;

  /// Whether the overlay should currently be on screen.
  bool get visible => _visible;

  /// Last known play state, mirrored from mpv.
  bool get playing => _playing;

  /// Pointer motion, a scroll, or any key press. Reveals the overlay and
  /// restarts the countdown — but only arms the countdown while playing.
  IdleHide onActivity() {
    _visible = true;
    return _playing ? IdleHide.restart : IdleHide.cancel;
  }

  /// The idle countdown elapsed. Hides the overlay — but defensively re-checks
  /// [playing] first: a timer armed just before a pause can still fire after
  /// it, and hiding then would strand the overlay on a paused video.
  IdleHide onIdleElapsed() {
    if (!_playing) return IdleHide.cancel;
    _visible = false;
    return IdleHide.cancel;
  }

  /// mpv's play state changed. Pausing or ending pins the overlay up and stops
  /// the countdown; resuming behaves like fresh activity.
  IdleHide onPlayingChanged(bool playing) {
    _playing = playing;
    if (!playing) {
      _visible = true;
      return IdleHide.cancel;
    }
    return onActivity();
  }
}
