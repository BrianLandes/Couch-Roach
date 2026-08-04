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

/// A watched, still-present file the cleanup reaper will delete: the library row
/// plus when it was last watched, so the UI can show how long until (or that)
/// it's past the grace period. The reaper deletes it once `lastWatchedAt` is
/// older than the configured grace period, unless the user pins it `keep`.
class ReapCandidate {
  const ReapCandidate({required this.item, required this.lastWatchedAt});

  final LibraryItem item;
  final DateTime lastWatchedAt;
}

/// The furthest **finished** episode of a matched TV show, plus when it was
/// finished — the seed for the "New Episodes For You" rail (was the user caught
/// up then, and has anything aired since — see [hasNewEpisodeSinceCaughtUp]).
class WatchedShow {
  const WatchedShow({
    required this.tmdbId,
    required this.name,
    required this.season,
    required this.episode,
    required this.lastWatchedAt,
    this.posterPath,
  });

  final int tmdbId;
  final String name;
  final int season;
  final int episode;

  /// When the furthest-finished episode was watched — the reference instant for
  /// the "caught up then / new since" check.
  final DateTime lastWatchedAt;
  final String? posterPath;
}

/// A distinct watched title for taste inference.
class WatchSignal {
  const WatchSignal({
    required this.tmdbId,
    required this.mediaType,
    required this.lastWatchedAt,
    required this.completed,
  });
  final int tmdbId;
  final String mediaType;
  final DateTime lastWatchedAt;
  final bool completed;
}

abstract class WatchHistoryRepository {
  Future<WatchHistoryData?> forItem(int libraryItemId);

  /// The furthest **finished** (`completed`) episode of each matched TV show,
  /// most-recently-watched show first — seeds the "New Episodes" check. Only
  /// completed episodes count (an in-progress episode, or a next-episode seeded
  /// by [advanceToNextEpisode], isn't "finished"), and each carries its
  /// `lastWatchedAt` so the rail can tell whether the user was caught up then.
  Future<List<WatchedShow>> latestWatchedEpisodePerShow();

  /// In-progress, still-present titles, most-recently-watched first — the
  /// Continue Watching feed. Excludes completed items, items with no progress,
  /// and files flagged missing.
  Stream<List<ContinueWatchingEntry>> watchContinueWatching({int limit = 20});

  /// The `(season, episode)` pairs of show [tmdbId] that have been **watched**
  /// (watch history `completed`), for the show detail page's per-episode watched
  /// mark. Includes episodes whose file was since reaped (so the mark survives
  /// auto-cleanup — the row stays, flagged missing). Live.
  Stream<Set<(int, int)>> watchCompletedEpisodes(int tmdbId);

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

  /// Keep a show in Continue Watching after finishing an episode: seed a
  /// near-zero resume on the **next** episode ([nextLibraryItemId], when it's
  /// downloaded) so the show stays on the rail, now pointing at the next episode
  /// — and, being the most-recently-touched, it supersedes any older in-progress
  /// episode (which would otherwise resurface and look unwatched). No-op if that
  /// next episode already has history, so real progress is never clobbered.
  Future<void> advanceToNextEpisode(int nextLibraryItemId);

  /// Rows with progress, most-recently-watched first (Continue Watching feed).
  Stream<List<WatchHistoryData>> watchRecent();

  /// Distinct TMDB ids of recently-watched, matched shows (newest first) — the
  /// seed for the "Recommended For You" rail.
  Future<List<int>> recentlyWatchedTmdbIds({int limit});

  /// Distinct watched titles (one row per tmdbId+mediaType), most-recent first,
  /// with when it was last watched and whether it's finished — the raw input for
  /// taste inference.
  Future<List<WatchSignal>> watchSignals({int limit});

  /// Present, non-kept library items whose watch is `completed` and whose last
  /// watch was before [before] — the auto-cleanup reaper's delete candidates.
  Future<List<LibraryItem>> reapable(DateTime before);

  /// Every present, non-kept, `completed` item the reaper is tracking — the full
  /// pending-cleanup queue regardless of grace period — soonest-reaped first.
  /// Live, so pinning "keep" (or watching more) updates the Settings list. The
  /// UI compares each `lastWatchedAt` against the grace period to show when it
  /// will be (or already is) deleted.
  Stream<List<ReapCandidate>> watchReapCandidates();
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
  Stream<Set<(int, int)>> watchCompletedEpisodes(int tmdbId) {
    final query = _db.select(_db.watchHistory).join([
      innerJoin(
        _db.libraryItems,
        _db.libraryItems.id.equalsExp(_db.watchHistory.libraryItemId),
      ),
    ])
      ..where(_db.watchHistory.completed.equals(true) &
          _db.libraryItems.tmdbId.equals(tmdbId) &
          _db.libraryItems.season.isNotNull() &
          _db.libraryItems.episode.isNotNull());
    return query.watch().map((rows) => {
          for (final row in rows)
            (
              row.readTable(_db.libraryItems).season!,
              row.readTable(_db.libraryItems).episode!,
            ),
        });
  }

