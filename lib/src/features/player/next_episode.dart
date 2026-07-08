/// The next episode's (season, episode) after ([season], [episode]), given each
/// season's episode count ([episodeCounts]: seasonNumber → number of episodes).
///
/// - Mid-season (or when the current season's count is unknown) → the next
///   episode in the same season.
/// - Last episode of the season → the **first episode of the next season**, if
///   one exists in [episodeCounts].
/// - Last episode of the last known season → null (nothing to queue).
///
/// Pure + tested.
(int season, int episode)? nextEpisodeNumber(
  int season,
  int episode, {
  required Map<int, int> episodeCounts,
}) {
  final count = episodeCounts[season];
  if (count != null && episode >= count) {
    final nextSeason = season + 1;
    if (episodeCounts.containsKey(nextSeason)) return (nextSeason, 1);
    return null; // finished the last season
  }
  return (season, episode + 1);
}
