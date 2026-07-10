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

  test('movieDetails parses the /movie/{id} response as a summary', () async {
    final client = clientFor({
      '/movie/550': {
        'id': 550,
        'title': 'Fight Club',
        'poster_path': '/fc.jpg',
        'release_date': '1999-10-15',
        'vote_average': 8.4,
      },
    });

    final movie = await client.movieDetails(550);
    expect(movie, isNotNull);
    expect(movie!.tmdbId, 550);
    expect(movie.title, 'Fight Club');
    expect(movie.posterPath, '/fc.jpg');
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

  test('videos hits the tv or movie endpoint by media type', () async {
    final client = clientFor({
      '/tv/1399/videos': {
        'results': [
          {'key': 'yt1', 'site': 'YouTube', 'type': 'Trailer', 'official': true},
        ],
      },
      '/movie/550/videos': {
        'results': [
          {'key': 'yt2', 'site': 'YouTube', 'type': 'Teaser'},
        ],
      },
    });
    expect((await client.videos(tmdbId: 1399, isTv: true)).single.key, 'yt1');
    expect((await client.videos(tmdbId: 550, isTv: false)).single.type, 'Teaser');
  });

  test('seasonVideos hits the per-season endpoint', () async {
    final client = clientFor({
      '/tv/1399/season/2/videos': {
        'results': [
          {
            'key': 's2',
            'site': 'YouTube',
            'type': 'Trailer',
            'name': 'Season 2 Trailer',
          },
        ],
      },
    });
    final vids = await client.seasonVideos(tmdbId: 1399, seasonNumber: 2);
    expect(vids.single.key, 's2');
    expect(vids.single.name, 'Season 2 Trailer');
  });

  test('episodeCredits parses guest stars and cast separately', () async {
    final client = clientFor({
      '/tv/1399/season/1/episode/1/credits': {
        'cast': [
          {'id': 10, 'name': 'Sean Bean', 'character': 'Ned', 'order': 0},
        ],
        'guest_stars': [
          {'id': 20, 'name': 'Guest One', 'character': 'Innkeeper'},
        ],
      },
    });
    final credits = await client.episodeCredits(1399, 1, 1);
    expect(credits.cast.single.name, 'Sean Bean');
    expect(credits.cast.single.character, 'Ned');
    expect(credits.guestStars.single.personId, 20);
  });

  test('tvCast / movieCast read the cast array', () async {
    final client = clientFor({
      '/tv/1399/credits': {
        'cast': [
          {'id': 10, 'name': 'A', 'character': 'X'},
          {'id': 11, 'name': 'B', 'character': 'Y'},
        ],
      },
      '/movie/550/credits': {
        'cast': [
          {'id': 12, 'name': 'C', 'character': 'Z', 'profile_path': '/c.jpg'},
        ],
      },
    });
    expect((await client.tvCast(1399)).map((c) => c.name), ['A', 'B']);
    expect((await client.movieCast(550)).single.profilePath, '/c.jpg');
  });

  test('personCredits parses combined credits (movies + tv)', () async {
    final client = clientFor({
      '/person/10/combined_credits': {
        'cast': [
          {
            'id': 550,
            'media_type': 'movie',
            'title': 'Fight Club',
            'poster_path': '/fc.jpg',
            'popularity': 42.0,
            'release_date': '1999-10-15',
          },
          {
            'id': 1399,
            'media_type': 'tv',
            'name': 'Game of Thrones',
            'poster_path': '/got.jpg',
            'first_air_date': '2011-04-17',
          },
        ],
      },
    });
    final credits = await client.personCredits(10);
    expect(credits, hasLength(2));
    expect(credits[0].displayTitle, 'Fight Club');
    expect(credits[0].year, '1999');
    expect(credits[1].displayTitle, 'Game of Thrones');
  });

  test('non-200 degrades to empty/null (logged, not thrown)', () async {
    final client = clientFor({}); // everything 404
    expect(await client.searchTv('x'), isEmpty);
    expect(await client.tvDetails(1), isNull);
    expect(await client.trendingMovies(), isEmpty);
    expect(await client.discoverMovies(genreId: 99), isEmpty);
    expect(await client.videos(tmdbId: 1, isTv: true), isEmpty);
  });

  test('TmdbImages builds CDN urls and passes nulls through', () {
    expect(TmdbImages.poster('/abc.jpg'),
        'https://image.tmdb.org/t/p/w342/abc.jpg');
    expect(TmdbImages.backdrop(null), isNull);
  });
}
