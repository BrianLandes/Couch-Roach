import 'package:path/path.dart' as p;

import '../../services/subtitles/filename_media_info.dart';

/// Path-aware parsing for the library scanner + matcher. Unlike a filename-only
/// parse, this reads the **folder structure** too — the near-universal
/// `Show Name/Season 01/episode.mkv` layout — so a messy filename in a clean
/// folder still resolves to the right show, season, and episode. All pure +
/// heavily tested.

/// A parsed library file.
class ParsedMedia {
  const ParsedMedia({
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
  });
  final String title;

  /// 'tv' or 'movie'.
  final String mediaType;
  final int? season;
  final int? episode;
}

// A folder named for a season: "Season 1", "Season 01", "Series 2", "S01".
final _seasonFolder = RegExp(
  r'^(?:season|series)\s*0*(\d{1,2})$|^s0*(\d{1,2})$',
  caseSensitive: false,
);

// Episode-number cues used ONLY once we already know a file is TV (it sits in a
// season folder), so these looser patterns can't misfire on a movie.
final _epWord = RegExp(r'(?:episode|ep)[\s._-]*(\d{1,3})', caseSensitive: false);
final _epE = RegExp(r'(?:^|[^a-z0-9])e(\d{1,3})(?:[^a-z0-9]|$)', caseSensitive: false);
final _epLead = RegExp(r'^(\d{1,3})(?:[\s._-]|$)');
final _epDash = RegExp(r'[-\s._](\d{1,3})(?:[-\s._]|$)');

String _spaced(String s) => s.replaceAll(RegExp(r'[._]+'), ' ').trim();

int? _seasonFolderNumber(String folder) {
  final m = _seasonFolder.firstMatch(_spaced(folder));
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? m.group(2) ?? '');
}

/// True when [folder] is a "Season NN" / "Series NN" / "SNN" directory.
bool isSeasonFolder(String folder) => _seasonFolderNumber(folder) != null;

int? _episodeNumberFrom(String name) {
  final n = _spaced(name);
  for (final re in [_epWord, _epE]) {
    final m = re.firstMatch(n);
    if (m != null) return int.tryParse(m.group(1)!);
  }
  final lead = _epLead.firstMatch(n);
  if (lead != null) return int.tryParse(lead.group(1)!);
  final dash = _epDash.firstMatch(n);
  if (dash != null) return int.tryParse(dash.group(1)!);
  return null;
}

/// Normalize a show/movie name pulled from a folder: separators to spaces, and a
/// trailing year (`Show 2008` or `Show (2008)`) trimmed off.
String cleanShowName(String raw) {
  var s = _spaced(raw);
  s = s.replaceAll(RegExp(r'\s*\((?:19|20)\d{2}\)\s*$'), '');
  s = s.replaceAll(RegExp(r'\s+(?:19|20)\d{2}$'), '');
  return s.trim();
}

/// The show folder for [filePath] — the parent, or the grandparent when the file
/// sits in a "Season NN" folder. Meaningful for TV; for a flat movie folder it
/// returns the containing folder (a weak candidate the matcher's validator
/// filters out if it doesn't actually match).
String showFolderName(String filePath) =>
    cleanShowName(p.basename(showFolderPath(filePath)));

/// The full path of [filePath]'s show folder — its parent, or the grandparent
/// when it sits in a "Season NN" folder. This is the directory that identifies
/// "the folder these files live in together"; [showFolderName] is its basename.
String showFolderPath(String filePath) {
  final dir = p.dirname(filePath);
  if (isSeasonFolder(p.basename(dir))) return p.dirname(dir);
  return dir;
}

/// True when [filePath] sits loose directly in a library root (its show folder
/// *is* one of [rootPaths]) — so it has no real show folder to group by, and a
/// flat pile of files in a root shouldn't be folded into one bogus group.
bool isLooseInRoot(String filePath, Set<String> rootPaths) {
  final folder = showFolderPath(filePath);
  return rootPaths.any((r) => p.equals(r, folder));
}

/// Parse a file's full [filePath] into a [ParsedMedia]. Precedence:
/// 1. an `SxxExx` / `NxM` marker in the filename → TV (season/episode from it);
/// 2. a `Season NN` parent folder → TV (season from the folder, episode from the
///    filename, show name from the grandparent);
/// 3. otherwise a movie, with the quality/group-stripped filename as the title.
ParsedMedia parseLibraryPath(String filePath) {
  final fileName = p.basenameWithoutExtension(filePath);
  final parent = p.basename(p.dirname(filePath));
  final fm = FilenameMediaInfo.parse(fileName);

  if (fm.hasEpisode) {
    // The filename carries the marker; its show name is usually right, but fall
    // back to the folder when the filename is just "S01E02".
    final title = fm.title.trim().length >= 2 ? fm.title : showFolderName(filePath);
    return ParsedMedia(
        title: title, mediaType: 'tv', season: fm.season, episode: fm.episode);
  }

  final seasonNum = _seasonFolderNumber(parent);
  if (seasonNum != null) {
    final show = cleanShowName(p.basename(p.dirname(p.dirname(filePath))));
    return ParsedMedia(
      title: show.isNotEmpty ? show : cleanShowName(fileName),
      mediaType: 'tv',
      season: seasonNum,
      episode: _episodeNumberFrom(fileName),
    );
  }

  return ParsedMedia(
    title: fm.title.isNotEmpty ? fm.title : cleanShowName(fileName),
    mediaType: 'movie',
  );
}

