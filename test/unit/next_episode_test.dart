import 'package:couch_roach/src/features/player/next_episode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextEpisodeNumber', () {
    // Season 1 has 8 episodes, season 2 has 10.
    const counts = {1: 8, 2: 10};

    test('mid-season → next episode in the same season', () {
      expect(nextEpisodeNumber(1, 3, episodeCounts: counts), (1, 4));
    });

    test('last episode of a season → first of the next season', () {
      expect(nextEpisodeNumber(1, 8, episodeCounts: counts), (2, 1));
    });

    test('last episode of the last known season → null', () {
      expect(nextEpisodeNumber(2, 10, episodeCounts: counts), isNull);
    });

    test('unknown season count → falls back to same-season next', () {
      expect(nextEpisodeNumber(5, 2, episodeCounts: counts), (5, 3));
    });

    test('past the season count still rolls into the next season', () {
      expect(nextEpisodeNumber(1, 9, episodeCounts: counts), (2, 1));
    });
  });
}
