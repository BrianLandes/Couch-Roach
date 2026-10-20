import '../discover/discover_tile.dart';

/// Lane ids for per-lane dismissals ([RailDismissals]). Stable strings — they
/// are persisted, so never rename one.
abstract final class LaneIds {
  static const newEpisodes = 'newEpisodes';
  static const recent = 'recent';
}

/// Whether a lane dismissal still hides a tile.
///
/// A dismissal holds only while the tile's latest activity predates it: a show
/// removed from "New Episodes" comes back when its *next* episode airs, and a
/// title removed from "Recent" comes back when it's downloaded or watched
/// again. A tile that carries no activity time stays hidden — there's nothing
/// to say it changed. Pure + tested.
bool isDismissed({DateTime? dismissedAt, DateTime? activityAt}) {
  if (dismissedAt == null) return false;
  if (activityAt == null) return true;
  return !activityAt.isAfter(dismissedAt);
}

/// One candidate for the Recent lane and when it happened.
typedef RecentCandidate = ({DiscoverTile tile, DateTime at});

/// Merge recent downloads and recent watches into the single "Recent" lane.
///
/// One tile per title, stamped with its *latest* activity of either kind and
/// ordered newest first. [exclude] drops titles already in Continue Watching —
/// this lane exists for the ones that fell *out* of it (a finished episode, a
/// reaped file, a dismissal), so repeating the ones still in it would just
/// duplicate the row above. Pure + tested.
List<DiscoverTile> mergeRecentActivity({
  required List<RecentCandidate> downloads,
  required List<RecentCandidate> watched,
  Set<String> exclude = const {},
  int limit = 20,
}) {
  final latest = <String, RecentCandidate>{};
  for (final c in [...downloads, ...watched]) {
    final key = c.tile.key;
    if (exclude.contains(key)) continue;
    final prev = latest[key];
    if (prev == null || c.at.isAfter(prev.at)) latest[key] = c;
  }
  final ordered = latest.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  return [
    for (final c in ordered.take(limit)) c.tile.withActivity(c.at),
  ];
}
