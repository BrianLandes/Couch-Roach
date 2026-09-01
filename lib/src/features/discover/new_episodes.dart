// Logic for the "New Episodes For You" rail, decoupled from the TMDB DTOs so
// it's pure + unit-testable.

/// Whether something with [airDate] has been released by [now]. A missing air
/// date counts as *not* released — TMDB hasn't dated it yet (unannounced or
/// still to come). Pure + tested; the single source of truth for "is it out?".
bool isAired(DateTime? airDate, DateTime now) =>
    airDate != null && !airDate.isAfter(now);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The label for something that hasn't aired yet — "Airs Mar 4, 2026", or
/// "Not yet released" when TMDB hasn't dated it. Shared by the show detail
/// page's episode rows and the player's Next Episode button so an unreleased
/// episode reads the same wherever it turns up. Pure + tested.

/// Whether a watched show belongs on the "New Episodes" rail, given the air
/// dates of every episode *ranked above* the user's furthest-finished episode
/// ([higherRankedAirDates] — later episodes of that season plus later seasons),
/// the instant they finished it ([lastWatchedAt]), and [now].
///
/// It qualifies only when BOTH hold (see the rail's spec):
///  1. **They were caught up when they watched** — nothing ranked above had aired
///     by [lastWatchedAt] (a higher episode already out then is a *backlog*, not
///     something new).
///  2. **Something new has aired since** — at least one higher-ranked episode has
///     aired after [lastWatchedAt] and by [now].
///
/// A null air date is treated as not-yet-aired (ignored). An episode dated on or
/// before [lastWatchedAt] breaks condition 1. Pure + tested.
bool hasNewEpisodeSinceCaughtUp({
  required List<DateTime?> higherRankedAirDates,
  required DateTime lastWatchedAt,
  required DateTime now,
}) {
  var caughtUpWhenWatched = true;
  var newSince = false;
  for (final airDate in higherRankedAirDates) {
    if (airDate == null) continue; // undated → not aired
    if (!airDate.isAfter(lastWatchedAt)) {
      // Aired on or before they last watched → they had a backlog, not caught up.
      caughtUpWhenWatched = false;
    } else if (!airDate.isAfter(now)) {
      // Aired after they watched, and by now → genuinely new since.
      newSince = true;
    }
  }
  return caughtUpWhenWatched && newSince;
}

String airDateLabel(DateTime? airDate) {
  final d = airDate;
  if (d == null) return 'Not yet released';
  return 'Airs ${_months[d.month - 1]} ${d.day}, ${d.year}';
}
