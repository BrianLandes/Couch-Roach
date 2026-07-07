/// TMDB discovery client seam (HANDOFF §4.2 / §6). Implemented in M2. Pure HTTP,
/// keyed by `AppConfig.tmdbApiKey`. Endpoints: search, tv/{id},
/// tv/{id}/season/{n}, trending, recommendations, similar, watch/providers.
abstract class DiscoveryClient {
  Future<List<Object>> trending();
  Future<Object?> tvDetails(int tmdbId);
  Future<List<Object>> recommendations(int tmdbId);
  Future<int?> matchTitle(String title, {int? year, String mediaType = 'tv'});
}
