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
      // Folder resolves to the same clean name, so it's one search — but the
      // folder's "(1999)" survives as the year to sharpen it.
      expect(c.map((e) => e.query), ['The Matrix']);
    });

    test('surfaces the clean folder name when the stored title is messy', () {
      final c = tmdbSearchCandidates(
          '/tv/The Office (US)/Season 3/tos.s03e04.HDTV.mkv', 'tos');
      expect(c.first.query, 'tos');
      expect(c.map((e) => e.query), contains('The Office (US)'));
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

    group('short strings do not count as containment', () {
      // The bug this guard closes: a one-letter query is a substring of almost
      // every title, so a stray short candidate swept up whatever TMDB returned.
      test('a single-letter query matches nothing by containment', () {
        expect(pickBestMatchIndex(['Something Entirely Different'], 'm'), isNull);
      });

      test('a two-letter query no longer grabs a title that contains it', () {
        // "titanic" really does contain "it".
        expect(pickBestMatchIndex(['Titanic'], 'It'), isNull);
      });

      test('a short result inside a long query is just as weak', () {
        // The other direction: "saw" ⊂ "jigsawpuzzlemurders".
        expect(pickBestMatchIndex(['Saw'], 'Jigsaw Puzzle Murders'), isNull);
      });

      test('the floor is on the contained side, not the pair', () {
        // A long result doesn't rescue a short query.
        expect(
            pickBestMatchIndex(['The Extremely Long Movie Title'], 'x'), isNull);
      });
    });

    group('genuinely short titles still match', () {
      // The floor is only on containment; the exact pass has no length rule, so
      // real one- and two-character films are unaffected.
      test('an exact match wins at any length', () {
        expect(pickBestMatchIndex(['M'], 'M'), 0);
        expect(pickBestMatchIndex(['Up'], 'Up'), 0);
        expect(pickBestMatchIndex(['It'], 'It'), 0);
      });

      test('an exact match is preferred over an earlier containment', () {
        expect(pickBestMatchIndex(['Titanic', 'It'], 'It'), 1);
      });
    });

    group('the containment floor boundary', () {
      test('four characters is enough', () {
        expect(pickBestMatchIndex(['Dune: Part Two'], 'Dune'), 0);
      });

      test('three is not', () {
        expect(pickBestMatchIndex(['Jigsaw'], 'Saw'), isNull);
      });

      test('kMinContainmentChars is the documented threshold', () {
        expect(kMinContainmentChars, 4);
      });
    });
  });

  group('tmdbSearchCandidates', () {
    /// Just the query text, for the cases where the year isn't what's under test.
    List<String> queriesOf(String path, String title,
            {Set<String> rootPaths = const {}}) =>
        tmdbSearchCandidates(path, title, rootPaths: rootPaths)
            .map((c) => c.query)
            .toList();

    test('offers the stored title first, then the show folder', () {
      expect(
        queriesOf('/tv/The Office/xyz.release.mkv', 'The Office'),
        ['The Office'],
      );
      // A useless filename is rescued by the folder that names the show.
      expect(
        queriesOf('/tv/The Office/xyz.release.mkv', 'xyz release'),
        ['xyz release', 'The Office'],
      );
    });

    // The other half of the false-match bug: with the canonical layout the
    // "folder" is just the library root, so this searched TMDB for "movies".
    test('a file loose in a library root contributes no folder candidate', () {
      expect(
        queriesOf('/movies/Inception.mkv', 'Inception',
            rootPaths: {'/movies'}),
        ['Inception'],
      );
    });

    test('a file inside a folder under a root still offers the folder', () {
      expect(
        queriesOf('/movies/Inception (2010)/Inception.mkv', 'raw.release',
            rootPaths: {'/movies'}),
        // cleanShowName turns release-style dots into spaces.
        ['raw release', 'Inception'],
      );
    });

    test('an unrelated root does not suppress a real show folder', () {
      expect(
        queriesOf('/tv/The Office/xyz.mkv', 'xyz', rootPaths: {'/movies'}),
        ['xyz', 'The Office'],
      );
    });

    test('a season folder is skipped in favour of the show folder', () {
      expect(
        queriesOf('/tv/The Office/Season 2/xyz.mkv', 'xyz',
            rootPaths: {'/tv'}),
        ['xyz', 'The Office'],
      );
    });

    test('duplicate candidates are collapsed', () {
      expect(
        queriesOf('/tv/The Office/The Office.mkv', 'The Office'),
        ['The Office'],
      );
    });

    group('carries the year it strips, to sharpen the search', () {
      // The point of the record: cleanShowName removes the year from the query
      // text, so without carrying it separately TMDB never sees a `year=`
      // filter and "Dune" stays ambiguous across three films.
      test('a bare trailing year', () {
        final c = tmdbSearchCandidates('/movies/Dune 2021.mkv', 'Dune 2021',
            rootPaths: {'/movies'});
        expect(c.single, (query: 'Dune', year: 2021));
      });

      test('a parenthesised year', () {
        final c = tmdbSearchCandidates(
            '/movies/Dune (2021).mkv', 'Dune (2021)', rootPaths: {'/movies'});
        expect(c.single, (query: 'Dune', year: 2021));
      });

      test('no year named leaves it null rather than guessing', () {
        final c = tmdbSearchCandidates('/movies/Dune.mkv', 'Dune',
            rootPaths: {'/movies'});
        expect(c.single, (query: 'Dune', year: null));
      });

      test('a year in the folder is picked up for the folder candidate', () {
        final c = tmdbSearchCandidates(
            '/movies/Blade Runner (1982)/raw.release.mkv', 'raw release',
            rootPaths: {'/movies'});
        expect(c, [
          (query: 'raw release', year: null),
          (query: 'Blade Runner', year: 1982),
        ]);
      });

      // A number that isn't a plausible release year is part of the title.
      test('a title that merely ends in digits keeps them', () {
        expect(splitShowNameYear('Apollo 13'), ('Apollo 13', null));
        expect(splitShowNameYear('Se7en'), ('Se7en', null));
      });

      test('a year-shaped title is not mistaken for a year', () {
        // "2012" is the whole title, not a suffix to strip.
        expect(splitShowNameYear('2012'), ('2012', null));
      });
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
