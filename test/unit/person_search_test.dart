import 'package:couch_roach/src/data/tmdb/credits.dart';
import 'package:couch_roach/src/data/tmdb/person_summary.dart';
import 'package:couch_roach/src/features/discover/person_search.dart';
import 'package:flutter_test/flutter_test.dart';

PersonSummary person(String name, {double popularity = 1, int id = 1}) =>
    PersonSummary(personId: id, name: name, popularity: popularity);

PersonCredit credit({
  required int id,
  required String title,
  String mediaType = 'movie',
  double popularity = 1,
  String? releaseDate,
}) =>
    PersonCredit(
      tmdbId: id,
      mediaType: mediaType,
      title: title,
      popularity: popularity,
      releaseDate: releaseDate,
    );

void main() {
  group('bestPersonMatch', () {
    test('matches a full name, case- and punctuation-insensitively', () {
      final p = [person('Quentin Tarantino')];
      expect(bestPersonMatch(p, 'Quentin Tarantino')?.name, 'Quentin Tarantino');
      expect(bestPersonMatch(p, 'quentin tarantino')?.name, 'Quentin Tarantino');
    });

    test('matches a surname or forename alone', () {
      final p = [person('Quentin Tarantino')];
      expect(bestPersonMatch(p, 'Tarantino'), isNotNull);
      expect(bestPersonMatch(p, 'quentin'), isNotNull);
    });

    test('the most popular qualifying person wins a shared surname', () {
      // What makes a bare surname resolve to who you actually meant.
      final result = bestPersonMatch([
        person('Paul Anderson', popularity: 4, id: 1),
        person('Paul Thomas Anderson', popularity: 40, id: 2),
      ], 'Anderson');
      expect(result?.personId, 2);
    });

    test('a title query does not become a person match', () {
      // TMDB's person search is fuzzy and always returns something; attaching a
      // filmography to "batman" would be worse than showing nothing.
      expect(bestPersonMatch([person('Adam West')], 'batman'), isNull);
      expect(bestPersonMatch([person('Christopher Nolan')], 'inception'),
          isNull);
    });

    test('empty query and empty results yield null', () {
      expect(bestPersonMatch([person('Someone')], ''), isNull);
      expect(bestPersonMatch([person('Someone')], '   '), isNull);
      expect(bestPersonMatch(const [], 'Tarantino'), isNull);
    });

    test('a nameless result is skipped rather than matched', () {
      expect(bestPersonMatch([person('')], 'anything'), isNull);
    });
  });

  group('tilesFromCredits', () {
    test('orders by popularity, most popular first', () {
      final tiles = tilesFromCredits([
        credit(id: 1, title: 'Minor', popularity: 1),
        credit(id: 2, title: 'Famous', popularity: 90),
      ]);
      expect(tiles.map((t) => t.title), ['Famous', 'Minor']);
    });

    test('keeps one tile per title', () {
      // Combined credits list a title once per role held on it.
      final tiles = tilesFromCredits([
        credit(id: 7, title: 'Dual Role', popularity: 5),
        credit(id: 7, title: 'Dual Role', popularity: 5),
      ]);
      expect(tiles, hasLength(1));
    });

    test('drops ids the caller already showed', () {
      final tiles = tilesFromCredits(
        [credit(id: 1, title: 'Shown'), credit(id: 2, title: 'New')],
        exclude: {1},
      );
      expect(tiles.map((t) => t.title), ['New']);
    });

    test('skips media types with no detail page, and untitled credits', () {
      final tiles = tilesFromCredits([
        credit(id: 1, title: 'Fine'),
        credit(id: 2, title: 'Nope', mediaType: 'person'),
        credit(id: 3, title: ''),
      ]);
      expect(tiles.map((t) => t.tmdbId), [1]);
    });

    test('carries the year through when TMDB has a date', () {
      final tiles =
          tilesFromCredits([credit(id: 1, title: 'X', releaseDate: '1994-10-14')]);
      expect(tiles.single.year, 1994);
      // A credit with no date is still shown, just undated.
      expect(tilesFromCredits([credit(id: 2, title: 'Y')]).single.year, isNull);
    });

    test('honours the limit', () {
      final many = [
        for (var i = 0; i < 60; i++)
          credit(id: i, title: 'T$i', popularity: i.toDouble())
      ];
      expect(tilesFromCredits(many, limit: 5), hasLength(5));
      expect(tilesFromCredits(many), hasLength(40)); // default cap
    });

    test('an empty credit list yields no tiles', () {
      expect(tilesFromCredits(const []), isEmpty);
    });
  });
}
