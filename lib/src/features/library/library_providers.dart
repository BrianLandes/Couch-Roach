import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/rail_dismissal_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';
import '../discover/discover_tile.dart';
import 'landing_lanes.dart';

/// Live list of present (non-missing) library items, fed by the drift watch
/// query so screens update as scans land and files come and go. Kept alive (not
/// autoDispose) — it's the app's central library feed, watched across screens.
final libraryItemsProvider = StreamProvider<List<LibraryItem>>(
  (ref) => getIt<LibraryRepository>().watchPresent(),
);

/// Live Continue Watching feed (in-progress, present titles, newest first).
final continueWatchingProvider = StreamProvider<List<ContinueWatchingEntry>>(
  (ref) => getIt<WatchHistoryRepository>().watchContinueWatching(),
);

/// Live "Recently Downloaded" feed: app-acquired titles, one entry per show,
/// most-recently-downloaded first — for the landing rail of the same name.
final recentlyDownloadedProvider = StreamProvider<List<LibraryItem>>(
  (ref) => getIt<LibraryRepository>().watchRecentlyDownloaded(),
);


/// Live recently-watched titles (any watch, file present or reaped), one per
/// title, newest first — the watch half of the "Recent" lane.
final recentlyWatchedProvider = StreamProvider<List<RecentlyWatched>>(
  (ref) => getIt<WatchHistoryRepository>().watchRecentlyWatched(),
);

/// The landing page's "Recent" lane: recent downloads and recent watches
/// merged, newest activity first, minus anything already in Continue Watching.
/// See [mergeRecentActivity].
final recentLaneProvider = Provider<List<DiscoverTile>>((ref) {
  DiscoverTile tileOf(LibraryItem i) => DiscoverTile(
        tmdbId: i.tmdbId!,
        // The show's canonical name/poster, not the episode's, so a series
        // shows once with its own art.
        title: i.tmdbName ?? i.title,
        mediaType: i.mediaType,
        posterPath: i.tmdbPosterPath,
      );

  final downloads = [
    for (final i in ref.watch(recentlyDownloadedProvider).asData?.value ??
        const <LibraryItem>[])
      if (i.tmdbId != null) (tile: tileOf(i), at: i.addedAt),
  ];
  final watched = [
    for (final w in ref.watch(recentlyWatchedProvider).asData?.value ??
        const <RecentlyWatched>[])
      (tile: tileOf(w.item), at: w.lastWatchedAt),
  ];
  final inContinueWatching = {
    for (final e in ref.watch(continueWatchingProvider).asData?.value ??
        const <ContinueWatchingEntry>[])
      if (e.item.tmdbId != null) '${e.item.mediaType}:${e.item.tmdbId}',
  };
  return mergeRecentActivity(
    downloads: downloads,
    watched: watched,
    exclude: inContinueWatching,
  );
});

/// Live per-lane dismissals for [rail] (see [RailDismissalRepository]).
final railDismissalsProvider =
    StreamProvider.family<Map<String, DateTime>, String>(
  (ref, rail) => getIt<RailDismissalRepository>().watch(rail),
);
