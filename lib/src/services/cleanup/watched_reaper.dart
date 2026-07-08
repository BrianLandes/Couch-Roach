import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/settings/settings_service.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/watch_history_repository.dart';

/// Auto-cleanup after watch (DECISIONS: auto-cleanup).
///
/// MODEL: the library folders are the app's to manage. Every file in them is
/// hydrated (metadata + subtitles) and then reaped once its watch history is
/// `completed` AND `last_watched_at` is older than [gracePeriod] — deleting the
/// video plus its `.en.srt` sidecar. The one exception is a file the user has
/// pinned `keep = true` (a movie to rewatch), which is never auto-deleted.
///
/// WATCH RECORDS OUTLIVE THE FILE. Reaping deletes the file + sidecar and flags
/// the library row `missing` — it must NOT delete the row or its `watch_history`.
/// "What I watched / where I left off" has to survive the video being gone, so
/// the row persists as the durable record and only its bytes on disk are freed.
///
/// Runs on startup and periodically (wired in `main()`). Whether it runs and the
/// grace period come from [SettingsService] (user-configurable in Settings).
abstract class WatchedReaper {
  /// Scans for eligible files and deletes them. Returns paths removed.
  Future<List<String>> sweep();
}

@LazySingleton(as: WatchedReaper)
class DriftWatchedReaper implements WatchedReaper {
  DriftWatchedReaper(this._history, this._library, this._log, this._settings);

  final WatchHistoryRepository _history;
  final LibraryRepository _library;
  final ErrorLogService _log;
  final SettingsService _settings;

  /// English sidecars the app itself may have written next to the video. A bare
  /// `.srt` is deliberately left alone — it may be a user's own subtitle.
  static const _sidecarSuffixes = ['.en.srt', '.eng.srt', '.english.srt'];

  @override
  Future<List<String>> sweep() async {
    if (!_settings.cleanupEnabled) return const [];
    final cutoff = DateTime.now().subtract(_settings.cleanupGracePeriod);
    final candidates = await _history.reapable(cutoff);
    if (candidates.isEmpty) return const [];

    final removed = <String>[];
    for (final item in candidates) {
      try {
        _deleteFileAndSidecars(item.filePath);
        // Flag the row missing (keep the row + its watch history) so the delete
        // survives as "watched, then cleaned up".
        await _library.markMissing(item.id);
        removed.add(item.filePath);
        _log.info('reaped "${item.title}" (${item.filePath})',
            source: 'WatchedReaper.sweep');
      } catch (e, st) {
        _log.logError(e, stackTrace: st, source: 'WatchedReaper.sweep');
      }
    }
    if (removed.isNotEmpty) {
      _log.info('reaper freed ${removed.length} watched file(s)',
          source: 'WatchedReaper.sweep');
    }
    return removed;
  }

  void _deleteFileAndSidecars(String videoPath) {
    final video = File(videoPath);
    if (video.existsSync()) video.deleteSync();

    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    for (final suffix in _sidecarSuffixes) {
      final sidecar = File(p.join(dir, '$base$suffix'));
      if (sidecar.existsSync()) sidecar.deleteSync();
    }
  }
}
