import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
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
  Future<SeasonDetails?> seasonDetails(int tmdbId, int seasonNumber);
  Future<List<TvShowSummary>> trendingTv();
  Future<List<MovieSummary>> trendingMovies();

  /// Discover movies, optionally within a genre (e.g. 99 = Documentary), sorted
  /// by popularity — the source for the category rails.
  Future<List<MovieSummary>> discoverMovies({int? genreId});

  /// Recommendations for a show — the "similar to what you watched" feed.
  Future<List<TvShowSummary>> recommendedTv(int tmdbId);

  /// Videos (trailers/teasers) for a title — the preview source.
  Future<List<TmdbVideo>> videos({required int tmdbId, required bool isTv});
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
  Future<List<TvShowSummary>> recommendedTv(int tmdbId) async =>
      _results(await _get('/tv/$tmdbId/recommendations'), TvShowSummary.fromJson);

  @override
  Future<List<TmdbVideo>> videos({
    required int tmdbId,
    required bool isTv,
  }) async =>
      _results(
        await _get('/${isTv ? 'tv' : 'movie'}/$tmdbId/videos'),
        TmdbVideo.fromJson,
      );
}
