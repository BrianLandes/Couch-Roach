/// Auto-cleanup after watch (DECISIONS: auto-cleanup).
///
/// MODEL: the library folders are the app's to manage. Every file in them is
/// hydrated (metadata + subtitles) and then reaped once its watch history is
/// `completed` AND `last_watched_at` is older than [gracePeriod] — deleting the
/// video plus its `.en.srt` sidecar. The one exception is a file the user has
/// pinned `keep = true` (a movie to rewatch), which is never auto-deleted.
///
/// Runs on startup and periodically. Not yet wired into app startup — pending
/// Brian's confirmation of the grace-period length.
class WatchedReaperConfig {
  const WatchedReaperConfig({
    this.enabled = true,
    this.gracePeriod = const Duration(days: 7),
  });

  final bool enabled;
  final Duration gracePeriod;
}

abstract class WatchedReaper {
  /// Scans for eligible files and deletes them. Returns paths removed.
  Future<List<String>> sweep();
}
