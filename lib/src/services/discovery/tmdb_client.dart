import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../data/tmdb/credits.dart';
import '../../data/tmdb/movie_summary.dart';
import '../../data/tmdb/season.dart';
import '../../data/tmdb/tmdb_video.dart';
import '../../data/tmdb/tv_show_details.dart';
import '../../data/tmdb/tv_show_summary.dart';

/// TMDB discovery client (HANDOFF §6). Read-only metadata over HTTP; the API key
/// comes from [AppConfig]. Failures are logged and return empty/null so callers
/// degrade gracefully rather than throw into the UI.
abstract class DiscoveryClient {
  Future<List<TvShowSummary>> searchTv(String query, {int? year});
  Future<List<MovieSummary>> searchMovies(String query, {int? year});
  Future<TvShowDetails?> tvDetails(int tmdbId);

  /// Full movie details (`movie/{id}`) — used to back-fill a known-id movie's
  /// canonical title + poster without a fuzzy title search. Returned as a
  /// [MovieSummary] since the details response is a superset of the list shape.
  Future<MovieSummary?> movieDetails(int tmdbId);

  Future<SeasonDetails?> seasonDetails(int tmdbId, int seasonNumber);
  Future<List<TvShowSummary>> trendingTv();
  Future<List<MovieSummary>> trendingMovies();

  /// Discover movies, optionally within a genre (e.g. 99 = Documentary), sorted
  /// by popularity — the source for the category rails.
  Future<List<MovieSummary>> discoverMovies({int? genreId});

  /// Discover TV, optionally within a genre — the TV counterpart of
  /// [discoverMovies] for the personalized category rails.
  Future<List<TvShowSummary>> discoverTv({int? genreId});

  /// Recommendations for a show — the "similar to what you watched" feed.
  Future<List<TvShowSummary>> recommendedTv(int tmdbId);

  /// Recommendations for a movie (the movie counterpart of [recommendedTv]).
  Future<List<MovieSummary>> recommendedMovies(int tmdbId);

  /// A title's genres ({id, name}) from its details — the taste-inference input.
  Future<List<Genre>> titleGenres(int tmdbId, {required bool isTv});

  /// Videos (trailers/teasers) for a title — the preview source.
  Future<List<TmdbVideo>> videos({required int tmdbId, required bool isTv});

  /// Season-specific videos for a TV title — trailers/teasers TMDB attaches to
  /// an individual season (`/tv/{id}/season/{n}/videos`), which the show-level
  /// [videos] call doesn't return.
  Future<List<TmdbVideo>> seasonVideos({
    required int tmdbId,
    required int seasonNumber,
  });

  /// The cast credited on a specific TV episode — its guest stars and its
  /// (episode-scoped) regular cast. Drives the "Who's in this?" panel.
  Future<({List<CastMember> guestStars, List<CastMember> cast})> episodeCredits(
    int tmdbId,
    int seasonNumber,
    int episodeNumber,
  );

  /// A show's main/recurring cast (`/tv/{id}/credits`).
  Future<List<CastMember>> tvCast(int tmdbId);

  /// A movie's cast (`/movie/{id}/credits`).
  Future<List<CastMember>> movieCast(int tmdbId);

  /// A person's combined film/TV credits — the "known for" feed for an actor.
  Future<List<PersonCredit>> personCredits(int personId);
}

@LazySingleton(as: DiscoveryClient)
class TmdbClient implements DiscoveryClient {
  TmdbClient(this._http, this._log);

  final http.Client _http;
  final ErrorLogService _log;

  static const _base = 'https://api.themoviedb.org/3';

