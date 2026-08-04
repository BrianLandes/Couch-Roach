import 'package:couch_roach/src/features/discover/new_episodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 8);
  DateTime d(String s) => DateTime.parse(s);

  group('isAired', () {
    test('true for a past air date', () {
      expect(isAired(d('2026-07-07'), now), isTrue);
    });

    test('false for a future air date', () {
      expect(isAired(d('2026-07-09'), now), isFalse);
    });

    test('true for an air date equal to now (out as of today)', () {
      // now is 2026-07-08 00:00; an air date of the 8th is not *after* now.
      expect(isAired(d('2026-07-08'), now), isTrue);
    });

    test('false when there is no air date', () {
      expect(isAired(null, now), isFalse);
    });
  });

  group('hasNewEpisodeSinceCaughtUp', () {
    final lastWatched = d('2026-06-01'); // now is 2026-07-08

    bool check(List<DateTime?> higher) => hasNewEpisodeSinceCaughtUp(
          higherRankedAirDates: higher,
          lastWatchedAt: lastWatched,
          now: now,
        );

    test('qualifies: caught up when watched, and a new one has aired since', () {
      expect(check([d('2026-06-15')]), isTrue);
    });

    test('no: a higher episode was already out when watched (a backlog)', () {
      // The 05-01 episode predates the last watch → they weren\'t caught up,
      // even though 06-20 is genuinely new.
      expect(check([d('2026-05-01'), d('2026-06-20')]), isFalse);
    });

    test('no: caught up, but nothing new has aired yet (still to come)', () {
      expect(check([d('2027-01-01')]), isFalse);
    });

    test('no: nothing is ranked above the furthest-watched episode', () {
      expect(check(const []), isFalse);
    });

    test('undated higher episodes are ignored (not counted as aired)', () {
      expect(check(const [null, null]), isFalse);
    });

    test('an episode aired exactly at the last watch counts as a backlog', () {
      expect(check([lastWatched]), isFalse);
    });

    test('a later-season air date drives it the same as an episode date', () {
      // (The provider passes season-level dates for later seasons.)
      expect(check([d('2026-06-10')]), isTrue);
    });
  });
}
