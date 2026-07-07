import 'package:injectable/injectable.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../data/repositories/library_repository.dart';
import '../../services/discovery/tmdb_client.dart';

/// Resolves filename-derived library titles to TMDB ids and caches the poster +
/// canonical name on the row (M2 back-fill). Runs after a scan; only touches
/// still-unmatched rows, so it's cheap on re-runs. TMDB search is unlimited, so
/// misses simply stay null and get retried on the next pass.
@LazySingleton()
class LibraryMatchService {
  LibraryMatchService(this._library, this._tmdb, this._log);

  final LibraryRepository _library;
  final DiscoveryClient _tmdb;
  final ErrorLogService _log;

  Future<void> matchUnmatched() async {
    if (!const AppConfig().hasTmdbKey) return;

    for (final item in await _library.unmatched()) {
      try {
        final (title, year) = _splitYear(item.title);
        if (item.mediaType == 'tv') {
          final results = await _tmdb.searchTv(title, year: year);
          if (results.isNotEmpty) {
            final best = results.first;
            await _library.setTmdbMatch(
              id: item.id,
              tmdbId: best.tmdbId,
              name: best.name,
              posterPath: best.posterPath,
            );
          }
        } else {
          final results = await _tmdb.searchMovies(title, year: year);
          if (results.isNotEmpty) {
            final best = results.first;
            await _library.setTmdbMatch(
              id: item.id,
              tmdbId: best.tmdbId,
              name: best.title,
              posterPath: best.posterPath,
            );
          }
        }
      } catch (e, st) {
        _log.logError(e,
            stackTrace: st, source: 'LibraryMatchService.match(${item.title})');
      }
    }
  }

  /// Splits a trailing 4-digit year off a title ("A Movie 2021" → "A Movie",
  /// 2021) to sharpen the TMDB search. Returns the original title if none.
  (String, int?) _splitYear(String title) {
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(title);
    if (match == null) return (title, null);
    final year = int.tryParse(match.group(0)!);
    final cleaned = title
        .replaceRange(match.start, match.end, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (cleaned.isEmpty ? title : cleaned, year);
  }
}