  @override
  Future<void> advanceToNextEpisode(int nextLibraryItemId) async {
    // Only seed a fresh next episode — never overwrite one already watched or
    // in progress. `1s` (not 0) is deliberate: the feed filters on
    // `resumePositionSec > 0`, and a 1-second resume is indistinguishable from
    // the start when played.
    if (await forItem(nextLibraryItemId) != null) return;
    await record(
      libraryItemId: nextLibraryItemId,
      position: const Duration(seconds: 1),
    );
  }

  @override
  Stream<List<ContinueWatchingEntry>> watchContinueWatching({int limit = 20}) {
    // No SQL limit: we collapse multiple in-progress episodes of the same show
    // to one entry (below) and only then take `limit`, so limiting in SQL first
    // could starve other shows. The in-progress set is small on a home box.
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
      ]);

    return query.watch().map((rows) {
      final entries = <ContinueWatchingEntry>[];
      // Show identity for collapsing episodes: the matched TMDB id when present,
      // else the clean show name (the scanner title before any "— S01E01 …" the
      // acquire flow appends). Movies never collapse — each is its own title.
      final seenShows = <String>{};
      for (final row in rows) {
        final wh = row.readTable(_db.watchHistory);
        final item = row.readTable(_db.libraryItems);
        if (item.mediaType == 'tv') {
          final key = item.tmdbId != null
              ? 'tv:${item.tmdbId}'
              : 'tv:${item.title.split(' — ').first.trim().toLowerCase()}';
          // Rows are newest-watched first, so the first survivor per show is the
          // most recently watched episode — the only one we keep.
          if (!seenShows.add(key)) continue;
        }
        entries.add(ContinueWatchingEntry(
          item: item,
          resumePositionSec: wh.resumePositionSec,
          durationSec: wh.durationSec,
        ));
        if (entries.length >= limit) break;
      }
      return entries;
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
      ..where(_db.watchHistory.completed.equals(true) &
          _db.libraryItems.mediaType.equals('tv') &
          _db.libraryItems.tmdbId.isNotNull() &
          _db.libraryItems.season.isNotNull() &
          _db.libraryItems.episode.isNotNull())
      ..orderBy([
        OrderingTerm(
          expression: _db.watchHistory.lastWatchedAt,
          mode: OrderingMode.desc,
        ),
      ]);

    // Keep the furthest-finished episode per show (with that row's lastWatchedAt);
    // insertion order (newest watch first, from the query) is preserved.
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
          lastWatchedAt: row.readTable(_db.watchHistory).lastWatchedAt,
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
  Future<List<WatchSignal>> watchSignals({int limit = 30}) async {
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

    final out = <WatchSignal>[];
    final seen = <String>{};
    for (final row in await query.get()) {
      final item = row.readTable(_db.libraryItems);
      final wh = row.readTable(_db.watchHistory);
      final id = item.tmdbId;
      if (id == null) continue;
      if (!seen.add('$id:${item.mediaType}')) continue; // one row per title
      out.add(WatchSignal(
        tmdbId: id,
        mediaType: item.mediaType,
        lastWatchedAt: wh.lastWatchedAt,
        completed: wh.completed,
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<List<LibraryItem>> reapable(DateTime before) async {
    final query = _db.select(_db.watchHistory).join([
      innerJoin(
        _db.libraryItems,
        _db.libraryItems.id.equalsExp(_db.watchHistory.libraryItemId),
      ),
      // A matched title may be pinned "keep" at the show level (SavedTitles):
      // exempt its files — including episodes acquired after pinning — since
      // this flag is per-show, not per-episode. Unmatched rows never match the
      // join (null tmdbId) and reap normally.
      leftOuterJoin(
        _db.savedTitles,
        _db.savedTitles.tmdbId.equalsExp(_db.libraryItems.tmdbId) &
            _db.savedTitles.mediaType.equalsExp(_db.libraryItems.mediaType),
      ),
    ])
      ..where(_db.watchHistory.completed.equals(true) &
          _db.watchHistory.lastWatchedAt.isSmallerThanValue(before) &
          _db.libraryItems.keep.equals(false) &
          _db.savedTitles.keptAt.isNull() &
          _db.libraryItems.missing.equals(false));
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.libraryItems)).toList();
  }

  @override
  Stream<List<ReapCandidate>> watchReapCandidates() {
    final query = _db.select(_db.watchHistory).join([
      innerJoin(
        _db.libraryItems,
        _db.libraryItems.id.equalsExp(_db.watchHistory.libraryItemId),
      ),
      // Same show-level "keep" exemption as reapable (see there).
      leftOuterJoin(
        _db.savedTitles,
        _db.savedTitles.tmdbId.equalsExp(_db.libraryItems.tmdbId) &
            _db.savedTitles.mediaType.equalsExp(_db.libraryItems.mediaType),
      ),
    ])
      ..where(_db.watchHistory.completed.equals(true) &
          _db.libraryItems.keep.equals(false) &
          _db.savedTitles.keptAt.isNull() &
          _db.libraryItems.missing.equals(false))
      // Oldest watch first: the one nearest (or furthest past) the grace cutoff.
      ..orderBy([
        OrderingTerm(
          expression: _db.watchHistory.lastWatchedAt,
          mode: OrderingMode.asc,
        ),
      ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return ReapCandidate(
          item: row.readTable(_db.libraryItems),
          lastWatchedAt: row.readTable(_db.watchHistory).lastWatchedAt,
        );
      }).toList();
    });
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
