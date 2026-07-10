import 'package:couch_roach/src/data/tmdb/season.dart';
import 'package:couch_roach/src/features/acquire/acquire_play.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Local midnight, matching how TMDB date strings parse — keeps the aired
  // comparison off any timezone edge.
  final now = DateTime(2026, 7, 10);

  EpisodeSummary ep(int n, {String? airDate}) =>
      EpisodeSummary(episodeNumber: n, name: 'E$n', airDate: airDate);

  group('airedEpisodeNumbers', () {
    test('keeps only aired episodes, in order', () {
      final eps = [
        ep(1, airDate: '2026-01-01'), // aired
        ep(2, airDate: '2026-07-09'), // aired (yesterday)
        ep(3, airDate: '2026-12-25'), // future
        ep(4), // no date → treated as not aired
      ];
      expect(airedEpisodeNumbers(eps, now), [1, 2]);
    });

    test('empty in, empty out', () {
      expect(airedEpisodeNumbers(const [], now), isEmpty);
    });
  });
}
