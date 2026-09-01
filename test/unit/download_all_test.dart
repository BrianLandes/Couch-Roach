import 'package:couch_roach/src/data/tmdb/season.dart';
import 'package:couch_roach/src/features/acquire/acquire_play.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers one season's episode list; everything else is unused here.
class _FakeDiscovery implements DiscoveryClient {
  _FakeDiscovery({this.season, this.throws = false});
  final SeasonDetails? season;
  final bool throws;

  @override
  Future<SeasonDetails?> seasonDetails(int tmdbId, int seasonNumber) async {
    if (throws) throw Exception('TMDB unreachable');
    return season;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

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

  group('seasonPackWorthTrying', () {
    test('true when every episode has aired (a complete season)', () {
      final eps = [
        ep(1, airDate: '2026-01-01'),
        ep(2, airDate: '2026-07-09'),
      ];
      expect(seasonPackWorthTrying(eps, now), isTrue);
    });

    test('false when any episode is still to air', () {
      final eps = [
        ep(1, airDate: '2026-01-01'),
        ep(2, airDate: '2026-12-25'), // future → season still airing
      ];
      expect(seasonPackWorthTrying(eps, now), isFalse);
    });

    test('false when an episode has no air date (treated as not aired)', () {
      final eps = [ep(1, airDate: '2026-01-01'), ep(2)];
      expect(seasonPackWorthTrying(eps, now), isFalse);
    });

    test('true for an empty list (unknown → keep normal pack-first behavior)',
        () {
      expect(seasonPackWorthTrying(const [], now), isTrue);
    });
  });

  group('episodeHasAired', () {
    Future<void> withDiscovery(_FakeDiscovery d, Future<void> Function() body) async {
      await getIt.reset();
      getIt.registerLazySingleton<DiscoveryClient>(() => d);
      try {
        await body();
      } finally {
        await getIt.reset();
      }
    }

    SeasonDetails season(List<EpisodeSummary> eps) =>
        SeasonDetails(seasonNumber: 1, name: 'Season 1', episodes: eps);

    test('a past air date has aired', () async {
      await withDiscovery(
        _FakeDiscovery(season: season([ep(1, airDate: '2020-01-01')])),
        () async => expect(await episodeHasAired(1, 1, 1), isTrue),
      );
    });

    test('a future air date has not', () async {
      await withDiscovery(
        _FakeDiscovery(season: season([ep(1, airDate: '2099-01-01')])),
        () async => expect(await episodeHasAired(1, 1, 1), isFalse),
      );
    });

    test('listed but undated is not out yet', () async {
      await withDiscovery(
        _FakeDiscovery(season: season([ep(1)])),
        () async => expect(await episodeHasAired(1, 1, 1), isFalse),
      );
    });

    // The guard exists to avoid pointless fetches, not to become a new way for
    // downloads to fail. Anything it can't answer must fail open.
    group('fails open rather than blocking the user', () {
      test('an episode TMDB does not list at all', () async {
        await withDiscovery(
          _FakeDiscovery(season: season([ep(1, airDate: '2020-01-01')])),
          () async => expect(await episodeHasAired(1, 1, 99), isTrue),
        );
      });

      test('a season TMDB has no details for', () async {
        await withDiscovery(
          _FakeDiscovery(season: null),
          () async => expect(await episodeHasAired(1, 1, 1), isTrue),
        );
      });

      test('a TMDB lookup that throws', () async {
        await withDiscovery(
          _FakeDiscovery(throws: true),
          () async => expect(await episodeHasAired(1, 1, 1), isTrue),
        );
      });

      test('an unparseable air date', () async {
        await withDiscovery(
          _FakeDiscovery(season: season([ep(1, airDate: 'not-a-date')])),
          () async => expect(await episodeHasAired(1, 1, 1), isTrue),
        );
      });
    });
  });

  group('episodeAirDate', () {
    test('returns the parsed date for a listed episode', () async {
      await getIt.reset();
      getIt.registerLazySingleton<DiscoveryClient>(() => _FakeDiscovery(
          season: SeasonDetails(
              seasonNumber: 1,
              name: 'S1',
              episodes: [ep(2, airDate: '2026-03-04')])));
      addTearDown(getIt.reset);

      expect(await episodeAirDate(1, 1, 2), DateTime(2026, 3, 4));
      expect(await episodeAirDate(1, 1, 9), isNull); // not listed
    });
  });
}
