import '../../data/tmdb/credits.dart';

/// The person appearing across the most seed titles in [casts] (each entry is one
/// title's cast, best-billed first) — the "actor you keep watching," the seed for
/// the "Because you watch <Actor>" rail. Only the first [topBilledPerTitle] of
/// each cast count (leads, not the long tail), and a person must appear in at
/// least [minTitles] of them to qualify. Ties break by most appearances, then by
/// lower person id (stable). Returns null when nobody recurs enough. Pure.
({int personId, String name})? topRecurringPerson(
  List<List<CastMember>> casts, {
  int topBilledPerTitle = 8,
  int minTitles = 2,
}) {
  final titleCount = <int, int>{};
  final names = <int, String>{};
  for (final cast in casts) {
    final countedInThisTitle = <int>{};
    for (final member in cast.take(topBilledPerTitle)) {
      if (countedInThisTitle.add(member.personId)) {
        titleCount[member.personId] = (titleCount[member.personId] ?? 0) + 1;
        names[member.personId] = member.name;
      }
    }
  }

  int? bestId;
  var bestCount = 0;
  for (final entry in titleCount.entries) {
    if (entry.value < minTitles) continue;
    if (entry.value > bestCount ||
        (entry.value == bestCount && (bestId == null || entry.key < bestId))) {
      bestCount = entry.value;
      bestId = entry.key;
    }
  }
  if (bestId == null) return null;
  return (personId: bestId, name: names[bestId]!);
}
