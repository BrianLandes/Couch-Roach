import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../data/tmdb/season.dart';
import '../../data/tmdb/tv_show_details.dart';
import '../../data/tmdb/tv_show_summary.dart';
import '../../injection.dart';
import '../../services/discovery/tmdb_client.dart';

/// Trending TV this week — the "What to Watch Next" rail.
final trendingTvProvider = FutureProvider<List<TvShowSummary>>(
  (ref) => getIt<DiscoveryClient>().trendingTv(),
);

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
