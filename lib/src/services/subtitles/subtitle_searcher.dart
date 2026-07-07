import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../data/opensubtitles/subtitle_result.dart';
import 'filename_media_info.dart';
import 'movie_hasher.dart';
import 'opensubtitles_client.dart';

/// Finds the best English subtitle for a video (HANDOFF §4.6 steps 3–5):
/// moviehash search first, then a filename/tmdb_id + season/episode fallback,
/// then rank the hits and return the single best one. It stops short of
/// downloading — the quota-aware download/save is the next step in the flow.
@LazySingleton()
class SubtitleSearcher {
  SubtitleSearcher(this._hasher, this._client, this._log);

  final MovieHasher _hasher;
  final SubtitleClient _client;
  final ErrorLogService _log;

  /// Search for [videoPath]'s best English subtitle. Supplies [tmdbId] /
  /// [season] / [episode] / [title] when the caller already knows them (a
  /// matched library row); anything missing is teased out of the filename.
  /// Returns null when nothing usable is found.
  Future<SubtitleResult?> findBest(
    String videoPath, {
    int? tmdbId,
    int? season,
    int? episode,
    String? title,
    bool preferHearingImpaired = false,
  }) async {
    var results = const <SubtitleResult>[];

    // 1. Hash match — the most reliable signal (exact file → exact sub).
    try {
      final hash = await _hasher.hash(videoPath);
      results = await _client.search(moviehash: hash, language: 'en');
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'SubtitleSearcher.hash');
    }

    // 2. Fallback: tmdb_id (if we have it) else a filename query, scoped by
    //    season/episode from the args or parsed out of the name.
    if (results.isEmpty) {
      final parsed = FilenameMediaInfo.parse(p.basename(videoPath));
      final s = season ?? parsed.season;
      final e = episode ?? parsed.episode;
      if (tmdbId != null) {
        results = await _client.search(
          tmdbId: tmdbId,
          season: s,
          episode: e,
          language: 'en',
        );
      } else {
        final query = title ?? (parsed.title.isEmpty ? null : parsed.title);
        if (query != null) {
          results = await _client.search(
            query: query,
            season: s,
            episode: e,
            language: 'en',
          );
        }
      }
    }

    return pickBest(results, preferHearingImpaired: preferHearingImpaired);
  }

  /// Rank subtitle hits and return the best downloadable one (HANDOFF §4.6
  /// step 5). Results without a downloadable file id are ignored. Pure + static
  /// so the ranking is unit-testable in isolation.
  static SubtitleResult? pickBest(
    List<SubtitleResult> results, {
    bool preferHearingImpaired = false,
  }) {
    final candidates = results.where((r) => r.fileId != null).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => _score(b.attributes, preferHearingImpaired)
        .compareTo(_score(a.attributes, preferHearingImpaired)));
    return candidates.first;
  }

  // Download count is the base signal (popular subs are usually well-synced and
  // correctly matched); a trusted uploader earns a fixed boost; a
  // hearing-impaired mismatch with the preference is a gentle nudge, never a
  // hard exclusion — an HI sub still beats no sub, or an obscure alternative.
  static const _trustedBoost = 500.0;
  static const _hiMismatchPenalty = 100.0;

  static double _score(SubtitleAttributes a, bool preferHearingImpaired) {
    var score = a.downloadCount.toDouble();
    if (a.fromTrusted) score += _trustedBoost;
    if (a.hearingImpaired != preferHearingImpaired) score -= _hiMismatchPenalty;
    return score;
  }
}
