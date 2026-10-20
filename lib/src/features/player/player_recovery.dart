/// What the player should do with an error libmpv just reported.
enum PlaybackFailureAction {
  /// Transparently reopen the file at the last known position (after
  /// [PlaybackRecovery.delayFor]) — the error looks like a lost audio/video
  /// pipeline, not a bad file.
  recover,

  /// A recovery is already under way; this error is fallout from the same
  /// failure. Log it and do nothing else.
  ignore,

  /// Show the "can't be played" error screen.
  showError,
}

/// Tells a **transient** playback failure apart from a **real** one, pulled out
/// of the player widget so it can be tested without libmpv.
///
/// Putting the PC to sleep or unplugging the HDMI cable while a video is paused
/// tears down the audio device / GPU output libmpv was rendering to, and mpv
/// reports an error even though the file itself is fine — reopening it at the
/// same position plays normally. A file that genuinely can't be played (corrupt,
/// unsupported codec, missing) fails *before* it ever plays, or fails again
/// straight after a reopen.
///
/// Rather than pattern-matching mpv's error strings (which vary by platform and
/// output driver), the policy classifies by outcome:
///
/// * An error before playback ever started → [PlaybackFailureAction.showError].
/// * An error on a network stream → `showError` (no local file to reopen).
/// * An error after playback was running → [PlaybackFailureAction.recover], at
///   most [maxAttempts] times within [window], with a growing delay so a display
///   that's still waking up gets a moment to come back.
/// * An error while a reopen is in flight → [PlaybackFailureAction.ignore]; the
///   reopen's own outcome decides. Once a reopen has been issued
///   ([onReopened]), an error before playback confirms again counts as that
///   attempt failing — retried while attempts remain, then `showError`.
class PlaybackRecovery {
  PlaybackRecovery({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Reopens allowed inside [window] before giving up and showing the error.
  static const maxAttempts = 3;

  /// The span [maxAttempts] is counted over — a later, unrelated hiccup (the
  /// next night's sleep) gets a fresh budget.
  static const window = Duration(minutes: 2);

  /// Wait before each successive reopen attempt (0-based).
  static const _delays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];

  final DateTime Function() _clock;
  final List<DateTime> _attempts = [];
  bool _started = false;
  bool _reopening = false;

  /// Whether the file has been confirmed playing (a position tick with a known
  /// duration) since it was opened or last reopened.
  bool get hasStarted => _started;

  /// Whether a reopen is scheduled or in flight.
  bool get isRecovering => _reopening;

  /// Playback is confirmed running — call on a position tick once the duration
  /// is known. Ends any recovery in progress.
  void onPlaybackConfirmed() {
    _started = true;
    _reopening = false;
  }

  /// The reopen command has been issued; from here, an error before
  /// [onPlaybackConfirmed] means the reopen itself failed.
  void onReopened() {
    _reopening = false;
    _started = false;
  }

  /// Classify an error reported by the player.
  PlaybackFailureAction onError({required bool isNetworkSource}) {
    if (_reopening) return PlaybackFailureAction.ignore;
    if (isNetworkSource) return PlaybackFailureAction.showError;
    // Never played and not mid-recovery: the file itself is the problem.
    if (!_started && _attempts.isEmpty) return PlaybackFailureAction.showError;

    final now = _clock();
    _attempts.removeWhere((t) => now.difference(t) > window);
    if (_attempts.length >= maxAttempts) return PlaybackFailureAction.showError;
    _attempts.add(now);
    _reopening = true;
    return PlaybackFailureAction.recover;
  }

  /// How long to wait before the reopen just granted by [onError].
  Duration get delayFor {
    final i = (_attempts.length - 1).clamp(0, _delays.length - 1);
    return _delays[i];
  }
}
