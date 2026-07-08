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

  // `Show S01 …` / `Season 1` / `Series 1` — a whole-season pack marker, used
  // when no single-episode marker is present.
  static final _packSeason = RegExp(
    r'\b(?:s|season|series) ?(\d{1,2})\b',
    caseSensitive: false,
  );
  // Release variants shot in / titled for sign language — excluded by default
  // (a different cut than the standard release; CLAUDE settings toggle).
  static final _signLanguage = RegExp(
    r'\b(asl|bsl|sign language)\b',
    caseSensitive: false,
  );

  /// Normalized form for comparing show titles across sources (TMDB name vs a
  /// release/torrent title): lowercased with every non-alphanumeric character
  /// removed, so `House of the Dragon`, `House.of.the.Dragon` and
  /// `house_of_the_dragon` all compare equal. Pure + tested.
  static String normalizeTitle(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// Whether [release] plausibly names the same show as [query] — the release's
  /// normalized text contains the query's (a release carries extra year/quality
  /// tokens the query doesn't). Empty query never matches. Pure + tested.
  static bool titleMatches(String release, String query) {
    final q = normalizeTitle(query);
    return q.isNotEmpty && normalizeTitle(release).contains(q);
  }

  /// The season number of a **whole-season pack** named by [filename], or null
  /// when it names a single episode (has an `SxxExx`/`NxM` marker) or carries no
  /// season marker at all. Lets the resolver treat `Show.S01.1080p` as season 1's
  /// pack while rejecting `Show.S01E03` here (that's a single episode). Pure +
  /// tested.
  static int? seasonPackNumber(String filename) {
    final name = filename.replaceAll(RegExp(r'[._]+'), ' ');
    if (_sxxExx.hasMatch(name) || _altSxE.hasMatch(name)) return null;
    final m = _packSeason.firstMatch(name);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Whether [text] (a release/torrent/subtitle title) is a sign-language cut —
  /// ASL/BSL or "sign language". Pure + tested.
  static bool looksLikeSignLanguage(String text) =>
      _signLanguage.hasMatch(text.replaceAll(RegExp(r'[._]+'), ' '));

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