  Future<Map<String, dynamic>?> _get(
    String path, [
    Map<String, String>? params,
  ]) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: {
      'api_key': AppConfig.tmdbApiKey,
      'language': 'en-US',
      ...?params,
    });
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) {
        _log.warn('TMDB ${res.statusCode} for $path', source: 'TmdbClient');
        return null;
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'TmdbClient.get($path)');
      return null;
    }
  }

  List<T> _results<T>(
    Map<String, dynamic>? json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final list = json?['results'] as List<dynamic>?;
    if (list == null) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<TvShowSummary>> searchTv(String query, {int? year}) async =>
      _results(
        await _get('/search/tv', {
          'query': query,
          if (year != null) 'first_air_date_year': '$year',
        }),
        TvShowSummary.fromJson,
      );

  @override
  Future<List<MovieSummary>> searchMovies(String query, {int? year}) async =>
      _results(
        await _get('/search/movie', {
          'query': query,
          if (year != null) 'year': '$year',
        }),
        MovieSummary.fromJson,
      );

  @override
  Future<TvShowDetails?> tvDetails(int tmdbId) async {
    final json = await _get('/tv/$tmdbId');
    return json == null ? null : TvShowDetails.fromJson(json);
  }

  @override
  Future<MovieSummary?> movieDetails(int tmdbId) async {
    final json = await _get('/movie/$tmdbId');
    return json == null ? null : MovieSummary.fromJson(json);
  }

  @override
  Future<SeasonDetails?> seasonDetails(int tmdbId, int seasonNumber) async {
    final json = await _get('/tv/$tmdbId/season/$seasonNumber');
    return json == null ? null : SeasonDetails.fromJson(json);
  }

  @override
  Future<List<TvShowSummary>> trendingTv() async =>
      _results(await _get('/trending/tv/week'), TvShowSummary.fromJson);

  @override
  Future<List<MovieSummary>> trendingMovies() async =>
      _results(await _get('/trending/movie/week'), MovieSummary.fromJson);

  @override
  Future<List<MovieSummary>> discoverMovies({int? genreId}) async => _results(
        await _get('/discover/movie', {
          'sort_by': 'popularity.desc',
          'vote_count.gte': '50', // trim obscure/noise entries
          if (genreId != null) 'with_genres': '$genreId',
        }),
        MovieSummary.fromJson,
      );

  @override
  Future<List<TvShowSummary>> discoverTv({int? genreId}) async => _results(
        await _get('/discover/tv', {
          'sort_by': 'popularity.desc',
          'vote_count.gte': '50',
          if (genreId != null) 'with_genres': '$genreId',
        }),
        TvShowSummary.fromJson,
      );

  @override
  Future<List<TvShowSummary>> recommendedTv(int tmdbId) async =>
      _results(await _get('/tv/$tmdbId/recommendations'), TvShowSummary.fromJson);

  @override
  Future<List<MovieSummary>> recommendedMovies(int tmdbId) async => _results(
        await _get('/movie/$tmdbId/recommendations'), MovieSummary.fromJson);

  @override
  Future<List<Genre>> titleGenres(int tmdbId, {required bool isTv}) async {
    final json = await _get('/${isTv ? 'tv' : 'movie'}/$tmdbId');
    final list = json?['genres'] as List<dynamic>?;
    if (list == null) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Genre.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<TmdbVideo>> videos({
    required int tmdbId,
    required bool isTv,
  }) async =>
      _results(
        await _get('/${isTv ? 'tv' : 'movie'}/$tmdbId/videos'),
        TmdbVideo.fromJson,
      );

  @override
  Future<List<TmdbVideo>> seasonVideos({
    required int tmdbId,
    required int seasonNumber,
  }) async =>
      _results(
        await _get('/tv/$tmdbId/season/$seasonNumber/videos'),
        TmdbVideo.fromJson,
      );

  @override
  Future<({List<CastMember> guestStars, List<CastMember> cast})> episodeCredits(
    int tmdbId,
    int seasonNumber,
    int episodeNumber,
  ) async {
    final json = await _get(
        '/tv/$tmdbId/season/$seasonNumber/episode/$episodeNumber/credits');
    return (
      guestStars: _list(json, 'guest_stars', CastMember.fromJson),
      cast: _list(json, 'cast', CastMember.fromJson),
    );
  }

  @override
  Future<List<CastMember>> tvCast(int tmdbId) async =>
      _list(await _get('/tv/$tmdbId/credits'), 'cast', CastMember.fromJson);

  @override
  Future<List<CastMember>> movieCast(int tmdbId) async =>
      _list(await _get('/movie/$tmdbId/credits'), 'cast', CastMember.fromJson);

  @override
  Future<List<PersonCredit>> personCredits(int personId) async => _list(
        await _get('/person/$personId/combined_credits'),
        'cast',
        PersonCredit.fromJson,
      );

  /// Like [_results] but reads an arbitrary array [key] (credits use
  /// `cast`/`guest_stars`, not `results`).
  List<T> _list<T>(
    Map<String, dynamic>? json,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final list = json?[key] as List<dynamic>?;
    if (list == null) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }
}
