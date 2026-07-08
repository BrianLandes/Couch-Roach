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
}
