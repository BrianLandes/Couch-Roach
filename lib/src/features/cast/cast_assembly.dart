import '../../data/tmdb/credits.dart';

/// Order cast for the "Who's in this?" panel: episode **guest stars** first (the
/// hard-to-place faces), then the episode's regular cast, then the show's main
/// cast. Deduped by person — the first (most episode-specific) billing wins.
/// Pure + tested.
List<CastMember> assembleEpisodeCast({
  required List<CastMember> guestStars,
  required List<CastMember> episodeCast,
  required List<CastMember> mainCast,
}) {
  final seen = <int>{};
  final out = <CastMember>[];
  for (final group in [guestStars, episodeCast, mainCast]) {
    for (final c in group) {
      if (seen.add(c.personId)) out.add(c);
    }
  }
  return out;
}

/// The titles to show in an actor's "known for" grid: drop the title we're
/// watching, entries without a poster, and duplicates; rank by popularity and
/// cap at [limit]. Pure + tested.
List<PersonCredit> knownForTitles(
  List<PersonCredit> credits, {
  int? excludeTmdbId,
  int limit = 18,
}) {
  final seen = <int>{};
  final kept = <PersonCredit>[];
  for (final c in credits) {
    if (c.tmdbId == excludeTmdbId) continue;
    if (c.posterPath == null) continue;
    if (c.displayTitle.isEmpty) continue;
    if (!seen.add(c.tmdbId)) continue; // credited twice on one title
    kept.add(c);
  }
  kept.sort((a, b) => b.popularity.compareTo(a.popularity));
  return kept.take(limit).toList(growable: false);
}
