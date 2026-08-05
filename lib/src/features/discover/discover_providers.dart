import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../data/tmdb/season.dart';
import '../../data/tmdb/tmdb_video.dart';
import '../../data/tmdb/tv_show_details.dart';
import '../../data/tmdb/tv_show_summary.dart';
import '../../injection.dart';
import '../../services/discovery/tmdb_client.dart';
import 'discover_tile.dart';
import 'new_episodes.dart';
import 'recommendation_helpers.dart';
import 'taste_providers.dart';

/// Trending TV this week — the "What to Watch Next" rail.
final trendingTvProvider = FutureProvider<List<TvShowSummary>>(
  (ref) => getIt<DiscoveryClient>().trendingTv(),
);

/// Popular movies this week — the "Popular Movies" rail.
final trendingMoviesProvider = FutureProvider<List<DiscoverTile>>((ref) async =>
    (await getIt<DiscoveryClient>().trendingMovies())
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

/// Full TMDB details for a **movie**, as a [DiscoverTile] (overview + rating +
/// year). Used to enrich a matched library movie — whose row only cached id,
/// name and poster — with the same profile the discovery page shows. Null while
/// loading or on a miss.
final movieTileProvider =
    FutureProvider.family<DiscoverTile?, int>((ref, tmdbId) async {
  final m = await getIt<DiscoveryClient>().movieDetails(tmdbId);
  return m == null ? null : DiscoverTile.fromMovie(m);
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
final recommendedProvider = FutureProvider<List<DiscoverTile>>((ref) async {
  // Seed from what the user clearly likes: recent watches, then favorites, then
  // want-to-watch — each typed so we can pull TV *and* movie recommendations.
  final seeds = <({int tmdbId, String mediaType})>[];
  final seedIds = <int>{};
  void addSeed(int id, String type) {
    if (seedIds.add(id)) seeds.add((tmdbId: id, mediaType: type));
  }

  for (final w in await getIt<WatchHistoryRepository>().watchSignals(limit: 4)) {
    addSeed(w.tmdbId, w.mediaType);
  }
  final saved = getIt<SavedTitlesRepository>();
  for (final f in (await saved.watchFavorites().first).take(3)) {
    addSeed(f.tmdbId, f.mediaType);
  }
  for (final w in (await saved.watchWantToWatch().first).take(2)) {
    addSeed(w.tmdbId, w.mediaType);
  }
  if (seeds.isEmpty) return const [];

  final owned = {
    for (final i in await getIt<LibraryRepository>().getAll())
      if (i.tmdbId != null) i.tmdbId!,
  };
  final tmdb = getIt<DiscoveryClient>();
  final out = <DiscoverTile>[];
  final emitted = <int>{...seedIds}; // never recommend the seeds themselves
  for (final s in seeds.take(6)) {
    if (s.mediaType == 'tv') {
      for (final rec in await tmdb.recommendedTv(s.tmdbId)) {
        if (!owned.contains(rec.tmdbId) && emitted.add(rec.tmdbId)) {
          out.add(DiscoverTile.fromTv(rec));
        }
      }
    } else {
      for (final rec in await tmdb.recommendedMovies(s.tmdbId)) {
        if (!owned.contains(rec.tmdbId) && emitted.add(rec.tmdbId)) {
          out.add(DiscoverTile.fromMovie(rec));
        }
      }
    }
  }
  return out;
});

/// A named recommendation rail's payload: the seed's display name (for the row
/// label) and the tiles to show. Null from a provider means "don't render it."
typedef NamedRail = ({String name, List<DiscoverTile> tiles});

/// "More like <favorite>" — recommendations seeded from your most-recent
/// favorite alone, as its own legible rail (vs. the blended "Recommended For
/// You"). Null when you have no favorites or nothing comes back.
final moreLikeFavoriteProvider = FutureProvider<NamedRail?>((ref) async {
  final favs = await getIt<SavedTitlesRepository>().watchFavorites().first;
  if (favs.isEmpty) return null;
  final seed = favs.first; // newest-favorited
  final owned = await ref.watch(ownedTmdbIdsProvider.future);
  final tmdb = getIt<DiscoveryClient>();
  final tiles = <DiscoverTile>[];
  final seen = <int>{seed.tmdbId};
  if (seed.mediaType == 'tv') {
    for (final r in await tmdb.recommendedTv(seed.tmdbId)) {
      if (!owned.contains(r.tmdbId) && seen.add(r.tmdbId)) {
        tiles.add(DiscoverTile.fromTv(r));
      }
    }
  } else {
    for (final r in await tmdb.recommendedMovies(seed.tmdbId)) {
      if (!owned.contains(r.tmdbId) && seen.add(r.tmdbId)) {
        tiles.add(DiscoverTile.fromMovie(r));
      }
    }
  }
  return tiles.isEmpty ? null : (name: seed.name, tiles: tiles);
});

/// "Acclaimed in <genre>" — top-rated titles (with a vote-count floor so they're
/// genuinely vetted, not a handful of 10/10s) in your #1 inferred genre: a
/// quality axis next to the popularity-based genre rows. Null until there's a
/// taste profile.
final acclaimedInGenreProvider = FutureProvider<NamedRail?>((ref) async {
  final ranked = await ref.watch(tasteProfileProvider.future);
  if (ranked.isEmpty) return null;
  final top = ranked.first;
  final owned = await ref.watch(ownedTmdbIdsProvider.future);
  final tmdb = getIt<DiscoveryClient>();
  const sortBy = 'vote_average.desc';
  const minVotes = 300;
  final tiles = <DiscoverTile>[];
  if (top.mediaType == 'tv') {
    for (final s in await tmdb.discoverTv(
        genreId: top.genreId, sortBy: sortBy, minVotes: minVotes)) {
      if (!owned.contains(s.tmdbId)) tiles.add(DiscoverTile.fromTv(s));
    }
  } else {
    for (final m in await tmdb.discoverMovies(
        genreId: top.genreId, sortBy: sortBy, minVotes: minVotes)) {
      if (!owned.contains(m.tmdbId)) tiles.add(DiscoverTile.fromMovie(m));
    }
  }
  return tiles.isEmpty ? null : (name: top.name, tiles: tiles);
});

/// "Because you watch <Actor>" — the actor recurring across the most titles you
/// watch + favorite, then more of their work (ranked by popularity, minus what
/// you own or seeded it). Null when no actor recurs across your titles.
final favoriteActorProvider = FutureProvider<NamedRail?>((ref) async {
  final seeds = <({int tmdbId, String mediaType})>[];
  final seedIds = <int>{};
  void add(int id, String type) {
    if (seedIds.add(id)) seeds.add((tmdbId: id, mediaType: type));
  }

  for (final w in await getIt<WatchHistoryRepository>().watchSignals(limit: 8)) {
    add(w.tmdbId, w.mediaType);
  }
  for (final f
      in (await getIt<SavedTitlesRepository>().watchFavorites().first).take(6)) {
    add(f.tmdbId, f.mediaType);
  }
  if (seeds.length < 2) return null; // need overlap potential

  final tmdb = getIt<DiscoveryClient>();
  final casts = await Future.wait(seeds.take(10).map((s) =>
      s.mediaType == 'tv' ? tmdb.tvCast(s.tmdbId) : tmdb.movieCast(s.tmdbId)));
  final person = topRecurringPerson(casts);
  if (person == null) return null;

  final owned = await ref.watch(ownedTmdbIdsProvider.future);
  final credits = [...await tmdb.personCredits(person.personId)]
    ..sort((a, b) => b.popularity.compareTo(a.popularity));
  final tiles = <DiscoverTile>[];
  final emitted = <int>{};
  for (final c in credits) {
    if (c.mediaType != 'tv' && c.mediaType != 'movie') continue;
    if (owned.contains(c.tmdbId) || seedIds.contains(c.tmdbId)) continue;
    if (c.displayTitle.isEmpty || !emitted.add(c.tmdbId)) continue;
    tiles.add(DiscoverTile(
      tmdbId: c.tmdbId,
      title: c.displayTitle,
      mediaType: c.mediaType,
      posterPath: c.posterPath,
      year: int.tryParse(c.year ?? ''),
    ));
    if (tiles.length >= 20) break;
  }
  return tiles.isEmpty ? null : (name: person.name, tiles: tiles);
});

/// "Finish the Franchise" — for movies you own or favorited that belong to a
/// TMDB collection, the *other* released films in those collections you don't
/// have yet. Empty when none apply.
final finishFranchiseProvider = FutureProvider<List<DiscoverTile>>((ref) async {
  // Movies the user has a stake in: owned movies + favorited movies.
  final seedMovieIds = <int>{};
  for (final i in await getIt<LibraryRepository>().getAll()) {
    if (i.mediaType == 'movie' && i.tmdbId != null) seedMovieIds.add(i.tmdbId!);
  }
  for (final f in await getIt<SavedTitlesRepository>().watchFavorites().first) {
    if (f.mediaType == 'movie') seedMovieIds.add(f.tmdbId);
  }
  if (seedMovieIds.isEmpty) return const [];

  final tmdb = getIt<DiscoveryClient>();
  final collectionIds = <int>{};
  for (final id in seedMovieIds.take(12)) {
    final cid = await tmdb.movieCollectionId(id);
    if (cid != null) collectionIds.add(cid);
  }
  if (collectionIds.isEmpty) return const [];

  final owned = await ref.watch(ownedTmdbIdsProvider.future);
  final now = DateTime.now();
  final out = <DiscoverTile>[];
  final emitted = <int>{};
  for (final cid in collectionIds) {
    final coll = await tmdb.movieCollection(cid);
    if (coll == null) continue;
    for (final m in coll.parts) {
      if (seedMovieIds.contains(m.tmdbId) || owned.contains(m.tmdbId)) continue;
      if (!emitted.add(m.tmdbId)) continue;
      final released = isAired(
          m.releaseDate == null ? null : DateTime.tryParse(m.releaseDate!), now);
      if (!released) continue;
      out.add(DiscoverTile.fromMovie(m));
    }
  }
  return out;
});

/// "New Episodes For You" — shows you were **caught up on** (your furthest
/// *finished* episode was the latest aired when you watched it) that have since
/// had a new episode air. Both conditions are checked in
/// [hasNewEpisodeSinceCaughtUp] against the air dates of everything ranked above
/// your furthest episode: later episodes of that season (from season details)
/// and later seasons (their season-level air date). Empty until you've finished
/// matched episodes.
final newEpisodesProvider = FutureProvider<List<DiscoverTile>>((ref) async {
  final watched =
      await getIt<WatchHistoryRepository>().latestWatchedEpisodePerShow();
  if (watched.isEmpty) return const [];

  final tmdb = getIt<DiscoveryClient>();
  final now = DateTime.now();

  DateTime? parse(String? d) => d == null ? null : DateTime.tryParse(d);

  final results = await Future.wait(watched.take(12).map((show) async {
    final details = await tmdb.tvDetails(show.tmdbId);
    final season = await tmdb.seasonDetails(show.tmdbId, show.season);

    // Air dates of everything ranked above the furthest-finished episode: later
    // episodes of the same season, plus later seasons (season-level date stands
    // in for their episodes).
    final higher = <DateTime?>[
      for (final e in season?.episodes ?? const [])
        if (e.episodeNumber > show.episode) parse(e.airDate),
      for (final s in details?.seasons ?? const [])
        if (s.seasonNumber >= 1 && s.seasonNumber > show.season)
          parse(s.airDate),
    ];

    return hasNewEpisodeSinceCaughtUp(
      higherRankedAirDates: higher,
      lastWatchedAt: show.lastWatchedAt,
      now: now,
    )
        ? _newEpisodeTile(show)
        : null;
  }));

  return results.whereType<DiscoverTile>().toList();
});

DiscoverTile _newEpisodeTile(WatchedShow show) => DiscoverTile(
      tmdbId: show.tmdbId,
      title: show.name,
      mediaType: 'tv',
      posterPath: show.posterPath,
    );

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

/// The watched (completed) episodes of a show, as `(season, episode)` pairs —
/// drives the per-episode "watched" mark on the show detail page. Live.
final completedEpisodesProvider =
    StreamProvider.family<Set<(int, int)>, int>((ref, tmdbId) =>
        getIt<WatchHistoryRepository>().watchCompletedEpisodes(tmdbId));

/// The season of the show's most-recently-watched episode (null when none) — the
/// show detail opens on it instead of always season 1.
final lastWatchedSeasonProvider = FutureProvider.family<int?, int>(
    (ref, tmdbId) =>
        getIt<WatchHistoryRepository>().lastWatchedSeason(tmdbId));

/// Every local file matched to a show (tmdbId), season/episode order — the
/// fallback the show detail page lists when TMDB details won't load, so the
/// user can still play what's on disk. Unlike [localEpisodesProvider] it keeps
/// files that lack a season/episode (a loose matched file) rather than dropping
/// them.
final localShowItemsProvider =
    FutureProvider.family<List<LibraryItem>, int>((ref, tmdbId) async {
  final items = await getIt<LibraryRepository>().localEpisodes(tmdbId);
  items.sort((a, b) {
    final sa = a.season ?? 0, sb = b.season ?? 0;
    if (sa != sb) return sa.compareTo(sb);
    return (a.episode ?? 0).compareTo(b.episode ?? 0);
  });
  return items;
});
