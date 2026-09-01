// Playback-position policy — where to start, when to persist, when a title
// counts as watched, and when to prefetch the next episode. Split out of the
// widget so the thresholds are pinned by tests rather than living as bare
// numbers inside stream callbacks. Pure.

/// Fraction of the runtime past which a title counts as watched. Backing out
/// during the credits should still mark it complete, so this is deliberately
/// short of the very end.
const double kWatchedFraction = 0.95;

/// Fraction of the runtime past which the next episode starts downloading in
/// the background, so it's ready by the time this one ends.
const double kPrefetchFraction = 0.5;

/// How much playback must advance before another watch-history write. Position
/// ticks arrive many times a second; without this the DB would be hammered.
const int kSaveThresholdSec = 5;

/// Where playback should begin.
///
/// An explicit [requested] start (the caller already knows the position — an
/// auto-advance into the next episode, say) always wins. Otherwise a saved
/// resume position is used. A saved position of zero is "never watched", not
/// "resume at the start", so it falls through to the beginning either way.
Duration resolveStartPosition({
  required Duration requested,
  int? savedResumeSec,
}) {
  if (requested > Duration.zero) return requested;
  if (savedResumeSec != null && savedResumeSec > 0) {
    return Duration(seconds: savedResumeSec);
  }
  return Duration.zero;
}

/// Whether a position tick should be written to watch history.
///
/// Throttled to [kSaveThresholdSec] of movement in **either** direction, so a
/// seek backwards persists as promptly as normal playback does.
bool shouldSaveProgress({
  required int positionSec,
  required int lastSavedSec,
}) =>
    (positionSec - lastSavedSec).abs() >= kSaveThresholdSec;

/// Whether the title has been watched far enough to count as completed.
///
/// False when [duration] is unknown (zero) — an unmeasured file must never be
/// marked watched, or the reaper could delete something nobody finished.
bool isWatched({required Duration position, required Duration duration}) =>
    duration.inSeconds > 0 &&
    position.inSeconds >= duration.inSeconds * kWatchedFraction;

/// Whether playback has passed the point where the next episode should start
/// downloading. False on an unknown duration, for the same reason as above.
bool shouldPrefetchNext({
  required Duration position,
  required Duration duration,
}) =>
    duration.inSeconds > 0 &&
    position.inSeconds >= duration.inSeconds * kPrefetchFraction;
