import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../db/database.dart';

/// Resume position + completion per library item — the data behind "resume where
/// you left off", the Continue Watching rail, and the cleanup reaper.
///
/// One row per `libraryItemId` (maintained by [record]). Keyed to the library
/// row, which outlives the file: a deleted video flags its library row `missing`
/// but never removes it, so this history survives (see DECISIONS: watch records
/// outlive the file).
/// A resumable title for the Continue Watching rail: the library row plus its
/// resume position and duration.
class ContinueWatchingEntry {
  const ContinueWatchingEntry({
    required this.item,
    required this.resumePositionSec,
    this.durationSec,
  });

  final LibraryItem item;
  final int resumePositionSec;
  final int? durationSec;

  Duration get resume => Duration(seconds: resumePositionSec);

  /// Time left, or null when the duration isn't known.
  Duration? get remaining {
    final d = durationSec;
    if (d == null) return null;
    return Duration(seconds: (d - resumePositionSec).clamp(0, d));
  }
}

/// The furthest-watched episode of a matched TV show — the seed for the "New
/// Episodes For You" rail (compare against what's since aired on TMDB).
class WatchedShow {
  const WatchedShow({
    required this.tmdbId,
    required this.name,
    required this.season,
    required this.episode,
    this.posterPath,
  });

  final int tmdbId;
  final String name;
  final int season;
  final int episode;
  final String? posterPath;
}

abstract class WatchHistoryRepository {
  Future<WatchHistoryData?> forItem(int libraryItemId);

  /// The furthest-watched episode of each matched TV show in watch history,
  /// most-recently-watched show first — seeds the "New Episodes" check.
  Future<List<WatchedShow>> latestWatchedEpisodePerShow();

  /// In-progress, still-present titles, most-recently-watched first — the
  /// Continue Watching feed. Excludes completed items, items with no progress,
  /// and files flagged missing.
  Stream<List<ContinueWatchingEntry>> watchContinueWatching({int limit = 20});

  /// Remove a title from the Continue Watching rail without deleting its history
  /// or marking it watched: clears the resume position so it drops out of the
  /// rail (the feed filters on `resumePositionSec > 0`) and simply restarts from
  /// the beginning next time. Left `completed = false`, so it neither triggers
  /// the cleanup reaper nor stops seeding the recommendation rails. No-op when
  /// there's no history row for [libraryItemId].
  Future<void> dismissFromContinueWatching(int libraryItemId);

  /// Insert or update the row for [libraryItemId]. When [completed] is true the
  /// resume position is cleared so the title restarts next time.
  Future<void> record({
    required int libraryItemId,
    required Duration position,
    Duration? duration,
    bool completed = false,
  });

  /// Rows with progress, most-recently-watched first (Continue Watching feed).
  Stream<List<WatchHistoryData>> watchRecent();

  /// Distinct TMDB ids of recently-watched, matched shows (newest first) — the
  /// seed for the "Recommended For You" rail.
  Future<List<int>> recentlyWatchedTmdbIds({int limit});

  /// Present, non-kept library items whose watch is `completed` and whose last
  /// watch was before [before] — the auto-cleanup reaper's delete candidates.
  Future<List<LibraryItem>> reapable(DateTime before);
}

@LazySingleton(as: WatchHistoryRepository)
class DriftWatchHistoryRepository implements WatchHistoryRepository {
  DriftWatchHistoryRepository(this._db);

  final AppDatabase _db;

  @override
  Future<WatchHistoryData?> forItem(int libraryItemId) {
    return (_db.select(_db.watchHistory)
          ..where((t) => t.libraryItemId.equals(libraryItemId)))
        .getSingleOrNull();
  }

