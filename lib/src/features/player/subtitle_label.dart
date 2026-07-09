/// Build the display label for a subtitle track in the player's right-click
/// picker from its raw libmpv fields. Embedded tracks and downloaded sidecars
/// can carry a verbose title (a full release string, an OpenSubtitles filename),
/// so the title is capped with an ellipsis to keep the menu from blowing out to
/// the width of the screen. Pure + tested — the widget passes the SubtitleTrack
/// fields straight through.
String subtitleTrackLabel({
  required String id,
  String? title,
  String? language,
  int maxTitle = 36,
}) {
  if (id == 'no') return 'Off';
  if (id == 'auto') return 'Auto';
  final t = title?.trim();
  final lang = language?.trim();
  if (t != null && t.isNotEmpty) {
    final short = truncateSubtitleTitle(t, maxTitle);
    return (lang != null && lang.isNotEmpty) ? '$short ($lang)' : short;
  }
  if (lang != null && lang.isNotEmpty) return lang;
  return 'Track $id';
}

/// Cap [title] to [max] characters, appending an ellipsis when it's cut. Trims a
/// trailing space before the ellipsis so it reads cleanly. Pure.
String truncateSubtitleTitle(String title, [int max = 36]) {
  final t = title.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max - 1).trimRight()}…';
}
