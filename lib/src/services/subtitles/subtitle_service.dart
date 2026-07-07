/// Auto English-subtitle fetch seam (HANDOFF §4.6). Implemented in M3.
///
/// Flow: skip if embedded/sidecar EN exists → compute OpenSubtitles moviehash →
/// search (unlimited) → filename fallback → pick best → download
/// (quota-limited) → save `<VideoName>.en.srt`. A quota-aware queue processes a
/// few/day and records attempts in `subtitle_attempts` so it never hammers on
/// first launch.
abstract class SubtitleService {
  /// Ensure an English sidecar exists for [videoPath]. Returns the srt path if
  /// one is present or was downloaded, else null (e.g. no match, or deferred by
  /// quota). Used on-demand right before playback.
  Future<String?> ensureEnglish(String videoPath, {int? tmdbId, int? season, int? episode});

  /// Work through a bounded batch of library items that still need English
  /// subtitles, respecting the daily download budget and stopping early if the
  /// API reports the quota is spent. Records every outcome in `subtitle_attempts`
  /// so a bulk first-scan is spread over days instead of hammering the quota.
  /// Returns how many subtitles were downloaded this run. [max] overrides the
  /// per-run download cap.
  Future<int> processQueue({int? max});
}
