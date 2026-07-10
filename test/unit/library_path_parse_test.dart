import 'package:couch_roach/src/features/library/library_path_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLibraryPath — filename markers', () {
    test('SxxExx in the filename → tv with season/episode + show name', () {
      final m =
          parseLibraryPath('/tv/Breaking Bad/Season 01/Breaking.Bad.S01E02.1080p.mkv');
      expect(m.mediaType, 'tv');
      expect(m.title, 'Breaking Bad');
      expect(m.season, 1);
      expect(m.episode, 2);
    });

    test('NxM marker works too', () {
      final m = parseLibraryPath('/tv/Show/Season 01/Show - 1x03 - Title.mkv');
      expect(m.mediaType, 'tv');
      expect(m.season, 1);
      expect(m.episode, 3);
    });

    test('a marker-only filename borrows the show name from the folder', () {
      final m = parseLibraryPath('/tv/Firefly/Season 1/S01E01.mkv');
      expect(m.title, 'Firefly');
      expect(m.season, 1);
      expect(m.episode, 1);
    });
  });

  group('parseLibraryPath — season folder (no marker in filename)', () {
    test('leading episode number', () {
      final m = parseLibraryPath("/tv/Breaking Bad/Season 1/02 - Cat's in the Bag.mkv");
      expect(m.mediaType, 'tv');
      expect(m.title, 'Breaking Bad');
      expect(m.season, 1);
      expect(m.episode, 2);
    });

    test('"Episode N" wording', () {
      final m = parseLibraryPath('/tv/Some Show/Season 2/Episode 5.mkv');
      expect(m.mediaType, 'tv');
      expect(m.title, 'Some Show');
      expect(m.season, 2);
      expect(m.episode, 5);
    });

    test('strips a year off the show folder name', () {
      final m = parseLibraryPath('/tv/Fargo (2014)/Season 3/03 whatever.mkv');
      expect(m.title, 'Fargo');
      expect(m.season, 3);
    });
  });

  group('parseLibraryPath — movies', () {
    test('quality/group tokens are stripped from the title', () {
      final m = parseLibraryPath('/movies/The.Matrix.1999.1080p.BluRay.x264-GRP.mkv');
      expect(m.mediaType, 'movie');
      expect(m.title, 'The Matrix');
    });

    test('a loose file with no TV signal is a movie', () {
      final m = parseLibraryPath('/x/Inception.mkv');
      expect(m.mediaType, 'movie');
      expect(m.title, 'Inception');
    });
  });

  group('showFolderName', () {
    test('grandparent when inside a Season folder', () {
      expect(showFolderName('/tv/Breaking Bad/Season 01/x.mkv'), 'Breaking Bad');
    });
    test('parent otherwise, with a year stripped', () {
      expect(showFolderName('/movies/The Matrix (1999)/x.mkv'), 'The Matrix');
    });
  });

  group('isSeasonFolder', () {
    test('recognizes the common shapes', () {
      for (final f in ['Season 1', 'Season 01', 'Series 2', 'S01', 's1']) {
        expect(isSeasonFolder(f), isTrue, reason: f);
      }
    });
    test('rejects non-season folders', () {
      for (final f in ['Specials', 'Movies', 'Extras', 'Breaking Bad']) {
        expect(isSeasonFolder(f), isFalse, reason: f);
      }
    });
  });

  group('tmdbSearchCandidates', () {
    test('stored title first, then the show folder, deduped', () {
      final c = tmdbSearchCandidates(
          '/movies/The Matrix (1999)/The.Matrix.1999.1080p.mkv', 'The Matrix');
      expect(c, ['The Matrix']); // folder resolves to the same clean name
    });

    test('surfaces the clean folder name when the stored title is messy', () {
      final c = tmdbSearchCandidates(
          '/tv/The Office (US)/Season 3/tos.s03e04.HDTV.mkv', 'tos');
      expect(c.first, 'tos');
      expect(c, contains('The Office (US)'));
    });
  });

  group('pickBestMatchIndex', () {
    test('exact normalized match wins', () {
      expect(pickBestMatchIndex(['The Office', 'Office Space'], 'the office'), 0);
    });
    test('containment either direction', () {
      expect(pickBestMatchIndex(['The Office'], 'Office'), 0);
      expect(pickBestMatchIndex(['Office'], 'The Office US'), 0);
    });
    test('null when nothing is a confident match', () {
      expect(pickBestMatchIndex(['Totally Unrelated'], 'Breaking Bad'), isNull);
    });
    test('null on an empty query', () {
      expect(pickBestMatchIndex(['Whatever'], ''), isNull);
    });
  });

  group('unmatchedShowKey', () {
    test('two episodes in the same show folder share a key', () {
      final a = unmatchedShowKey('/tv/Breaking Bad/Season 1/01.mkv', 'x');
      final b = unmatchedShowKey('/tv/Breaking Bad/Season 2/05.mkv', 'y');
      expect(a, b);
      expect(a, isNotEmpty);
    });
  });
}
