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

  /// TMDB metadata cached on the row after matching (M2): the canonical title and
  /// poster path (build the URL with TmdbImages). Null until matched.
  TextColumn get tmdbName => text().nullable()();
  TextColumn get tmdbPosterPath => text().nullable()();

  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();

  TextColumn get filePath => text().unique()();
  TextColumn get container => text().nullable()();
  TextColumn get videoCodec => text().nullable()();
  TextColumn get audioCodec => text().nullable()();
  BoolColumn get hasEmbeddedEnSub =>
      boolean().withDefault(const Constant(false))();

  /// User-set subtitle timing offset for this title, in milliseconds, applied
  /// as mpv's `sub-delay` during playback (positive delays the subtitles).
  /// Persisted per file so a re-watch keeps the correction; 0 means in sync.
  IntColumn get subtitleOffsetMs =>
      integer().withDefault(const Constant(0))();

  /// The audio / subtitle track the user *manually* chose for this file, as the
  /// libmpv track id (a subtitle id of `'no'` means "off"). Null until the user
  /// picks one from the player menu — while null the automatic pick governs
  /// (surround/language for audio, English fetch for subtitles). Set means the
  /// choice is restored on every re-watch and overrides the auto-pick. Stored
  /// per file so each episode/movie remembers its own.
  TextColumn get preferredAudioTrackId => text().nullable()();
  TextColumn get preferredSubtitleTrackId => text().nullable()();

  /// Provenance: true when the app acquired this file (torrent), false when it
  /// was already sitting in a library folder. Informational — cleanup eligibility
  /// is driven by library-folder membership + [keep], not this flag.
  BoolColumn get managed => boolean().withDefault(const Constant(false))();

  /// User-pinned "keep around": exempt from auto-cleanup even after a full
  /// watch (e.g. a movie to rewatch). Everything in the library folders is
  /// otherwise fair game to hydrate and then reap (see DECISIONS: auto-cleanup).
  BoolColumn get keep => boolean().withDefault(const Constant(false))();

  /// Set when a scan no longer finds the file on disk (deleted, or its disk is
  /// offline). Flagged rather than deleted so watch history / keep survive a
  /// transient disappearance (e.g. an unplugged disk); the reaper is the only
  /// hard-deleter.
  BoolColumn get missing => boolean().withDefault(const Constant(false))();

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

/// App-wide user preferences as a generic key/value store. Typed access lives in
/// `SettingsService`; keeping the table generic means a new setting never needs a
/// schema migration.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// User-curated per-title state for TMDB titles (shows/movies), independent of
/// whether the title is in the local library — you can favorite or watchlist
/// something you don't own yet. A title can be in any combination of lists; each
/// non-null timestamp means it's in that list and doubles as the newest-first
/// sort key. The row is removed once every timestamp is null. Keyed by TMDB id +
/// media type (movie and tv ids are separate namespaces).
class SavedTitles extends Table {
  IntColumn get tmdbId => integer()();

  /// 'tv' or 'movie'.
  TextColumn get mediaType => text()();

  /// TMDB display name + poster path, cached so list tiles render without a
  /// network round-trip.
  TextColumn get name => text()();
  TextColumn get posterPath => text().nullable()();

  DateTimeColumn get favoritedAt => dateTime().nullable()();
  DateTimeColumn get wantToWatchAt => dateTime().nullable()();

  /// Set means the user pinned this whole title "keep": its library files are
  /// exempt from auto-cleanup after a watch — including episodes downloaded
  /// *after* it was pinned, since the reaper checks this show-level flag rather
  /// than each episode row. The show-level counterpart to `LibraryItems.keep`
  /// (which still pins an individual movie / loose file).
  DateTimeColumn get keptAt => dateTime().nullable()();

  /// Set means the user marked this title "not interested": it's dropped from
  /// every discovery row on the landing page (recommendations, trending,
  /// personalized genre rows, …) but still turns up in search.
  DateTimeColumn get notInterestedAt => dateTime().nullable()();

  /// How this entry got here when it wasn't a direct in-app action — e.g.
  /// 'alexa' for a title queued by voice (see the Alexa inbox drain). Null for
  /// the normal case (the user favorited/watchlisted it themselves).
  /// Informational: powers a "recently added via Alexa" surface later.
  TextColumn get source => text().nullable()();

  @override
  Set<Column> get primaryKey => {tmdbId, mediaType};
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
  tables: [
    LibraryItems,
    WatchHistory,
    SubtitleAttempts,
    Settings,
    SavedTitles,
    StorageLocations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: inject an in-memory or custom executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(libraryItems, libraryItems.missing);
          }
          if (from < 3) {
            await m.addColumn(libraryItems, libraryItems.tmdbName);
            await m.addColumn(libraryItems, libraryItems.tmdbPosterPath);
          }
          if (from < 4) {
            await m.createTable(settings);
          }
          if (from < 5) {
            await m.addColumn(libraryItems, libraryItems.subtitleOffsetMs);
          }
          if (from < 6) {
            await m.createTable(savedTitles);
          }
          if (from < 7) {
            await m.addColumn(savedTitles, savedTitles.source);
          }
          if (from < 8) {
            await m.addColumn(savedTitles, savedTitles.keptAt);
          }
          if (from < 9) {
            await m.addColumn(savedTitles, savedTitles.notInterestedAt);
          }
          if (from < 10) {
            await m.addColumn(libraryItems, libraryItems.preferredAudioTrackId);
            await m.addColumn(
                libraryItems, libraryItems.preferredSubtitleTrackId);
          }
        },
        beforeOpen: (details) async {
          // Enable cascade deletes (watch_history → library_items).
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'couch_roach.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
