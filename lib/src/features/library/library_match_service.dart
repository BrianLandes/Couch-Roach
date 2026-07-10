import 'package:injectable/injectable.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../data/db/database.dart';
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
      await _matchRow(item);
    }
  }

  /// Match a single row **now** — used right after a title is registered
  /// mid-session (e.g. an acquired episode) so its poster + canonical name
  /// resolve without waiting for the next startup pass, and its Continue
  /// Watching / library tile updates live off the drift stream. No-op when TMDB
  /// isn't configured, the row is gone, or it's already fully matched (id +
  /// poster). An acquire stamps the id up front but leaves the poster null, so
  /// this still runs to back-fill the art.
  Future<void> matchItem(int id) async {
    if (!const AppConfig().hasTmdbKey) return;
    final item = await _library.findById(id);
    if (item == null) return;
    if (item.tmdbId != null && item.tmdbPosterPath != null) return;
    await _matchRow(item);
  }

  /// Resolve one row against TMDB and cache the id/name/poster. Best effort — a
  /// miss stays null (retried on the next pass); a throw is logged. When the row
  /// already carries a tmdbId (acquire-stamped) we back-fill the name/poster by
  /// id, deterministically, rather than re-searching by title.
  Future<void> _matchRow(LibraryItem item) async {
    try {
      final knownId = item.tmdbId;
      if (knownId != null) {
        if (item.mediaType == 'tv') {
          final d = await _tmdb.tvDetails(knownId);
          if (d != null) {
            await _library.setTmdbMatch(
                id: item.id,
                tmdbId: knownId,
                name: d.name,
                posterPath: d.posterPath);
          }
        } else {
          final d = await _tmdb.movieDetails(knownId);
          if (d != null) {
            await _library.setTmdbMatch(
                id: item.id,
                tmdbId: knownId,
                name: d.title,
                posterPath: d.posterPath);
          }
        }
        return;
      }
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
