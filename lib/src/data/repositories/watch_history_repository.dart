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
abstract class WatchHistoryRepository {
  Future<WatchHistoryData?> forItem(int libraryItemId);

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
