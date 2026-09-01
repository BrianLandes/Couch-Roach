import 'package:couch_roach/src/features/discover/discover_tile.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tile as the landing rails build one from a local row (a saved / Alexa-queued
/// / recently-downloaded title): identity and artwork only, no profile.
const _sparse = DiscoverTile(
  tmdbId: 693134,
  title: 'Dune: Part Two',
  mediaType: 'movie',
  posterPath: '/saved.jpg',
);

/// The same title as TMDB returns it.
const _fetched = DiscoverTile(
  tmdbId: 693134,
  title: 'Dune: Part Two',
  mediaType: 'movie',
  posterPath: '/tmdb.jpg',
  overview: 'Paul Atreides unites with the Fremen.',
  year: 2024,
  voteAverage: 8.2,
);

void main() {
  group('hydrateTile', () {
    test('fills a sparse tile with the fetched profile', () {
      final t = hydrateTile(_sparse, _fetched);
      expect(t.overview, 'Paul Atreides unites with the Fremen.');
      expect(t.year, 2024);
      expect(t.voteAverage, 8.2);
      expect(t.posterPath, '/tmdb.jpg');
    });

    // The page must paint immediately off what it was pushed with, rather than
    // blanking while the fetch is in flight.
    test('a pending or missed fetch leaves the tile untouched', () {
      expect(hydrateTile(_sparse, null), same(_sparse));
    });

    test('identity always comes from the base tile', () {
      // The fetch was keyed on these; a mismatched response must not smuggle in
      // a different title's id or flip a movie into a show.
      const wrong = DiscoverTile(
          tmdbId: 1, title: 'Something Else', mediaType: 'tv', year: 1999);
      final t = hydrateTile(_sparse, wrong);
      expect(t.tmdbId, 693134);
      expect(t.mediaType, 'movie');
    });

    group('falls back field by field so a partial response blanks nothing', () {
      test('an empty overview keeps the one already shown', () {
        const base = DiscoverTile(
            tmdbId: 1,
            title: 'A',
            mediaType: 'movie',
            overview: 'Already known.');
        const partial =
            DiscoverTile(tmdbId: 1, title: 'A', mediaType: 'movie', year: 2001);
        expect(hydrateTile(base, partial).overview, 'Already known.');
      });

      test('a null poster keeps the cached artwork', () {
        const partial = DiscoverTile(
            tmdbId: 693134, title: 'Dune: Part Two', mediaType: 'movie');
        expect(hydrateTile(_sparse, partial).posterPath, '/saved.jpg');
      });

      test('an empty title keeps the saved name', () {
        const partial =
            DiscoverTile(tmdbId: 693134, title: '', mediaType: 'movie');
        expect(hydrateTile(_sparse, partial).title, 'Dune: Part Two');
      });

      test('a null year or rating keeps whatever the base had', () {
        const base = DiscoverTile(
            tmdbId: 1,
            title: 'A',
            mediaType: 'movie',
            year: 1999,
            voteAverage: 7.0);
        const partial = DiscoverTile(
            tmdbId: 1, title: 'A', mediaType: 'movie', overview: 'New.');
        final t = hydrateTile(base, partial);
        expect(t.year, 1999);
        expect(t.voteAverage, 7.0);
        expect(t.overview, 'New.');
      });
    });

    test('a fetched value wins over a stale base value', () {
      const base = DiscoverTile(
          tmdbId: 1, title: 'A', mediaType: 'movie', year: 1999, voteAverage: 1);
      const fresh = DiscoverTile(
          tmdbId: 1, title: 'A', mediaType: 'movie', year: 2001, voteAverage: 9);
      final t = hydrateTile(base, fresh);
      expect(t.year, 2001);
      expect(t.voteAverage, 9);
    });

    test('hydrating an already-full tile is a no-op in effect', () {
      final t = hydrateTile(_fetched, _fetched);
      expect(t.overview, _fetched.overview);
      expect(t.year, _fetched.year);
      expect(t.posterPath, _fetched.posterPath);
    });
  });
}
