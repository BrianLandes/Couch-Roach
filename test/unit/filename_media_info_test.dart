import 'package:couch_roach/src/services/subtitles/filename_media_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('episodes', () {
    test('Show.Name.S01E02.1080p.WEB-DL.mkv', () {
      final r = FilenameMediaInfo.parse('Show.Name.S01E02.1080p.WEB-DL.mkv');
      expect(r.title, 'Show Name');
      expect(r.season, 1);
      expect(r.episode, 2);
      expect(r.hasEpisode, isTrue);
    });

    test('lowercase and multi-digit episode', () {
      final r = FilenameMediaInfo.parse('the_show_s10e123_720p.mkv');
      expect(r.title, 'the show');
      expect(r.season, 10);
      expect(r.episode, 123);
    });

    test('1x02 alternate form', () {
      final r = FilenameMediaInfo.parse('Show Name - 1x02 - Pilot.mkv');
      expect(r.title, 'Show Name'); // trailing " - " is trimmed off
      expect(r.season, 1);
      expect(r.episode, 2);
    });

    test('space-separated S01 E02', () {
      final r = FilenameMediaInfo.parse('Cool Show S01 E02.mkv');
      expect(r.title, 'Cool Show');
      expect(r.season, 1);
      expect(r.episode, 2);
    });
  });

  group('movies', () {
    test('year marks the title boundary', () {
      final r = FilenameMediaInfo.parse('Great.Movie.2019.1080p.BluRay.mkv');
      expect(r.title, 'Great Movie');
      expect(r.year, 2019);
      expect(r.season, isNull);
      expect(r.episode, isNull);
      expect(r.hasEpisode, isFalse);
    });

    test('no year: quality tokens are stripped', () {
      final r = FilenameMediaInfo.parse('Another Movie 720p x264.mkv');
      expect(r.title, 'Another Movie');
      expect(r.year, isNull);
    });

    test('plain title with no markers', () {
      final r = FilenameMediaInfo.parse('Just A Title.mkv');
      expect(r.title, 'Just A Title');
      expect(r.season, isNull);
    });
  });

  test('S/E takes precedence over a year in the name', () {
    final r = FilenameMediaInfo.parse('Show.2020.S03E04.mkv');
    expect(r.season, 3);
    expect(r.episode, 4);
    // Title keeps everything before the S/E marker.
    expect(r.title, 'Show 2020');
  });

  test('bare marker yields an empty title', () {
    final r = FilenameMediaInfo.parse('S01E05.mkv');
    expect(r.title, isEmpty);
    expect(r.season, 1);
    expect(r.episode, 5);
  });
}
