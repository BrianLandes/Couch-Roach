import '../../data/tmdb/credits.dart';
import '../../data/tmdb/person_summary.dart';
import 'discover_tile.dart';

/// The person [results] actually name, or null when none of them is a
/// convincing match for [query].
///
/// TMDB's `/search/person` is fuzzy and always returns *something* — searching
/// "batman" yields people with that word somewhere in their credits. Attaching
/// a filmography to a title search on that basis would be worse than useless,
/// so a result only counts when the query matches the person's **name**: the
/// whole name, or one of its parts (so "Tarantino" and "quentin tarantino"
/// both land, while "batman" doesn't).
///
/// Among qualifying matches the most popular wins, which is what makes a bare
/// surname resolve to the person someone actually meant. Pure + tested.
PersonSummary? bestPersonMatch(List<PersonSummary> results, String query) {
  final q = _normalize(query);
  if (q.isEmpty) return null;

  PersonSummary? best;
  for (final p in results) {
    final name = _normalize(p.name);
    if (name.isEmpty) continue;
    final parts = name.split(' ').where((w) => w.isNotEmpty);
    final matches = name == q || parts.contains(q);
    if (!matches) continue;
    if (best == null || p.popularity > best.popularity) best = p;
  }
  return best;
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();

/// Turn a person's credits into poster tiles: most popular first, one tile per
/// title, skipping anything unplayable.
///
/// [exclude] drops ids the caller already showed (the title matches above the
/// section, so the same film isn't listed twice on one screen). Pure + tested.
List<DiscoverTile> tilesFromCredits(
  List<PersonCredit> credits, {
  Set<int> exclude = const {},
  int limit = 40,
}) {
  final sorted = [...credits]
    ..sort((a, b) => b.popularity.compareTo(a.popularity));
  final tiles = <DiscoverTile>[];
  final seen = <int>{};
  for (final c in sorted) {
    // TMDB's combined credits can carry other media types; only these two have
    // a detail page to open.
    if (c.mediaType != 'tv' && c.mediaType != 'movie') continue;
    if (exclude.contains(c.tmdbId)) continue;
    if (c.displayTitle.isEmpty || !seen.add(c.tmdbId)) continue;
    tiles.add(DiscoverTile(
      tmdbId: c.tmdbId,
      title: c.displayTitle,
      mediaType: c.mediaType,
      posterPath: c.posterPath,
      year: int.tryParse(c.year ?? ''),
    ));
    if (tiles.length >= limit) break;
  }
  return tiles;
}
