/// Builds TMDB image CDN URLs from the `*_path` fields on the DTOs. Sizes are
/// TMDB's standard buckets; posters default to a grid-friendly width.
abstract final class TmdbImages {
  static const _base = 'https://image.tmdb.org/t/p';

  static String? poster(String? path, {String size = 'w342'}) =>
      path == null ? null : '$_base/$size$path';

  static String? backdrop(String? path, {String size = 'w780'}) =>
      path == null ? null : '$_base/$size$path';

  static String? still(String? path, {String size = 'w300'}) =>
      path == null ? null : '$_base/$size$path';

  /// Actor headshot (cast lists). `w185` is TMDB's portrait bucket.
  static String? profile(String? path, {String size = 'w185'}) =>
      path == null ? null : '$_base/$size$path';
}
