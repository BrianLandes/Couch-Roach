import 'package:couch_roach/src/data/tmdb/tv_show_details.dart' show Genre;
import 'package:couch_roach/src/features/discover/taste.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RawSignal sig(TasteSource src,
          {int id = 1,
          String type = 'tv',
          bool completed = false,
          int? ageDays = 0}) =>
      RawSignal(
          tmdbId: id,
          mediaType: type,
          source: src,
          completed: completed,
          ageDays: ageDays);

  group('signalWeight', () {
    test('watch history outweighs favorites outweighs want-to-watch', () {
      final w = signalWeight(sig(TasteSource.watched));
      final f = signalWeight(sig(TasteSource.favorite));
      final want = signalWeight(sig(TasteSource.wantToWatch));
      expect(w, greaterThan(f));
      expect(f, greaterThan(want));
    });

    test('a finished watch counts a little more', () {
      expect(signalWeight(sig(TasteSource.watched, completed: true)),
          greaterThan(signalWeight(sig(TasteSource.watched, completed: false))));
    });

    test('older signals decay', () {
      expect(signalWeight(sig(TasteSource.watched, ageDays: 0)),
          greaterThan(signalWeight(sig(TasteSource.watched, ageDays: 400))));
    });
  });

  test('mergeSignalWeights sums across sources for the same title', () {
    final merged = mergeSignalWeights([
      sig(TasteSource.watched, id: 7),
      sig(TasteSource.favorite, id: 7),
    ]);
    expect(merged.keys, hasLength(1));
    expect(merged[(tmdbId: 7, mediaType: 'tv')],
        signalWeight(sig(TasteSource.watched, id: 7)) +
            signalWeight(sig(TasteSource.favorite, id: 7)));
  });

  group('rankGenres', () {
    Genre g(int id, String name) => Genre(id: id, name: name);

    test('ranks by summed weight, keeps TV and movie genres separate', () {
      final ranked = rankGenres([
        WeightedGenres(
            mediaType: 'tv', genres: [g(10765, 'Sci-Fi & Fantasy')], weight: 3),
        WeightedGenres(mediaType: 'tv', genres: [g(35, 'Comedy')], weight: 1),
        WeightedGenres(mediaType: 'tv', genres: [g(10765, 'Sci-Fi & Fantasy')], weight: 2),
        WeightedGenres(mediaType: 'movie', genres: [g(878, 'Science Fiction')], weight: 4),
      ]);
      // tv:10765 = 5, movie:878 = 4, tv:35 = 1
      expect(ranked.first.key, 'tv:10765');
      expect(ranked.first.score, 5);
      expect(ranked.map((r) => r.key).toList(), ['tv:10765', 'movie:878', 'tv:35']);
    });
  });

  group('pickGenreRows', () {
    GenreScore gs(String key, double score) {
      final parts = key.split(':');
      return GenreScore(
          mediaType: parts[0],
          genreId: int.parse(parts[1]),
          name: key,
          score: score);
    }

    test('takes the top N, skipping hidden genres', () {
      final rows = pickGenreRows(
        [gs('tv:1', 5), gs('tv:2', 4), gs('movie:3', 3), gs('tv:4', 2)],
        hidden: {'tv:2'},
        max: 2,
      );
      expect(rows.map((r) => r.key).toList(), ['tv:1', 'movie:3']);
    });
  });
}
