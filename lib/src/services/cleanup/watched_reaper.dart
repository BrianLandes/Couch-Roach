/// Auto-cleanup after watch (DECISIONS: auto-cleanup).
///
/// SAFETY MODEL (default): only files flagged `managed = true` (acquired by the
/// app) are ever auto-deleted. Pre-existing scanned library files are never
/// touched automatically unless a folder is explicitly opted in. A file is
/// eligible only when its watch history is `completed` AND `last_watched_at` is
/// older than [gracePeriod]. Deletes the video + its `.en.srt` sidecar.
///
/// Runs on startup and periodically. Not yet wired into app startup — pending
/// Brian's confirmation of the safety model + grace-period length.
class WatchedReaperConfig {
  const WatchedReaperConfig({
    this.enabled = false,
    this.gracePeriod = const Duration(days: 7),
    this.managedOnly = true,
  });

  final bool enabled;
  final Duration gracePeriod;

  /// When true (default), only app-downloaded files are deletable.
  final bool managedOnly;
}

abstract class WatchedReaper {
  /// Scans for eligible files and deletes them. Returns paths removed.
  Future<List<String>> sweep();
}
