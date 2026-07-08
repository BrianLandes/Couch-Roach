import 'package:couch_roach/src/features/discover/new_episodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 8);
  DateTime d(String s) => DateTime.parse(s);

  group('hasNewerAiredSeason', () {
    test('true when a later season has already aired', () {
      expect(
        hasNewerAiredSeason(watchedSeason: 1, now: now, seasons: [
          SeasonAir(season: 1, airDate: d('2024-01-01')),
          SeasonAir(season: 2, airDate: d('2026-06-01')),
        ]),
        isTrue,
      );
    });

    test('false when the later season airs in the future', () {
      expect(
        hasNewerAiredSeason(watchedSeason: 1, now: now, seasons: [
          SeasonAir(season: 2, airDate: d('2027-01-01')),
        ]),
        isFalse,
      );
    });

    test('false when the later season has no air date yet', () {
      expect(
        hasNewerAiredSeason(watchedSeason: 1, now: now, seasons: const [
          SeasonAir(season: 2),
        ]),
        isFalse,
      );
    });

    test('ignores the watched season and earlier ones', () {
      expect(
        hasNewerAiredSeason(watchedSeason: 2, now: now, seasons: [
          SeasonAir(season: 1, airDate: d('2020-01-01')),
          SeasonAir(season: 2, airDate: d('2025-01-01')),
        ]),
        isFalse,
      );
    });
  });

  group('hasLaterAiredEpisode', () {
    test('true when a later episode in the season has aired', () {
      expect(
        hasLaterAiredEpisode(watchedEpisode: 3, now: now, episodes: [
          EpisodeAir(episode: 3, airDate: d('2026-01-01')),
          EpisodeAir(episode: 4, airDate: d('2026-06-01')),
        ]),
        isTrue,
      );
    });

    test('false when the next episode is unaired', () {
      expect(
        hasLaterAiredEpisode(watchedEpisode: 3, now: now, episodes: [
          EpisodeAir(episode: 4, airDate: d('2026-12-01')),
        ]),
        isFalse,
      );
    });

    test('false when caught up (no later episode)', () {
      expect(
        hasLaterAiredEpisode(watchedEpisode: 8, now: now, episodes: [
          EpisodeAir(episode: 8, airDate: d('2026-01-01')),
        ]),
        isFalse,
      );
    });

    test('false when the later episode has no air date', () {
      expect(
        hasLaterAiredEpisode(watchedEpisode: 3, now: now, episodes: const [
          EpisodeAir(episode: 4),
        ]),
        isFalse,
      );
    });
  });
}
