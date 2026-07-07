import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../db/database.dart';

/// Outcome of a subtitle-fetch attempt, persisted in `subtitle_attempts` so the
/// quota-aware queue never retries endlessly (HANDOFF §4.6 / §5).
///
/// Terminal outcomes ([present], [found], [notFound]) take an item out of the
/// queue; transient ones ([quota], [error]) leave it eligible for a later run.
/// Only [found] consumes an OpenSubtitles download from the daily quota.
enum SubtitleAttemptStatus {
  /// English was already available (embedded track or `.srt` sidecar) — no fetch.
  present('present'),

  /// Downloaded and saved from OpenSubtitles. Consumes a daily download.
  found('found'),

  /// Search returned nothing usable. Not retried automatically (a manual
  /// re-scan can clear it if subtitles get uploaded later).
  notFound('not_found'),

  /// The daily download quota was exhausted — retry on a later run.
  quota('quota'),

  /// A network/IO error — retry on a later run.
  error('error');

  const SubtitleAttemptStatus(this.wire);

  /// The value stored in the `status` column.
  final String wire;

  static const _terminal = {present, found, notFound};
  bool get isTerminal => _terminal.contains(this);
}

/// Reads and writes `subtitle_attempts`, and answers the queue's questions:
/// which library items still need a subtitle, and how many downloads we've
/// already spent today.
abstract class SubtitleAttemptsRepository {
  /// Append an attempt row for [libraryItemId].
  Future<void> record(int libraryItemId, SubtitleAttemptStatus status);

  /// Present library items with no terminal attempt yet, oldest-added first —
  /// the queue's candidates. [limit] bounds the batch so a huge library is
  /// worked through gradually.
  Future<List<LibraryItem>> itemsNeedingSubtitles({int limit});

  /// Count of subtitles actually downloaded ([SubtitleAttemptStatus.found])
  /// since local midnight — the spend against the daily quota.
  Future<int> downloadsToday();
}

@LazySingleton(as: SubtitleAttemptsRepository)
class DriftSubtitleAttemptsRepository implements SubtitleAttemptsRepository {
  DriftSubtitleAttemptsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> record(int libraryItemId, SubtitleAttemptStatus status) async {
    await _db.into(_db.subtitleAttempts).insert(
          SubtitleAttemptsCompanion.insert(
            libraryItemId: libraryItemId,
            status: status.wire,
          ),
        );
  }

  @override
  Future<List<LibraryItem>> itemsNeedingSubtitles({int limit = 20}) async {
    final terminalWire = SubtitleAttemptStatus.values
        .where((s) => s.isTerminal)
        .map((s) => s.wire)
        .toList();

    final done = await (_db.selectOnly(_db.subtitleAttempts, distinct: true)
          ..addColumns([_db.subtitleAttempts.libraryItemId])
          ..where(_db.subtitleAttempts.status.isIn(terminalWire)))
        .get();
    final excludeIds =
        done.map((r) => r.read(_db.subtitleAttempts.libraryItemId)!).toList();

    final query = _db.select(_db.libraryItems)
      ..where((t) => t.missing.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.addedAt)])
      ..limit(limit);
    if (excludeIds.isNotEmpty) {
      query.where((t) => t.id.isNotIn(excludeIds));
    }
    return query.get();
  }

  @override
  Future<int> downloadsToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final count = _db.subtitleAttempts.id.count();
    final row = await (_db.selectOnly(_db.subtitleAttempts)
          ..addColumns([count])
          ..where(
            _db.subtitleAttempts.status.equals(SubtitleAttemptStatus.found.wire) &
                _db.subtitleAttempts.attemptedAt
                    .isBiggerOrEqualValue(startOfDay),
          ))
        .getSingle();
    return row.read(count) ?? 0;
  }
}
