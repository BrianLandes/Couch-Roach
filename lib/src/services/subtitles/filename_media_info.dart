import 'package:path/path.dart' as p;

/// Title / season / episode / year teased out of a media filename, for the
/// filename fallback when a moviehash search comes up empty (HANDOFF §4.6
/// step 4). Dart regex over the common `Show.S01E02.1080p…` / `Show - 1x02` /
/// `Movie.2019.1080p` shapes — no GuessIt dependency until filenames prove
/// chaotic enough to need it.
class FilenameMediaInfo {
  const FilenameMediaInfo({
    required this.title,
    this.season,
    this.episode,
    this.year,
  });

  /// Cleaned show/movie title (separators normalized, trailing junk trimmed).
  /// May be empty when the name is nothing but a marker (e.g. `S01E02`).
  final String title;
  final int? season;
  final int? episode;
  final int? year;

  bool get hasEpisode => season != null && episode != null;

  // `S01E02`, `s1 e2`, `S01.E02` (dots already normalized to spaces below).
  static final _sxxExx = RegExp(r'[sS](\d{1,2}) ?[eE](\d{1,3})');
  // `1x02`, `12x134` — bounded so it isn't picked out of a longer number.
  static final _altSxE = RegExp(r'\b(\d{1,2})x(\d{1,3})\b');
  // A standalone film year.
  static final _year = RegExp(r'\b(19\d{2}|20\d{2})\b');
  // Release/quality noise that marks the end of a title when no S/E or year is
  // present (`Movie Name 1080p BluRay x264`).
  static final _qualityToken = RegExp(
    r'\b(2160p|1080p|720p|480p|web[ -]?dl|web[ -]?rip|blu[ -]?ray|brrip|bdrip'
    r'|hdrip|dvdrip|hdtv|x ?264|x ?265|h ?264|h ?265|hevc|xvid|aac|ac3|dts'
    r'|proper|repack|remux|extended|unrated)\b',
    caseSensitive: false,
  );

  static FilenameMediaInfo parse(String filename) {
    final name = p
        .basenameWithoutExtension(filename)
        .replaceAll(RegExp(r'[._]+'), ' ')
        .trim();

    int? season;
    int? episode;
    int? year;
    var cut = name.length; // where the title ends / the junk begins

    final se = _sxxExx.firstMatch(name);
    if (se != null) {
      season = int.parse(se.group(1)!);
      episode = int.parse(se.group(2)!);
      cut = se.start;
    } else {
      final alt = _altSxE.firstMatch(name);
      if (alt != null) {
        season = int.parse(alt.group(1)!);
        episode = int.parse(alt.group(2)!);
        cut = alt.start;
      } else {
        final y = _year.firstMatch(name);
        if (y != null) {
          year = int.parse(y.group(1)!);
          cut = y.start;
        }
      }
    }

    var title = name.substring(0, cut);
    // No structural marker found — cut at the first quality token instead.
    if (cut == name.length) {
      final q = _qualityToken.firstMatch(title);
      if (q != null) title = title.substring(0, q.start);
    }
    title = title.replaceAll(RegExp(r'[\s\-]+$'), '').trim();

    return FilenameMediaInfo(
      title: title,
      season: season,
      episode: episode,
      year: year,
    );
  }
}
