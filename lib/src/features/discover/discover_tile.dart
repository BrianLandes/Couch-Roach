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
