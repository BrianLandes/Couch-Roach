import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../db/database.dart';

/// Per-lane "Remove from this row" for the landing page. See [RailDismissals]
/// for why dismissals are per lane and why they expire on new activity.
abstract class RailDismissalRepository {
  /// Remove a title from [rail], stamped now. Re-dismissing refreshes the time,
  /// which is what a lane compares new activity against.
  Future<void> dismiss({
    required String rail,
    required int tmdbId,
    required String mediaType,
  });

  /// Put a title back in [rail] (the snackbar's Undo).
  Future<void> restore({
    required String rail,
    required int tmdbId,
    required String mediaType,
  });

  /// Live dismissals for [rail], keyed `'<mediaType>:<tmdbId>'` → when.
  Stream<Map<String, DateTime>> watch(String rail);
}

@LazySingleton(as: RailDismissalRepository)
class DriftRailDismissalRepository implements RailDismissalRepository {
  DriftRailDismissalRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> dismiss({
    required String rail,
    required int tmdbId,
    required String mediaType,
  }) async {
    await _db.into(_db.railDismissals).insertOnConflictUpdate(
          RailDismissalsCompanion.insert(
            rail: rail,
            tmdbId: tmdbId,
            mediaType: mediaType,
            dismissedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> restore({
    required String rail,
    required int tmdbId,
    required String mediaType,
  }) async {
    await (_db.delete(_db.railDismissals)
          ..where((t) =>
              t.rail.equals(rail) &
              t.tmdbId.equals(tmdbId) &
              t.mediaType.equals(mediaType)))
        .go();
  }

  @override
  Stream<Map<String, DateTime>> watch(String rail) {
    return (_db.select(_db.railDismissals)..where((t) => t.rail.equals(rail)))
        .watch()
        .map((rows) => {
              for (final r in rows) '${r.mediaType}:${r.tmdbId}': r.dismissedAt,
            });
  }
}
