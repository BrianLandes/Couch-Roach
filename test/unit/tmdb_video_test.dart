import 'package:couch_roach/src/data/tmdb/tmdb_video.dart';
import 'package:flutter_test/flutter_test.dart';

TmdbVideo v(String type, {String site = 'YouTube', bool official = false, String key = 'k'}) =>
    TmdbVideo(key: key, site: site, type: type, official: official);

void main() {
  group('pickTrailer', () {
    test('prefers an official YouTube trailer', () {
      final best = pickTrailer([
        v('Teaser', official: true),
        v('Trailer', official: false, key: 'unofficial'),
        v('Trailer', official: true, key: 'official'),
      ]);
      expect(best!.key, 'official');
    });

    test('falls back to any trailer, then a teaser', () {
      expect(pickTrailer([v('Trailer', key: 't'), v('Teaser', key: 'z')])!.key, 't');
      expect(pickTrailer([v('Teaser', key: 'z'), v('Clip', key: 'c')])!.key, 'z');
    });

    test('ignores non-YouTube videos', () {
      expect(pickTrailer([v('Trailer', site: 'Vimeo')]), isNull);
    });

    test('ignores entries with an empty key', () {
      expect(pickTrailer([v('Trailer', key: '')]), isNull);
    });

    test('null when there are no videos', () {
      expect(pickTrailer(const []), isNull);
    });

    test('last resort is any YouTube video', () {
      expect(pickTrailer([v('Featurette', key: 'f')])!.key, 'f');
    });
  });

  test('youtubeWatchUrl builds the watch URL', () {
    expect(youtubeWatchUrl('abc123'),
        'https://www.youtube.com/watch?v=abc123');
  });

  test('TmdbVideo.fromJson tolerates missing fields', () {
    final video = TmdbVideo.fromJson({'key': 'x'});
    expect(video.key, 'x');
    expect(video.site, '');
    expect(video.official, isFalse);
  });

  group('groupTrailerOptions', () {
    TrailerOption opt(
      String type, {
      required String key,
      bool official = false,
      String name = '',
      int? season,
      String site = 'YouTube',
    }) =>
        TrailerOption(
          TmdbVideo(key: key, site: site, type: type, name: name, official: official),
          seasonNumber: season,
        );

    List<String> titles(List<TrailerGroup> groups) =>
        groups.map((g) => g.title).toList();

    test('drops non-YouTube and keyless videos', () {
      final groups = groupTrailerOptions([
        opt('Trailer', key: 'yt', site: 'YouTube'),
        opt('Trailer', key: 'vm', site: 'Vimeo'),
        opt('Trailer', key: ''), // keyless
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.options.single.video.key, 'yt');
    });

    test('buckets by type in Trailers → Teasers → Clips & More order', () {
      final groups = groupTrailerOptions([
        opt('Featurette', key: 'f'),
        opt('Teaser', key: 't'),
        opt('Trailer', key: 'r'),
        opt('Clip', key: 'c'),
      ]);
      expect(titles(groups), ['Trailers', 'Teasers', 'Clips & More']);
      expect(groups.last.options.map((o) => o.video.key), containsAll(['f', 'c']));
    });

    test('official videos sort before unofficial within a group', () {
      final groups = groupTrailerOptions([
        opt('Trailer', key: 'a', official: false, name: 'A'),
        opt('Trailer', key: 'b', official: true, name: 'B'),
      ]);
      expect(groups.single.options.map((o) => o.video.key).toList(), ['b', 'a']);
    });

    test('show-level sorts before season-specific, then by season ascending', () {
      final groups = groupTrailerOptions([
        opt('Trailer', key: 's2', season: 2),
        opt('Trailer', key: 's1', season: 1),
        opt('Trailer', key: 'show'), // show-level (no season)
      ]);
      expect(
        groups.single.options.map((o) => o.video.key).toList(),
        ['show', 's1', 's2'],
      );
    });

    test('de-dupes by video key', () {
      final groups = groupTrailerOptions([
        opt('Trailer', key: 'dup', name: 'first'),
        opt('Trailer', key: 'dup', name: 'second'),
      ]);
      expect(groups.single.options, hasLength(1));
    });

    test('is empty for no usable videos', () {
      expect(groupTrailerOptions([]), isEmpty);
      expect(groupTrailerOptions([opt('Trailer', key: 'x', site: 'Vimeo')]), isEmpty);
    });
  });
}
