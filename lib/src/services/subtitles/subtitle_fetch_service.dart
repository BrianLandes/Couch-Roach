import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../data/db/database.dart';
import '../../data/opensubtitles/subtitle_result.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/subtitle_attempts_repository.dart';
import 'opensubtitles_client.dart';
import 'subtitle_searcher.dart';
import 'subtitle_service.dart';
import 'subtitle_skip_check.dart';

/// The OpenSubtitles-backed [SubtitleService]: for a given video, reuse an
/// existing English track, else search (moviehash → filename/tmdb) and download
/// the best match to `<VideoName>.en.srt` (HANDOFF §4.6 step 6). [processQueue]
/// drives this across the library a few at a time, respecting the daily
/// download quota.
@LazySingleton(as: SubtitleService)
class OpenSubtitlesSubtitleService implements SubtitleService {
  OpenSubtitlesSubtitleService(
    this._skip,
    this._searcher,
    this._client,
    this._attempts,
    this._library,
    this._http,
    this._log,
  );

  final SubtitleSkipCheck _skip;
  final SubtitleSearcher _searcher;
  final SubtitleClient _client;
  final SubtitleAttemptsRepository _attempts;
  final LibraryRepository _library;
  final http.Client _http;
  final ErrorLogService _log;

  /// Downloads to spend per queue run / per day. Kept well under the free-tier
  /// ~20/day so a big library is subtitled gradually over several launches.
  static const _dailyDownloadBudget = 12;

  @override
  Future<int> processQueue({int? max}) async {
    final spent = await _attempts.downloadsToday();
    final budget = ((max ?? _dailyDownloadBudget) - spent)
        .clamp(0, _dailyDownloadBudget);
    if (budget <= 0) return 0;

    // Pull more candidates than the budget: items that already have English or
    // have no match don't spend a download, so we keep going until we've either
    // spent the budget, run out of candidates, or hit the quota wall.
    final items = await _attempts.itemsNeedingSubtitles(limit: budget * 4);

    var downloaded = 0;
    for (final item in items) {
      if (downloaded >= budget) break;
      final outcome = await _ensure(item, item.filePath);
      if (outcome.status == SubtitleAttemptStatus.found) downloaded++;
      if (outcome.status == SubtitleAttemptStatus.quota) break;
    }
    return downloaded;
  }

  @override
  Future<String?> ensureEnglish(
    String videoPath, {
    int? tmdbId,
    int? season,
    int? episode,
  }) async {
    final item = await _library.findByPath(videoPath);
    final outcome = await _ensure(
      item,
      videoPath,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    return outcome.path;
  }

  /// Core per-file flow shared by [ensureEnglish] and [processQueue]. Records an
  /// attempt when [item] is known. Explicit [tmdbId]/[season]/[episode] override
  /// the row's values (else they fall back to the row, then the filename).
  Future<({String? path, SubtitleAttemptStatus status})> _ensure(
    LibraryItem? item,
    String videoPath, {
    int? tmdbId,
    int? season,
    int? episode,
  }) async {
    try {
      // Already have English (embedded or a sidecar)? Nothing to fetch.
      if (await _skip.hasEnglish(videoPath)) {
        await _record(item, SubtitleAttemptStatus.present);
        return (
          path: SubtitleSkipCheck.englishSidecarPath(videoPath),
          status: SubtitleAttemptStatus.present,
        );
      }

      final result = await _searcher.findBest(
        videoPath,
        tmdbId: tmdbId ?? item?.tmdbId,
        season: season ?? item?.season,
        episode: episode ?? item?.episode,
        title: item?.tmdbName,
      );
      if (result == null) {
        await _record(item, SubtitleAttemptStatus.notFound);
        return (path: null, status: SubtitleAttemptStatus.notFound);
      }

      _log.info('requesting download for subtitle fileId=${result.fileId}',
          source: 'SubtitleService.ensure');
      final saved = await _downloadAndSave(result, videoPath);
      final status = saved != null
          ? SubtitleAttemptStatus.found
          : SubtitleAttemptStatus.quota; // download refused → treat as quota
      if (saved != null) {
        _log.info('downloaded English subtitle → $saved',
            source: 'SubtitleService.ensure');
      } else {
        _log.warn('subtitle download refused (quota or link failure)',
            source: 'SubtitleService.ensure');
      }
      await _record(item, status);
      return (path: saved, status: status);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'SubtitleService.ensure');
      await _record(item, SubtitleAttemptStatus.error);
      return (path: null, status: SubtitleAttemptStatus.error);
    }
  }

  /// Request a temp link and write the srt next to the video. Returns the saved
  /// path, or null when the download was refused (quota) or the link failed.
  Future<String?> _downloadAndSave(
    SubtitleResult result,
    String videoPath,
  ) async {
    final fileId = result.fileId;
    if (fileId == null) return null;

    final dl = await _client.requestDownload(fileId);
    if (dl == null) return null; // quota/error — client already logged it

    final res = await _http.get(Uri.parse(dl.link));
    if (res.statusCode != 200) {
      _log.warn('subtitle link HTTP ${res.statusCode}',
          source: 'SubtitleService.download');
      return null;
    }

    final target = _sidecarPath(videoPath);
    await File(target).writeAsBytes(res.bodyBytes);
    return target;
  }

  Future<void> _record(LibraryItem? item, SubtitleAttemptStatus status) async {
    if (item != null) await _attempts.record(item.id, status);
  }

  String _sidecarPath(String videoPath) {
    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    return p.join(dir, '$base.en.srt');
  }
}
