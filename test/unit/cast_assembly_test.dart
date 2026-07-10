import 'package:couch_roach/src/data/tmdb/credits.dart';
import 'package:couch_roach/src/features/cast/cast_assembly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CastMember c(int id, {String name = 'n'}) =>
      CastMember(personId: id, name: name, character: 'char$id');

  PersonCredit credit(int id,
          {String title = 'T', String? poster = '/p.jpg', double pop = 1}) =>
      PersonCredit(
        tmdbId: id,
        mediaType: 'movie',
        title: title,
        posterPath: poster,
        popularity: pop,
      );

  group('assembleEpisodeCast', () {
    test('orders guest stars, then episode cast, then main cast', () {
      final out = assembleEpisodeCast(
        guestStars: [c(1)],
        episodeCast: [c(2)],
        mainCast: [c(3)],
      );
      expect(out.map((m) => m.personId), [1, 2, 3]);
    });

    test('dedupes by person, keeping the earliest (most specific) billing', () {
      final out = assembleEpisodeCast(
        guestStars: [c(1)],
        episodeCast: [c(1), c(2)],
        mainCast: [c(2), c(3)],
      );
      expect(out.map((m) => m.personId), [1, 2, 3]);
    });
  });

  group('knownForTitles', () {
    test('drops the current title, posterless entries, and dupes', () {
      final out = knownForTitles(
        [
          credit(1, pop: 5),
          credit(1, pop: 5), // dup id
          credit(2, poster: null), // no poster
          credit(3, pop: 9),
          credit(99), // the title we're watching
        ],
        excludeTmdbId: 99,
      );
      expect(out.map((c) => c.tmdbId), [3, 1]); // sorted by popularity desc
    });

    test('caps at the limit', () {
      final many = [for (var i = 0; i < 30; i++) credit(i, pop: i.toDouble())];
      expect(knownForTitles(many, limit: 5), hasLength(5));
    });
  });
}