/// A TMDB search query plus the release year that was stripped off it, when the
/// source named one. The year sharpens the search (TMDB's `year=` filter), which
/// is the whole reason it's carried separately rather than discarded — a bare
/// "Dune" matches three films, "Dune" + 2021 matches one.
typedef SearchCandidate = ({String query, int? year});

/// [cleanShowName], plus the four-digit year it removed.
///
/// The query is byte-for-byte what [cleanShowName] returns, so nothing about the
/// search text changes — the year is recovered from the tail that was trimmed,
/// which keeps the two permanently in step.
(String, int?) splitShowNameYear(String raw) {
  final cleaned = cleanShowName(raw);
  final spaced = _spaced(raw);
  final tail = spaced.startsWith(cleaned) ? spaced.substring(cleaned.length) : '';
  final match = RegExp(r'(?:19|20)\d{2}').firstMatch(tail);
  return (cleaned, match == null ? null : int.tryParse(match.group(0)!));
}

/// Ordered TMDB search queries for [filePath], best-first: the parsed/stored
/// [storedTitle], then the show/containing folder. Deduped by query; empties
/// dropped.
///
/// The folder candidate exists to rescue a file whose *name* is a useless
/// release string but whose folder names the show ("/tv/The Office/xyz.mkv").
/// That only holds when the folder is the title's own — a file sitting loose
/// directly in a library root has no show folder, just the root's name
/// ("/movies/Inception.mkv" would search for "movies"), so pass [rootPaths] and
/// the folder candidate is skipped for those. Omitting [rootPaths] keeps the old
/// behaviour, which is only safe when the caller knows the file is foldered.
List<SearchCandidate> tmdbSearchCandidates(
  String filePath,
  String storedTitle, {
  Set<String> rootPaths = const {},
}) {
  final out = <SearchCandidate>[];
  void add(String raw) {
    final (query, year) = splitShowNameYear(raw);
    if (query.isEmpty) return;
    // Dedupe on the query alone: the same title from the filename and its folder
    // is one search, and we keep the first (best-ranked) year seen for it.
    if (out.any((c) => c.query == query)) return;
    out.add((query: query, year: year));
  }

  add(storedTitle);
  if (!isLooseInRoot(filePath, rootPaths)) {
    // The folder was already year-stripped by showFolderName, so read the year
    // off the raw basename instead of the cleaned one.
    add(p.basename(showFolderPath(filePath)));
  }
  return out;
}

/// A stable key that groups unmatched episodes of the same show — the show
/// folder (normalized), else the parsed [fallbackTitle].
String unmatchedShowKey(String filePath, String fallbackTitle) {
  final folder = showFolderName(filePath);
  return FilenameMediaInfo.normalizeTitle(folder.isNotEmpty ? folder : fallbackTitle);
}

/// How many normalized characters the *contained* side of a containment match
/// must have before it counts as evidence.
///
/// Below this, containment is noise rather than a match: "it" ⊂ "titanic",
/// "saw" ⊂ "jigsaw", and a single letter is inside almost every title. Short
/// titles that are genuinely real ("M", "Up", "It") are unaffected — they're
/// caught by the exact-match pass above, which has no length rule.
const int kMinContainmentChars = 4;

/// The index of the TMDB result whose name best matches [query], or null when
/// none is a confident match.
///
/// An exact normalized match wins outright. Failing that, containment either way
/// ("Office" ⊂ "The Office", "The Office US" ⊃ "Office"), earliest (most
/// TMDB-relevant) first — but only when the **contained** side is at least
/// [kMinContainmentChars] long, so a stray short query can't sweep up an
/// unrelated title. Returning null — rather than blindly taking result 0 — is
/// what stops a noisy query grabbing the wrong title. Pure + tested.
int? pickBestMatchIndex(List<String> resultNames, String query) {
  final q = FilenameMediaInfo.normalizeTitle(query);
  if (q.isEmpty) return null;
  final norm = resultNames.map(FilenameMediaInfo.normalizeTitle).toList();
  for (var i = 0; i < norm.length; i++) {
    if (norm[i] == q) return i;
  }
  for (var i = 0; i < norm.length; i++) {
    final n = norm[i];
    if (n.isEmpty) continue;
    // Guard whichever string is the contained one — a short *result* inside a
    // long query is as weak as a short query inside a long result.
    if (n.contains(q) && q.length >= kMinContainmentChars) return i;
    if (q.contains(n) && n.length >= kMinContainmentChars) return i;
  }
  return null;
}
