/// Air info for the "new episodes of watched shows" check, decoupled from the
/// TMDB DTOs so the logic is pure + unit-testable.
class SeasonAir {
  const SeasonAir({required this.season, this.airDate});
  final int season;
  final DateTime? airDate;
}

class EpisodeAir {
  const EpisodeAir({required this.episode, this.airDate});
  final int episode;
  final DateTime? airDate;
}

/// True when a season *later* than the one the user is on has already started
/// airing by [now] — i.e. there's a whole new season to catch up on. Unaired
/// (or date-less) future seasons don't count. Pure + tested.
bool hasNewerAiredSeason({
  required int watchedSeason,
  required List<SeasonAir> seasons,
  required DateTime now,
}) {
  for (final s in seasons) {
    if (s.season <= watchedSeason) continue;
    final aired = s.airDate;
    if (aired != null && !aired.isAfter(now)) return true;
  }
  return false;
}

/// True when a later episode than [watchedEpisode] (within the same season) has
/// already aired by [now]. Pure + tested.
bool hasLaterAiredEpisode({
  required int watchedEpisode,
  required List<EpisodeAir> episodes,
  required DateTime now,
}) {
  for (final e in episodes) {
    if (e.episode <= watchedEpisode) continue;
    final aired = e.airDate;
    if (aired != null && !aired.isAfter(now)) return true;
  }
  return false;
}
