import '../../data/tmdb/tv_show_details.dart' show Genre;

/// Local, content-based taste inference for the personalized category rows.
/// Turns the user's signals (what they watch, favorite, want to watch) into a
/// ranked set of genres — no ML backend, all pure + tested.

enum TasteSource { watched, favorite, wantToWatch }

/// One like-signal about a title, before weighting.
class RawSignal {
  const RawSignal({
    required this.tmdbId,
    required this.mediaType,
    required this.source,
    this.completed = false,
    this.ageDays,
  });
  final int tmdbId;
  final String mediaType; // 'tv' | 'movie'
  final TasteSource source;
  final bool completed;

  /// Age of the signal in days (for recency decay); null = unknown/undated.
  final int? ageDays;
}

/// Weight of one signal. **Watch history counts most, then favorites, then
/// want-to-watch** (per the chosen model); a finished watch counts a bit extra,
/// and recent signals outweigh old ones (gentle decay over ~months). Pure.
double signalWeight(RawSignal s) {
  final base = switch (s.source) {
    TasteSource.watched => 3.0,
    TasteSource.favorite => 2.0,
    TasteSource.wantToWatch => 1.0,
  };
  final completedBoost =
      (s.source == TasteSource.watched && s.completed) ? 1.4 : 1.0;
  final days = s.ageDays;
  final recency = days == null ? 1.0 : 1.0 / (1.0 + days / 45.0);
  return base * completedBoost * recency;
}

/// A title identity.
typedef TitleKey = ({int tmdbId, String mediaType});

/// Sum signal weights per title (a title you watched *and* favorited counts as
/// both). Pure.
Map<TitleKey, double> mergeSignalWeights(List<RawSignal> signals) {
  final out = <TitleKey, double>{};
  for (final s in signals) {
    final key = (tmdbId: s.tmdbId, mediaType: s.mediaType);
    out[key] = (out[key] ?? 0) + signalWeight(s);
  }
  return out;
}

/// A title's genres and the weight it contributes to them.
class WeightedGenres {
  const WeightedGenres({
    required this.mediaType,
    required this.genres,
    required this.weight,
  });
  final String mediaType;
  final List<Genre> genres;
  final double weight;
}

/// A ranked genre (per media type — TMDB TV and movie genre ids differ).
class GenreScore {
  const GenreScore({
    required this.mediaType,
    required this.genreId,
    required this.name,
    required this.score,
  });
  final String mediaType;
  final int genreId;
  final String name;
  final double score;

  /// Stable key ("tv:10765") for hiding / dedupe.
  String get key => '$mediaType:$genreId';
}

/// Rank genres by summed title weight, highest first. Pure.
List<GenreScore> rankGenres(List<WeightedGenres> titles) {
  final score = <String, double>{};
  final name = <String, String>{};
  final gid = <String, int>{};
  final mtype = <String, String>{};
  for (final t in titles) {
    for (final g in t.genres) {
      final key = '${t.mediaType}:${g.id}';
      score[key] = (score[key] ?? 0) + t.weight;
      name[key] = g.name;
      gid[key] = g.id;
      mtype[key] = t.mediaType;
    }
  }
  final out = [
    for (final k in score.keys)
      GenreScore(
          mediaType: mtype[k]!, genreId: gid[k]!, name: name[k]!, score: score[k]!),
  ];
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// The rows to actually show: the top [max] ranked genres minus any the user has
/// [hidden]. Pure.
List<GenreScore> pickGenreRows(
  List<GenreScore> ranked, {
  Set<String> hidden = const {},
  int max = 4,
}) {
  final out = <GenreScore>[];
  for (final g in ranked) {
    if (hidden.contains(g.key)) continue;
    out.add(g);
    if (out.length >= max) break;
  }
  return out;
}
