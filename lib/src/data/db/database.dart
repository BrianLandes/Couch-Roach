import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// A media file known to the app. Maps 1:1 to a file on disk. `tmdbId` is
/// nullable because M1 scans files with filename-derived titles and M2
/// back-fills the TMDB id (see DECISIONS).
class LibraryItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'tv' or 'movie'.
  TextColumn get mediaType => text()();
  TextColumn get title => text()();

  IntColumn get tmdbId => integer().nullable()();
  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();

  TextColumn get filePath => text().unique()();
  TextColumn get container => text().nullable()();
  TextColumn get videoCodec => text().nullable()();
  TextColumn get audioCodec => text().nullable()();
  BoolColumn get hasEmbeddedEnSub =>
      boolean().withDefault(const Constant(false))();

  /// Provenance: true when the app acquired this file (torrent), false when it
  /// was already sitting in a library folder. Informational — cleanup eligibility
  /// is driven by library-folder membership + [keep], not this flag.
  BoolColumn get managed => boolean().withDefault(const Constant(false))();

  /// User-pinned "keep around": exempt from auto-cleanup even after a full
  /// watch (e.g. a movie to rewatch). Everything in the library folders is
  /// otherwise fair game to hydrate and then reap (see DECISIONS: auto-cleanup).
  BoolColumn get keep => boolean().withDefault(const Constant(false))();

  DateTimeColumn get addedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Resume + completion tracking, keyed to a library item.
class WatchHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get libraryItemId =>
      integer().references(LibraryItems, #id, onDelete: KeyAction.cascade)();

  IntColumn get resumePositionSec =>
      integer().withDefault(const Constant(0))();
  IntColumn get durationSec => integer().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastWatchedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Records subtitle-fetch attempts so the quota-limited fetcher never retries
/// endlessly (HANDOFF §4.6 / §5).
class SubtitleAttempts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get libraryItemId =>
      integer().references(LibraryItems, #id, onDelete: KeyAction.cascade)();

  /// 'pending' | 'found' | 'not_found' | 'quota' | 'error'
  TextColumn get status => text()();
  DateTimeColumn get attemptedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Configured storage roots. Content spreads across these by free space
/// (see DECISIONS: multi-disk storage).
class StorageLocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  TextColumn get label => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
}

@DriftDatabase(
  tables: [LibraryItems, WatchHistory, SubtitleAttempts, StorageLocations],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: inject an in-memory or custom executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'couch_roach.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
