import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/settings/settings_service.dart';
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
  SubtitleSearcher(this._hasher, this._client, this._log, this._settings);

  final MovieHasher _hasher;
  final SubtitleClient _client;
  final ErrorLogService _log;
  final SettingsService _settings;

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

    // The file on disk is the ground truth for what we're subtitling: when its
    // name carries an explicit SxxExx, trust that over the caller's (possibly
    // stale) season/episode, so a mismatched download doesn't get the wrong
    // episode's subtitles. Falls back to the args when the name has no marker.
    final parsed = FilenameMediaInfo.parse(p.basename(videoPath));
    final s = parsed.hasEpisode ? parsed.season : season;
    final e = parsed.hasEpisode ? parsed.episode : episode;
    if (parsed.hasEpisode &&
        season != null &&
        episode != null &&
        (parsed.season != season || parsed.episode != episode)) {
      _log.warn(
          'subtitle S/E mismatch: file is S${parsed.season}E${parsed.episode} '
          'but the library says S${season}E$episode — using the file',
          source: 'SubtitleSearcher.findBest');
    }
    final exclude = _settings.excludeSignLanguage;

    _log.info(
        'searching English subtitles for "${p.basename(videoPath)}" '
        '(tmdbId=$tmdbId, title=$title, S=$s E=$e)',
        source: 'SubtitleSearcher.findBest');

    // 1. Hash match — the most reliable signal (exact file → exact sub).
    try {
      final hash = await _hasher.hash(videoPath);
      results = await _client.search(moviehash: hash, language: 'en');
      _log.info('moviehash search ($hash) → ${results.length} result(s)',
          source: 'SubtitleSearcher.findBest');
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'SubtitleSearcher.hash');
    }

    // 2. Fallback: tmdb_id (if we have it) else a filename query, scoped by
    //    the effective season/episode.
    if (results.isEmpty) {
      if (tmdbId != null) {
        results = await _client.search(
          tmdbId: tmdbId,
          season: s,
          episode: e,
          language: 'en',
        );
        _log.info('fallback tmdb_id=$tmdbId search → ${results.length} result(s)',
            source: 'SubtitleSearcher.findBest');
      } else {
        final query = title ?? (parsed.title.isEmpty ? null : parsed.title);
        if (query != null) {
          results = await _client.search(
            query: query,
            season: s,
            episode: e,
            language: 'en',
          );
          _log.info(
              'fallback query="$query" search → ${results.length} result(s)',
              source: 'SubtitleSearcher.findBest');
        } else {
          _log.warn('no fallback search possible: no tmdbId, title, or '
              'parseable filename title', source: 'SubtitleSearcher.findBest');
        }
      }
    }

    final best = pickBest(
      results,
      preferHearingImpaired: preferHearingImpaired,
      excludeSignLanguage: exclude,
      season: s,
      episode: e,
    );
    if (best == null) {
      _log.info('no usable subtitle after ranking ${results.length} hit(s)',
          source: 'SubtitleSearcher.findBest');
    } else {
      _log.info(
          'picked subtitle fileId=${best.fileId} '
          '(release="${best.attributes.release}", '
          'downloads=${best.attributes.downloadCount}, '
          'trusted=${best.attributes.fromTrusted}, '
          'hi=${best.attributes.hearingImpaired})',
          source: 'SubtitleSearcher.findBest');
    }
    return best;
  }

  /// Rank subtitle hits and return the best downloadable one (HANDOFF §4.6
  /// step 5). Results without a downloadable file id are ignored. A sub whose
  /// `release` names a **different** [season]/[episode] than requested is
  /// dropped (defense against a wrong-episode match), as are sign-language
  /// releases when [excludeSignLanguage]. Pure + static so the ranking is
  /// unit-testable in isolation.
  static SubtitleResult? pickBest(
    List<SubtitleResult> results, {
    bool preferHearingImpaired = false,
    bool excludeSignLanguage = true,
    int? season,
    int? episode,
  }) {
    final candidates = results.where((r) {
      if (r.fileId == null) return false;
      final release = r.attributes.release;
      if (release == null) return true;
      if (excludeSignLanguage &&
          FilenameMediaInfo.looksLikeSignLanguage(release)) {
        return false;
      }
      if (season != null && episode != null) {
        final parsed = FilenameMediaInfo.parse(release);
        if (parsed.hasEpisode &&
            (parsed.season != season || parsed.episode != episode)) {
          return false;
        }
      }
      return true;
    }).toList();
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
