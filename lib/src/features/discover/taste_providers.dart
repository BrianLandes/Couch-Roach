import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_service.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';
import '../../services/discovery/tmdb_client.dart';
import 'discover_tile.dart';
import 'taste.dart';

/// tmdbIds already in the library — excluded from discovery rows so they surface
/// only titles the user doesn't already have.
final ownedTmdbIdsProvider = FutureProvider<Set<int>>((ref) async {
  final items = await getIt<LibraryRepository>().getAll();
  return {for (final i in items) if (i.tmdbId != null) i.tmdbId!};
});

/// Ranked genres inferred from the user's signals (watch history + favorites +
/// want-to-watch). Empty until there's some signal to learn from.
final tasteProfileProvider = FutureProvider<List<GenreScore>>((ref) async {
  final now = DateTime.now();
  final signals = <RawSignal>[];

  for (final w in await getIt<WatchHistoryRepository>().watchSignals(limit: 30)) {
    signals.add(RawSignal(
      tmdbId: w.tmdbId,
      mediaType: w.mediaType,
      source: TasteSource.watched,
      completed: w.completed,
      ageDays: now.difference(w.lastWatchedAt).inDays,
    ));
  }
  final saved = getIt<SavedTitlesRepository>();
  for (final f in await saved.watchFavorites().first) {
    signals.add(RawSignal(
      tmdbId: f.tmdbId,
      mediaType: f.mediaType,
      source: TasteSource.favorite,
      ageDays:
          f.favoritedAt == null ? null : now.difference(f.favoritedAt!).inDays,
    ));
  }
  for (final w in await saved.watchWantToWatch().first) {
    signals.add(RawSignal(
      tmdbId: w.tmdbId,
      mediaType: w.mediaType,
      source: TasteSource.wantToWatch,
      ageDays: w.wantToWatchAt == null
          ? null
          : now.difference(w.wantToWatchAt!).inDays,
    ));
  }
  if (signals.isEmpty) return const [];

  // The heaviest-weighted dozen titles carry the profile — bounds the genre
  // lookups so the landing page doesn't fan out dozens of TMDB calls.
  final merged = mergeSignalWeights(signals);
  final top = merged.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final chosen = top.take(12).toList();

  final tmdb = getIt<DiscoveryClient>();
  final weighted = await Future.wait(chosen.map((e) async {
    final genres =
        await tmdb.titleGenres(e.key.tmdbId, isTv: e.key.mediaType == 'tv');
    return WeightedGenres(
        mediaType: e.key.mediaType, genres: genres, weight: e.value);
  }));
  return rankGenres(weighted.where((w) => w.genres.isNotEmpty).toList());
});

/// The genre rows to render — top ranked minus hidden — or empty when the
/// personalized-categories setting is off.
final personalGenreRowsProvider = FutureProvider<List<GenreScore>>((ref) async {
  if (!getIt<SettingsService>().personalizedCategories) return const [];
  final ranked = await ref.watch(tasteProfileProvider.future);
  return pickGenreRows(ranked,
      hidden: getIt<SettingsService>().hiddenGenres, max: 4);
});

/// Popular titles in a genre for one personalized row, minus anything already
/// in the library.
final genreTilesProvider = FutureProvider.family<List<DiscoverTile>,
    ({String mediaType, int genreId})>((ref, g) async {
  final owned = await ref.watch(ownedTmdbIdsProvider.future);
  final tmdb = getIt<DiscoveryClient>();
  if (g.mediaType == 'tv') {
    final res = await tmdb.discoverTv(genreId: g.genreId);
    return [
      for (final s in res)
        if (!owned.contains(s.tmdbId)) DiscoverTile.fromTv(s),
    ];
  }
  final res = await tmdb.discoverMovies(genreId: g.genreId);
  return [
    for (final m in res)
      if (!owned.contains(m.tmdbId)) DiscoverTile.fromMovie(m),
  ];
});
