import '../../data/tmdb/movie_summary.dart';
import '../../data/tmdb/tv_show_summary.dart';

/// A uniform view-model for a TMDB poster tile, so discovery rails and search
/// can mix TV and movies without caring which DTO produced them. Tapping
/// dispatches by [mediaType]: `'tv'` → the show detail page, `'movie'` → the
/// movie detail page.
class DiscoverTile {
  const DiscoverTile({
    required this.tmdbId,
    required this.title,
    required this.mediaType,
    this.posterPath,
    this.overview = '',
    this.year,
    this.voteAverage,
  });

  final int tmdbId;
  final String title;

  /// `'tv'` or `'movie'`.
  final String mediaType;
  final String? posterPath;
  final String overview;
  final int? year;
  final double? voteAverage;

  bool get isTv => mediaType == 'tv';

  factory DiscoverTile.fromTv(TvShowSummary s) => DiscoverTile(
        tmdbId: s.tmdbId,
        title: s.name,
        mediaType: 'tv',
        posterPath: s.posterPath,
        overview: s.overview,
        year: _yearOf(s.firstAirDate),
        voteAverage: s.voteAverage,
      );

  factory DiscoverTile.fromMovie(MovieSummary s) => DiscoverTile(
        tmdbId: s.tmdbId,
        title: s.title,
        mediaType: 'movie',
        posterPath: s.posterPath,
        overview: s.overview,
        year: _yearOf(s.releaseDate),
        voteAverage: s.voteAverage,
      );
}

/// The four-digit year from a TMDB `YYYY-MM-DD` date, or null.
int? _yearOf(String? date) =>
    (date != null && date.length >= 4) ? int.tryParse(date.substring(0, 4)) : null;

/// Fill in a **sparse** [base] tile from a [fetched] one loaded by TMDB id.
///
/// Tiles built from a local row — a saved/favorited title, an Alexa-queued
/// title, a recent download — only carry what that row cached (id, name,
/// mediaType, poster). The detail page renders overview/year/rating straight off
/// the tile, so without this it would show a bare page for exactly the titles
/// the user chose to save.
///
/// [base] wins on identity (id and mediaType are what the fetch was keyed on);
/// [fetched] wins on everything it actually has, falling back to [base] field by
/// field so a partial TMDB response never blanks out something already on
/// screen. Returns [base] unchanged while the fetch is pending or on a miss, so
/// the page paints immediately and fills in when TMDB answers. Pure.
DiscoverTile hydrateTile(DiscoverTile base, DiscoverTile? fetched) {
  if (fetched == null) return base;
  return DiscoverTile(
    tmdbId: base.tmdbId,
    mediaType: base.mediaType,
    title: fetched.title.isNotEmpty ? fetched.title : base.title,
    posterPath: fetched.posterPath ?? base.posterPath,
    overview: fetched.overview.isNotEmpty ? fetched.overview : base.overview,
    year: fetched.year ?? base.year,
    voteAverage: fetched.voteAverage ?? base.voteAverage,
  );
}
