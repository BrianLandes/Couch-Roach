import 'package:couch_roach/src/data/tmdb/movie_summary.dart';
import 'package:couch_roach/src/data/tmdb/tv_show_summary.dart';
import 'package:couch_roach/src/features/discover/discover_tile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromTv maps name/first_air_date and marks it TV', () {
    final tile = DiscoverTile.fromTv(TvShowSummary(
      tmdbId: 1,
      name: 'The Show',
      posterPath: '/p.jpg',
      overview: 'about',
      firstAirDate: '2011-04-17',
      voteAverage: 8.4,
    ));
    expect(tile.mediaType, 'tv');
    expect(tile.isTv, isTrue);
    expect(tile.title, 'The Show');
    expect(tile.year, 2011);
    expect(tile.posterPath, '/p.jpg');
    expect(tile.voteAverage, 8.4);
  });

  test('fromMovie maps title/release_date and marks it a movie', () {
    final tile = DiscoverTile.fromMovie(MovieSummary(
      tmdbId: 2,
      title: 'A Film',
      releaseDate: '2019-02-01',
    ));
    expect(tile.mediaType, 'movie');
    expect(tile.isTv, isFalse);
    expect(tile.title, 'A Film');
    expect(tile.year, 2019);
  });

  test('a missing or malformed date yields a null year', () {
    expect(DiscoverTile.fromMovie(MovieSummary(tmdbId: 3, title: 'x')).year,
        isNull);
    expect(
        DiscoverTile.fromTv(TvShowSummary(tmdbId: 4, name: 'y', firstAirDate: ''))
            .year,
        isNull);
  });
}
