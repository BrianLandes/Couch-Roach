import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../data/opensubtitles/download_response.dart';
import '../../data/opensubtitles/subtitle_result.dart';

/// Thin client over the OpenSubtitles.com REST API (HANDOFF §4.6). Searching is
/// unlimited; downloading is quota-limited (the caller manages the quota).
/// Requires the `Api-Key` header and a descriptive `User-Agent` (from
/// [AppConfig]) or requests are rejected. Failures are logged and degrade to
/// empty/null.
abstract class SubtitleClient {
  /// Search for subtitles. `moviehash` is preferred; `query` + season/episode
  /// (or `tmdbId`) is the fallback. Returns [] on failure.
  Future<List<SubtitleResult>> search({
    String? moviehash,
    String? query,
    int? tmdbId,
    int? season,
    int? episode,
    String language = 'en',
  });

  /// Request a temporary download link for a subtitle file (quota-limited).
  Future<DownloadResponse?> requestDownload(int fileId);
}

@LazySingleton(as: SubtitleClient)
class OpenSubtitlesClient implements SubtitleClient {
  OpenSubtitlesClient(this._http, this._log);

  final http.Client _http;
  final ErrorLogService _log;

  static const _base = 'https://api.opensubtitles.com/api/v1';

  Map<String, String> get _headers => {
        'Api-Key': AppConfig.openSubtitlesApiKey,
        'User-Agent': AppConfig.openSubtitlesUserAgent,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  @override
  Future<List<SubtitleResult>> search({
    String? moviehash,
    String? query,
    int? tmdbId,
    int? season,
    int? episode,
    String language = 'en',
  }) async {
    final uri = Uri.parse('$_base/subtitles').replace(queryParameters: {
      'languages': language,
      if (moviehash != null) 'moviehash': moviehash,
      if (query != null) 'query': query,
      if (tmdbId != null) 'tmdb_id': '$tmdbId',
      if (season != null) 'season_number': '$season',
      if (episode != null) 'episode_number': '$episode',
    });

    try {
      final res = await _http.get(uri, headers: _headers);
      if (res.statusCode != 200) {
        _log.warn('OpenSubtitles ${res.statusCode} on search',
            source: 'OpenSubtitlesClient');
        return const [];
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return SubtitleSearchResponse.fromJson(json).data;
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'OpenSubtitlesClient.search');
      return const [];
    }
  }

  @override
  Future<DownloadResponse?> requestDownload(int fileId) async {
    try {
      final res = await _http.post(
        Uri.parse('$_base/download'),
        headers: _headers,
        body: jsonEncode({'file_id': fileId}),
      );
      if (res.statusCode != 200) {
        _log.warn('OpenSubtitles ${res.statusCode} on download',
            source: 'OpenSubtitlesClient');
        return null;
      }
      return DownloadResponse.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'OpenSubtitlesClient.download');
      return null;
    }
  }
}