  @override
  Future<void> record({
    required int libraryItemId,
    required Duration position,
    Duration? duration,
    bool completed = false,
  }) async {
    final resumeSec = completed ? 0 : position.inSeconds;
    final existing = await forItem(libraryItemId);

    if (existing == null) {
      await _db.into(_db.watchHistory).insert(
            WatchHistoryCompanion.insert(
              libraryItemId: libraryItemId,
              resumePositionSec: Value(resumeSec),
              durationSec:
                  duration != null ? Value(duration.inSeconds) : const Value.absent(),
              completed: Value(completed),
              lastWatchedAt: Value(DateTime.now()),
            ),
          );
    } else {
      await (_db.update(_db.watchHistory)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        WatchHistoryCompanion(
          resumePositionSec: Value(resumeSec),
          durationSec:
              duration != null ? Value(duration.inSeconds) : const Value.absent(),
          completed: Value(completed),
          lastWatchedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  @override
  Stream<List<ContinueWatchingEntry>> watchContinueWatching({int limit = 20}) {
    final query = _db.select(_db.watchHistory).join([
      innerJoin(
        _db.libraryItems,
        _db.libraryItems.id.equalsExp(_db.watchHistory.libraryItemId),
      ),
    ])
      ..where(_db.watchHistory.completed.equals(false) &
          _db.watchHistory.resumePositionSec.isBiggerThanValue(0) &
          _db.libraryItems.missing.equals(false))
      ..orderBy([
        OrderingTerm(
          expression: _db.watchHistory.lastWatchedAt,
          mode: OrderingMode.desc,
        ),
      ])
      ..limit(limit);

    return query.watch().map((rows) {
      return rows.map((row) {
        final wh = row.readTable(_db.watchHistory);
        final item = row.readTable(_db.libraryItems);
        return ContinueWatchingEntry(
          item: item,
          resumePositionSec: wh.resumePositionSec,
          durationSec: wh.durationSec,
        );
      }).toList();
    });
  }

  @override
  Future<void> dismissFromContinueWatching(int libraryItemId) {
    return (_db.update(_db.watchHistory)
          ..where((t) => t.libraryItemId.equals(libraryItemId)))
        .write(const WatchHistoryCompanion(resumePositionSec: Value(0)));
  }

  @override
  Future<List<WatchedShow>> latestWatchedEpisodePerShow() async {
    final query = _db.select(_db.watchHistory).join([
      innerJoin(
        _db.libraryItems,
        _db.libraryItems.id.equalsExp(_db.watchHistory.libraryItemId),
      ),
    ])
      ..where(_db.libraryItems.mediaType.equals('tv') &
          _db.libraryItems.tmdbId.isNotNull() &
          _db.libraryItems.season.isNotNull() &
          _db.libraryItems.episode.isNotNull())
      ..orderBy([
        OrderingTerm(
          expression: _db.watchHistory.lastWatchedAt,
          mode: OrderingMode.desc,
        ),
      ]);

    // Keep the furthest-watched episode per show; insertion order (newest watch
    // first, from the query) is preserved for the rail.
    int rank(int s, int e) => s * 1000 + e;
    final byShow = <int, WatchedShow>{};
    for (final row in await query.get()) {
      final item = row.readTable(_db.libraryItems);
      final id = item.tmdbId!;
      final s = item.season!;
      final e = item.episode!;
      final existing = byShow[id];
      if (existing == null || rank(existing.season, existing.episode) < rank(s, e)) {
        byShow[id] = WatchedShow(
          tmdbId: id,
          name: item.tmdbName ?? item.title,
          season: s,
          episode: e,
          posterPath: item.tmdbPosterPath,
        );
      }
    }
    return byShow.values.toList();
  }

  @override
  Future<List<int>> recentlyWatchedTmdbIds({int limit = 5}) async {
    final query = _db.select(_db.watchHistory).join([
      innerJoin(
        _db.libraryItems,
        _db.libraryItems.id.equalsExp(_db.watchHistory.libraryItemId),
      ),
    ])
      ..where(_db.libraryItems.tmdbId.isNotNull())
      ..orderBy([
        OrderingTerm(
          expression: _db.watchHistory.lastWatchedAt,
          mode: OrderingMode.desc,
        ),
      ]);

    final ids = <int>[];
    final seen = <int>{};
    for (final row in await query.get()) {
      final id = row.readTable(_db.libraryItems).tmdbId;
      if (id != null && seen.add(id)) {
        ids.add(id);
        if (ids.length >= limit) break;
      }
    }
    return ids;
  }

  @override
  Future<List<LibraryItem>> reapable(DateTime before) async {
    final query = _db.select(_db.watchHistory).join([
      innerJoin(
        _db.libraryItems,
        _db.libraryItems.id.equalsExp(_db.watchHistory.libraryItemId),
      ),
    ])
      ..where(_db.watchHistory.completed.equals(true) &
          _db.watchHistory.lastWatchedAt.isSmallerThanValue(before) &
          _db.libraryItems.keep.equals(false) &
          _db.libraryItems.missing.equals(false));
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.libraryItems)).toList();
  }

  @override
  Stream<List<WatchHistoryData>> watchRecent() {
    return (_db.select(_db.watchHistory)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.lastWatchedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }
}
