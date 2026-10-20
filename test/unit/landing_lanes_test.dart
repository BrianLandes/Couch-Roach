import 'package:couch_roach/src/features/discover/discover_tile.dart';
import 'package:couch_roach/src/features/library/landing_lanes.dart';
import 'package:flutter_test/flutter_test.dart';

DiscoverTile tile(int id, {String type = 'tv'}) =>
    DiscoverTile(tmdbId: id, title: 'T$id', mediaType: type);

void main() {
  final t0 = DateTime(2026, 10, 1);
  DateTime at(int hours) => t0.add(Duration(hours: hours));

  group('isDismissed', () {
    test('nothing dismissed → shown', () {
      expect(isDismissed(dismissedAt: null, activityAt: at(5)), isFalse);
    });

    test('hidden while the latest activity predates the dismissal', () {
      expect(isDismissed(dismissedAt: at(10), activityAt: at(5)), isTrue);
    });

    test('returns once something new happens after the dismissal', () {
      // The point of the design: removing a show from "New Episodes" doesn't
      // lose it for good — the next episode airing brings it back.
      expect(isDismissed(dismissedAt: at(10), activityAt: at(11)), isFalse);
    });

    test('activity at exactly the dismissal instant stays hidden', () {
      expect(isDismissed(dismissedAt: at(10), activityAt: at(10)), isTrue);
    });

    test('a tile with no activity time stays hidden once dismissed', () {
      expect(isDismissed(dismissedAt: at(10), activityAt: null), isTrue);
    });
  });

  group('mergeRecentActivity', () {
    test('merges downloads and watches newest-first', () {
      final out = mergeRecentActivity(
        downloads: [(tile: tile(1), at: at(1)), (tile: tile(2), at: at(5))],
        watched: [(tile: tile(3), at: at(3))],
      );
      expect(out.map((t) => t.tmdbId), [2, 3, 1]);
    });

    test('one tile per title, keeping its latest activity of either kind', () {
      final out = mergeRecentActivity(
        downloads: [(tile: tile(1), at: at(1))],
        watched: [(tile: tile(1), at: at(9))],
      );
      expect(out, hasLength(1));
      expect(out.single.activityAt, at(9));
    });

    test('stamps each tile with its activity time (dismissals compare on it)',
        () {
      final out =
          mergeRecentActivity(downloads: [(tile: tile(1), at: at(4))], watched: const []);
      expect(out.single.activityAt, at(4));
    });

    test('drops titles already in Continue Watching', () {
      final out = mergeRecentActivity(
        downloads: [(tile: tile(1), at: at(1))],
        watched: [(tile: tile(2), at: at(2))],
        exclude: {'tv:2'},
      );
      expect(out.map((t) => t.tmdbId), [1]);
    });

    test('a movie and a show sharing an id are different titles', () {
      final out = mergeRecentActivity(
        downloads: [(tile: tile(5, type: 'movie'), at: at(1))],
        watched: [(tile: tile(5), at: at(2))],
      );
      expect(out, hasLength(2));
    });

    test('honours the limit, keeping the newest', () {
      final out = mergeRecentActivity(
        downloads: [for (var i = 0; i < 30; i++) (tile: tile(i), at: at(i))],
        watched: const [],
        limit: 3,
      );
      expect(out.map((t) => t.tmdbId), [29, 28, 27]);
    });
  });
}
