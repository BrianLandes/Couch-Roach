// Predicates about *what* the player is playing, split out of the widget so
// they're testable without a libmpv player. Pure.

/// Whether [path] is a network URL (a YouTube trailer resolved through yt-dlp)
/// rather than a local library file.
///
/// This gates real behaviour: the ytdl_hook wiring, verbose mpv logging, and
/// skipping the watch-history/next-episode machinery that only makes sense for
/// an owned file. A bare Windows path (`C:\...`) parses as a URI with scheme
/// `c`, so the check is scheme-allowlisted rather than "has a scheme".
bool isNetworkUrl(String path) {
  final uri = Uri.tryParse(path);
  return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
}

/// Whether a libmpv subtitle track id refers to a **sidecar file** we loaded
/// (an `.srt`/`.vtt` next to the video) rather than a track embedded in the
/// container.
///
/// libmpv reports an external subtitle's id as its path, so a separator or a
/// subtitle extension is the tell. The distinction matters on resume: a saved
/// sidecar choice is restored by letting the auto-English fetch reload the same
/// file, while a saved *embedded* choice (or "off") has to suppress that fetch
/// so it doesn't get overridden.
bool isSidecarSubtitleId(String id) =>
    id.endsWith('.srt') ||
    id.endsWith('.vtt') ||
    id.contains('/') ||
    id.contains(r'\');

/// Whether a saved [preferredSubtitleTrackId] must suppress the automatic
/// English-subtitle fetch, so restoring the user's manual choice wins.
///
/// True for "off" and for any embedded track; false for a sidecar (the auto
/// path reloads the same file anyway) and when nothing was saved.
bool suppressesAutoSubtitles(String? preferredSubtitleTrackId) {
  final id = preferredSubtitleTrackId;
  if (id == null) return false;
  return id == 'no' || !isSidecarSubtitleId(id);
}
