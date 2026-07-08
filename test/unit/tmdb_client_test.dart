import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/data/tmdb/tmdb_images.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A client whose HTTP layer returns canned JSON for paths containing a key.
  TmdbClient clientFor(Map<String, Object> routes) {
    final mock = MockClient((req) async {
      for (final entry in routes.entries) {
        if (req.url.path.contains(entry.key)) {
          return http.Response(jsonEncode(entry.value), 200,
              headers: {'content-type': 'application/json'});
        }
      }
      return http.Response('{}', 404);
    });
    return TmdbClient(mock, ErrorLogService());
  }

  test('searchTv parses list results', () async {
    final client = clientFor({
      '/search/tv': {
        'results': [
          {
            'id': 1399,
            'name': 'Game of Thrones',
            'overview': 'Nine noble families…',
            'poster_path': '/x.jpg',
            'first_air_date': '2011-04-17',
            'vote_average': 8.4,
          },
        ],
      },
    });

    final results = await client.searchTv('game of thrones');
    expect(results, hasLength(1));
    expect(results.first.tmdbId, 1399);
    expect(results.first.name, 'Game of Thrones');
    expect(results.first.voteAverage, 8.4);
  });

  test('tvDetails parses genres + seasons', () async {
    final client = clientFor({
      '/tv/1399': {
        'id': 1399,
        'name': 'Game of Thrones',
        'number_of_seasons': 8,
        'genres': [
          {'id': 10765, 'name': 'Sci-Fi & Fantasy'},
        ],
        'seasons': [
          {'season_number': 1, 'name': 'Season 1', 'episode_count': 10},
        ],
      },
    });

    final details = await client.tvDetails(1399);
    expect(details, isNotNull);
    expect(details!.numberOfSeasons, 8);
    expect(details.genres.single.name, 'Sci-Fi & Fantasy');
    expect(details.seasons.single.seasonNumber, 1);
    expect(details.seasons.single.episodeCount, 10);
  });

  test('seasonDetails parses episodes', () async {
    final client = clientFor({
      '/tv/1399/season/1': {
        'season_number': 1,
        'name': 'Season 1',
        'episodes': [
          {
            'episode_number': 1,
            'name': 'Winter Is Coming',
            'still_path': '/e.jpg',
            'runtime': 62,
            'vote_average': 8.0,
          },
        ],
      },
    });

    final season = await client.seasonDetails(1399, 1);
    expect(season, isNotNull);
    expect(season!.episodes.single.episodeNumber, 1);
    expect(season.episodes.single.name, 'Winter Is Coming');
    expect(season.episodes.single.runtime, 62);
  });

  test('discoverMovies parses list results (documentary genre)', () async {
    http.Request? captured;
    final client = TmdbClient(
      MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'results': [
              {'id': 7, 'title': 'Some Doc', 'poster_path': '/d.jpg', 'release_date': '2019-02-01'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      ErrorLogService(),
    );

    final movies = await client.discoverMovies(genreId: 99);
    expect(movies.single.title, 'Some Doc');
    expect(captured!.url.path, contains('/discover/movie'));
    expect(captured!.url.queryParameters['with_genres'], '99');
    expect(captured!.url.queryParameters['sort_by'], 'popularity.desc');
  });

  test('non-200 degrades to empty/null (logged, not thrown)', () async {
    final client = clientFor({}); // everything 404
    expect(await client.searchTv('x'), isEmpty);
    expect(await client.tvDetails(1), isNull);
    expect(await client.trendingMovies(), isEmpty);
    expect(await client.discoverMovies(genreId: 99), isEmpty);
  });

  test('TmdbImages builds CDN urls and passes nulls through', () {
    expect(TmdbImages.poster('/abc.jpg'),
        'https://image.tmdb.org/t/p/w342/abc.jpg');
    expect(TmdbImages.backdrop(null), isNull);
  });
}
