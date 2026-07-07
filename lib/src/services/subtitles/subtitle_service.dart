/// Auto English-subtitle fetch seam (HANDOFF §4.6). Implemented in M3.
///
/// Flow: skip if embedded/sidecar EN exists → compute OpenSubtitles moviehash →
/// search (unlimited) → filename fallback → pick best → download
/// (quota-limited) → save `<VideoName>.en.srt`. A quota-aware queue processes a
/// few/day and records attempts in `subtitle_attempts` so it never hammers on
/// first launch.
abstract class SubtitleService {
  /// Ensure an English sidecar exists for [videoPath]. Returns the srt path if
  /// one is present or was downloaded, else null (e.g. deferred by quota).
  Future<String?> ensureEnglish(String videoPath, {int? tmdbId, int? season, int? episode});
}
