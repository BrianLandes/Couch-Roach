import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../data/tmdb/season.dart';
import '../../data/tmdb/tmdb_video.dart';
import '../../data/tmdb/tv_show_details.dart';
import '../../data/tmdb/tv_show_summary.dart';
import '../../injection.dart';
import '../../services/discovery/tmdb_client.dart';
import 'discover_tile.dart';

/// Trending TV this week — the "What to Watch Next" rail.
final trendingTvProvider = FutureProvider<List<TvShowSummary>>(
  (ref) => getIt<DiscoveryClient>().trendingTv(),
);

/// TMDB genre id for Documentary (movies).
const _documentaryGenre = 99;

/// Popular movies this week — the "Popular Movies" rail.
final trendingMoviesProvider = FutureProvider<List<DiscoverTile>>((ref) async =>
    (await getIt<DiscoveryClient>().trendingMovies())
        .map(DiscoverTile.fromMovie)
        .toList());

/// Documentary films — the "Documentaries" rail.
final documentaryMoviesProvider =
    FutureProvider<List<DiscoverTile>>((ref) async =>
        (await getIt<DiscoveryClient>().discoverMovies(genreId: _documentaryGenre))
            .map(DiscoverTile.fromMovie)
            .toList());

/// TMDB search across TV + movies for [query], interleaved so the top hit of
/// each type surfaces early. Empty for a blank query.
final tmdbSearchProvider =
    FutureProvider.family<List<DiscoverTile>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  final tmdb = getIt<DiscoveryClient>();
  final tv = (await tmdb.searchTv(query)).map(DiscoverTile.fromTv).toList();
  final movies =
      (await tmdb.searchMovies(query)).map(DiscoverTile.fromMovie).toList();

  final out = <DiscoverTile>[];
  for (var i = 0; i < tv.length || i < movies.length; i++) {
    if (i < tv.length) out.add(tv[i]);
    if (i < movies.length) out.add(movies[i]);
  }
  return out;
});

/// The local library item matching [tmdbId] (e.g. a downloaded movie), or null.
/// Drives the movie detail page's Play button.
final localTitleProvider =
    FutureProvider.family<LibraryItem?, int>((ref, tmdbId) async {
  final items = await getIt<LibraryRepository>().localEpisodes(tmdbId);
  return items.isEmpty ? null : items.first;
});

/// The YouTube trailer URL for a title, or null when there's no usable preview.
/// Keyed by (tmdbId, isTv). Cheap (one show-level call) — drives whether the
/// Trailer button is shown at all; the full list is loaded lazily by
/// [trailerOptionsProvider] only when the picker opens.
final trailerUrlProvider =
    FutureProvider.family<String?, (int, bool)>((ref, key) async {
  final videos =
      await getIt<DiscoveryClient>().videos(tmdbId: key.$1, isTv: key.$2);
  final trailer = pickTrailer(videos);
  return trailer == null ? null : youtubeWatchUrl(trailer.key);
});

/// Every previewable video for a title, grouped for the trailer picker. For a TV
/// title this also pulls per-season videos (one call per numbered season, run in
/// parallel) and tags them with their season. Keyed by (tmdbId, isTv). Watched
/// only when the picker sheet is open, so the extra season calls are on-demand.
final trailerOptionsProvider =
    FutureProvider.family<List<TrailerGroup>, (int, bool)>((ref, key) async {
  final tmdb = getIt<DiscoveryClient>();
  final tmdbId = key.$1;
  final isTv = key.$2;

  final options = [
    for (final v in await tmdb.videos(tmdbId: tmdbId, isTv: isTv))
      TrailerOption(v),
  ];

  if (isTv) {
    final details = await tmdb.tvDetails(tmdbId);
    final seasonNumbers = (details?.seasons ?? const [])
        .map((s) => s.seasonNumber)
        .where((n) => n >= 1)
        .toList(growable: false);
    final perSeason = await Future.wait(seasonNumbers.map((n) async {
      final vids = await tmdb.seasonVideos(tmdbId: tmdbId, seasonNumber: n);
      return [for (final v in vids) TrailerOption(v, seasonNumber: n)];
    }));
    for (final list in perSeason) {
      options.addAll(list);
    }
  }

  return groupTrailerOptions(options);
});

/// "Recommended For You" — TMDB recommendations seeded by the shows you've
/// watched most recently, concatenated + deduped (no personalization algorithm;
/// that's a deferred fork). Empty until you've watched some matched shows.
final recommendedProvider = FutureProvider<List<TvShowSummary>>((ref) async {
  final ids = await getIt<WatchHistoryRepository>().recentlyWatchedTmdbIds(limit: 3);
  if (ids.isEmpty) return const [];

  final tmdb = getIt<DiscoveryClient>();
  final seen = <int>{...ids};
  final out = <TvShowSummary>[];
  for (final id in ids) {
    for (final rec in await tmdb.recommendedTv(id)) {
      if (seen.add(rec.tmdbId)) out.add(rec);
    }
  }
  return out;
});

/// Full details for a show (`tv/{id}`).
final tvDetailsProvider = FutureProvider.family<TvShowDetails?, int>(
  (ref, tmdbId) => getIt<DiscoveryClient>().tvDetails(tmdbId),
);

/// Episodes for a season. Keyed by (tmdbId, seasonNumber).
final seasonProvider = FutureProvider.family<SeasonDetails?, (int, int)>(
  (ref, key) => getIt<DiscoveryClient>().seasonDetails(key.$1, key.$2),
);

/// Which episodes of a show are available locally, keyed by (season, episode).
final localEpisodesProvider =
    FutureProvider.family<Map<(int, int), LibraryItem>, int>((ref, tmdbId) async {
  final items = await getIt<LibraryRepository>().localEpisodes(tmdbId);
  return {
    for (final i in items)
      if (i.season != null && i.episode != null) (i.season!, i.episode!): i,
  };
});
