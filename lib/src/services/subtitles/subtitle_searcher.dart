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

  /// Below this many unique id/hash hits we also run the (broader, noisier)
  /// query search to widen the pool. Above it the id search already gave us
  /// plenty, so we skip the extra call.
  static const _widenThreshold = 5;

  /// Dedup search hits that overlap across strategies (hash + id + query often
  /// return the same files), keyed by downloadable file id, else the result id.
  static List<SubtitleResult> _unique(List<SubtitleResult> hits) {
    final seen = <String>{};
    final out = <SubtitleResult>[];
    for (final r in hits) {
      final key = r.fileId?.toString() ?? 'id:${r.id}';
      if (seen.add(key)) out.add(r);
    }
    return out;
  }

  /// How many unique hits would actually survive [pickBest]'s filters for this
  /// request. Drives the widening decision: a search that returns rows which
  /// all get rejected (wrong episode, no downloadable file) counts as zero, so
  /// it can't suppress the broader searches.
  static int _usableCount(
    List<SubtitleResult> hits,
    bool excludeSignLanguage,
    int? season,
    int? episode,
  ) =>
      _unique(hits)
          .where((r) =>
              rejectReason(
                r,
                excludeSignLanguage: excludeSignLanguage,
                season: season,
                episode: episode,
              ) ==
              null)
          .length;

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
    final isEpisode = s != null && e != null;

    _log.info(
        'searching English subtitles for "${p.basename(videoPath)}" '
        '(tmdbId=$tmdbId, title=$title, S=$s E=$e)',
        source: 'SubtitleSearcher.findBest');

    // Accumulate hits across strategies rather than stopping at the first that
    // returns anything: a single narrow query can miss (or return the wrong
    // episode) while a broader one lands. Dedup + rank happens at the end, so
    // more raw hits only ever *widens* the pool pickBest chooses from.
    final hits = <SubtitleResult>[];

    // 1. Hash match — the most reliable signal (exact file → exact sub).
    try {
      final hash = await _hasher.hash(videoPath);
      final r = await _client.search(moviehash: hash, language: 'en');
      _log.info('moviehash search ($hash) → ${r.length} result(s)',
          source: 'SubtitleSearcher.findBest');
      hits.addAll(r);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'SubtitleSearcher.hash');
    }

    // A *usable* moviehash hit is an exact file→subtitle match — trust it and
    // don't dilute the ranking with looser id/query hits. But a hash hit that
    // pickBest would reject (wrong episode, no downloadable file) must NOT
    // suppress the broader searches — that lone rejected hit is exactly what
    // left this file subtitle-less before.
    if (_usableCount(hits, exclude, s, e) == 0) {
      // 2. Id-based. For a TV episode the show id is a *parent_tmdb_id* next to
      //    season/episode; for a movie it's a plain tmdb_id. Getting this shape
      //    right is what turns "1 wrong hit" into the full episode list.
      if (tmdbId != null) {
        final r = await _client.search(
          tmdbId: isEpisode ? null : tmdbId,
          parentTmdbId: isEpisode ? tmdbId : null,
          season: s,
          episode: e,
          language: 'en',
        );
        final param = isEpisode ? 'parent_tmdb_id' : 'tmdb_id';
        _log.info('$param=$tmdbId search → ${r.length} result(s)',
            source: 'SubtitleSearcher.findBest');
        hits.addAll(r);
      }

      // 3. Query fallback — widen when the id search was sparse (or we have no
      //    id at all). The TMDB name is the cleanest query; the filename title
      //    is the last resort.
      if (_usableCount(hits, exclude, s, e) < _widenThreshold) {
        final query = title ?? (parsed.title.isEmpty ? null : parsed.title);
        if (query != null) {
          final r = await _client.search(
            query: query,
            season: s,
            episode: e,
            language: 'en',
          );
          _log.info('query="$query" search → ${r.length} result(s)',
              source: 'SubtitleSearcher.findBest');
          hits.addAll(r);
        } else if (hits.isEmpty) {
          _log.warn('no query search possible: no tmdbId, title, or parseable '
              'filename title', source: 'SubtitleSearcher.findBest');
        }
      }
    }

    final results = _unique(hits);
    if (results.length != hits.length) {
      _log.info('merged ${hits.length} raw hit(s) → ${results.length} unique',
          source: 'SubtitleSearcher.findBest');
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
      // Explain why each hit was dropped — there's no score threshold, only the
      // hard filters in [pickBest], so this pins down exactly which one fired.
      for (final r in results) {
        _log.info(
            '  rejected: ${rejectReason(r, excludeSignLanguage: exclude, season: s, episode: e)}',
            source: 'SubtitleSearcher.findBest');
      }
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
    final candidates = results
        .where((r) =>
            rejectReason(
              r,
              excludeSignLanguage: excludeSignLanguage,
              season: season,
              episode: episode,
            ) ==
            null)
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => _score(b.attributes, preferHearingImpaired)
        .compareTo(_score(a.attributes, preferHearingImpaired)));
    return candidates.first;
  }

  /// Human-readable reason [r] can't be used, or null when it's a usable
  /// candidate. The single source of truth for [pickBest]'s filter — reused for
  /// diagnostic logging so "why was this hit dropped?" can never drift from the
  /// actual selection logic. Note there is **no** download-count / score
  /// threshold: ranking only orders the survivors, it never excludes.
  static String? rejectReason(
    SubtitleResult r, {
    bool excludeSignLanguage = true,
    int? season,
    int? episode,
  }) {
    if (r.fileId == null) {
      return 'fileId=null — hit has no downloadable file (empty files[])';
    }
    final release = r.attributes.release;
    if (release == null) return null;
    if (excludeSignLanguage &&
        FilenameMediaInfo.looksLikeSignLanguage(release)) {
      return 'fileId=${r.fileId} looks like sign-language ("$release")';
    }
    if (season != null && episode != null) {
      final parsed = FilenameMediaInfo.parse(release);
      if (parsed.hasEpisode &&
          (parsed.season != season || parsed.episode != episode)) {
        return 'fileId=${r.fileId} release is S${parsed.season}E${parsed.episode}, '
            'wanted S${season}E$episode ("$release")';
      }
    }
    return null;
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
