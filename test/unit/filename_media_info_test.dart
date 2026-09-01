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

  group('normalizeTitle / titleMatches', () {
    test('normalizes separators, case, and punctuation', () {
      expect(FilenameMediaInfo.normalizeTitle('House.of.the.Dragon'),
          'houseofthedragon');
      expect(FilenameMediaInfo.normalizeTitle('House of the Dragon'),
          'houseofthedragon');
      expect(FilenameMediaInfo.normalizeTitle('house_of_the_dragon'),
          'houseofthedragon');
    });

    test('a release matches its show despite extra tokens', () {
      expect(
          FilenameMediaInfo.titleMatches(
              'House.of.the.Dragon.2022.S01E01.1080p', 'House of the Dragon'),
          isTrue);
    });

    test('a different show does not match', () {
      expect(
          FilenameMediaInfo.titleMatches(
              'Game.of.Thrones.S01E09', 'House of the Dragon'),
          isFalse);
    });

    test('an empty query never matches', () {
      expect(FilenameMediaInfo.titleMatches('Anything', ''), isFalse);
    });
  });

  group('titleMatchesStrict', () {
    bool m(String release, String query) =>
        FilenameMediaInfo.titleMatchesStrict(release, query);

    test('accepts the exact movie, with year/quality noise stripped', () {
      expect(m('Descendants.2015.1080p.WEB-DL.x264', 'Descendants'), isTrue);
      expect(m('Descendants 2015 BluRay', 'Descendants'), isTrue);
    });

    test('rejects a longer title that merely contains the target', () {
      expect(m('Descendants.Wicked.Wonderland.2024.1080p', 'Descendants'),
          isFalse);
      // Extra *leading* word is a different film too.
      expect(m('The.Descendants.2011.1080p', 'Descendants'), isFalse);
    });

    test('matches a year-in-title film symmetrically', () {
      expect(m('Blade.Runner.2049.2017.2160p', 'Blade Runner 2049'), isTrue);
      // A same-named earlier film is rejected by the year check.
      expect(m('Blade.Runner.1982.1080p', 'Blade Runner 2049'), isFalse);
    });

    test('reconciles roman-numeral sequels with digits, and & with and', () {
      expect(m('Frozen.2.2019.1080p', 'Frozen II'), isTrue);
      expect(m('Fast.and.Furious.2009', 'Fast & Furious'), isTrue);
    });

    test('a year-only title (empty parsed title) falls back to loose match', () {
      expect(m('2012.2009.1080p.BluRay', '2012'), isTrue);
    });
  });

  group('titleMatchesSeriesAware', () {
    bool m(String release, String query) =>
        FilenameMediaInfo.titleMatchesSeriesAware(release, query);

    test('matches the base series but not its numbered sequels', () {
      expect(m('Planet.Earth.S01E01.1080p', 'Planet Earth'), isTrue);
      // The bug this fixes: loose containment let "Planet Earth" pick up the
      // sequels because "planetearthii".contains("planetearth").
      expect(m('Planet.Earth.II.S01E01.1080p', 'Planet Earth'), isFalse);
      expect(m('Planet.Earth.III.S01E01.1080p', 'Planet Earth'), isFalse);
    });

    test('a numbered sequel query matches only its own release', () {
      expect(m('Planet.Earth.II.S01E01.1080p', 'Planet Earth II'), isTrue);
      // Fewer tokens than the query can't be the sequel.
      expect(m('Planet.Earth.S01E01.1080p', 'Planet Earth II'), isFalse);
      // A different sequel number is a different series.
      expect(m('Planet.Earth.III.S01E01.1080p', 'Planet Earth II'), isFalse);
    });

    test('folds roman numerals and digits both ways', () {
      expect(m('Planet.Earth.2.S01E01.1080p', 'Planet Earth II'), isTrue);
      expect(m('Planet.Earth.II.S01E01.1080p', 'Planet Earth 2'), isTrue);
    });

    test('still allows a region/edition qualifier the canonical name lacks', () {
      // The reason TV stays prefix-based rather than exact like movies.
      expect(m('The.Office.US.S01E01.720p', 'The Office'), isTrue);
      expect(m('Shameless.US.S02E03', 'Shameless'), isTrue);
    });

    test('rejects a shorter or unrelated release', () {
      expect(m('Earth.S01E01', 'Planet Earth'), isFalse);
      expect(m('Blue.Planet.S01E01', 'Planet Earth'), isFalse);
    });

    test('a query with no parseable tokens falls back to loose match', () {
      expect(m('2012.S01E01.1080p', '2012'), isTrue);
    });
  });

  group('releaseHeight', () {
    int? h(String t) => FilenameMediaInfo.releaseHeight(t);

    test('reads the usual resolution tags', () {
      expect(h('Show.S01E01.2160p.WEB-DL.x265'), 2160);
      expect(h('Show.S01E01.1080p.BluRay'), 1080);
      expect(h('Show S01E01 720p HDTV'), 720);
      expect(h('Old.Film.480p.DVDRip'), 480);
      expect(h('Show.S01E01.1080i.HDTV'), 1080); // interlaced counts
    });

    test('4K and UHD mean 2160', () {
      expect(h('Planet.Earth.II.4K.HDR'), 2160);
      expect(h('Planet Earth II UHD BluRay'), 2160);
    });

    test('is null when the title names no resolution', () {
      expect(h('Show.S01E01.WEB-DL.x264'), isNull);
      expect(h('Some Movie 2019'), isNull);
    });

    test('a bare number in the title is not a resolution', () {
      // Word-bounded and suffix-required, so these are not read as 1080/720.
      expect(h('Apollo 13'), isNull);
      expect(h('Blade.Runner.2049.BluRay'), isNull);
      expect(h('Show.S01E01.x264'), isNull);
    });
  });

  group('seasonPackNumber', () {
    test('reads S01 / Season 1 / Series 1 as a pack', () {
      expect(FilenameMediaInfo.seasonPackNumber('Game.of.Thrones.S01.1080p'), 1);
      expect(FilenameMediaInfo.seasonPackNumber('Game of Thrones Season 2'), 2);
      expect(FilenameMediaInfo.seasonPackNumber('The.Show.Series.3.Complete'), 3);
    });

    test('a single-episode name is not a pack', () {
      expect(FilenameMediaInfo.seasonPackNumber('Show.S01E03.1080p'), isNull);
      expect(FilenameMediaInfo.seasonPackNumber('Show - 1x03'), isNull);
    });

    test('no season marker at all is not a pack', () {
      expect(FilenameMediaInfo.seasonPackNumber('Some.Movie.2020.1080p'), isNull);
    });
  });

  group('isShowPack', () {
    test('complete-series / all-seasons markers are show packs', () {
      expect(FilenameMediaInfo.isShowPack('The.Office.Complete.Series.1080p'),
          isTrue);
      expect(FilenameMediaInfo.isShowPack('Breaking Bad - Full Series'), isTrue);
      expect(FilenameMediaInfo.isShowPack('Lost.All.Seasons.720p'), isTrue);
    });

    test('a season range is a show pack', () {
      expect(FilenameMediaInfo.isShowPack('Game.of.Thrones.S01-S08.1080p'),
          isTrue);
      expect(FilenameMediaInfo.isShowPack('The.Wire.Seasons.1-5.BluRay'), isTrue);
      expect(FilenameMediaInfo.isShowPack('Dexter.S01-08'), isTrue);
    });

    test('a single season or single episode is not a show pack', () {
      expect(FilenameMediaInfo.isShowPack('Game.of.Thrones.S01.1080p'), isFalse);
      expect(FilenameMediaInfo.isShowPack('Game of Thrones Season 2'), isFalse);
      expect(
          FilenameMediaInfo.isShowPack('Game.of.Thrones.S01E03.1080p'), isFalse);
      // A single episode tagged "Complete" is still just one episode.
      expect(FilenameMediaInfo.isShowPack('Show.S01E01.Complete.1080p'), isFalse);
    });

    test('a movie is not a show pack', () {
      expect(FilenameMediaInfo.isShowPack('Some.Movie.2020.1080p'), isFalse);
    });
  });

  group('looksLikeSignLanguage', () {
    test('flags ASL/BSL/sign language cuts', () {
      expect(FilenameMediaInfo.looksLikeSignLanguage('Show.S01E03.ASL.1080p'),
          isTrue);
      expect(FilenameMediaInfo.looksLikeSignLanguage('Show.S01E03.BSL'), isTrue);
      expect(
          FilenameMediaInfo.looksLikeSignLanguage('Show Sign Language Version'),
          isTrue);
    });

    test('does not flag ordinary releases', () {
      expect(
          FilenameMediaInfo.looksLikeSignLanguage('Show.S01E03.1080p.WEB-DL'),
          isFalse);
      // "asl" only as a bounded token — not inside another word.
      expect(FilenameMediaInfo.looksLikeSignLanguage('Hassle.2019.1080p'),
          isFalse);
    });
  });

  group('audioLanguageScore', () {
    int score(String title, String lang) =>
        FilenameMediaInfo.audioLanguageScore(title, lang);

    test('explicit language tags score 2', () {
      expect(score('Some.Movie.2020.Dublado.PT.1080p', 'portuguese'), 2);
      expect(score('Some.Movie.PORTUGUES', 'portuguese'), 2);
      // Accepts a language code / native name as the query too.
      expect(score('Filme.TRUEFRENCH.1080p', 'fr'), 2);
      expect(score('Film.iTA.BluRay', 'italian'), 2);
    });

    test('a generic multi/dual-audio marker scores 1', () {
      expect(score('Some.Movie.2020.MULTI.1080p', 'portuguese'), 1);
      expect(score('Some.Movie.Dual.Audio.720p', 'spanish'), 1);
    });

    test('an unrelated release scores 0', () {
      expect(score('Some.Movie.2020.1080p.WEB-DL', 'portuguese'), 0);
    });

    test('empty preference always scores 0', () {
      expect(score('Some.Movie.Dublado.PT', ''), 0);
    });

    test('does not false-match a bare code inside a word', () {
      // "it" (Italian code) is intentionally not a token — "It" the film and
      // words like "spirit" must not read as Italian audio.
      expect(score('It.2017.1080p.BluRay', 'italian'), 0);
      expect(score('Spirit.2002.1080p', 'italian'), 0);
    });
  });
}
