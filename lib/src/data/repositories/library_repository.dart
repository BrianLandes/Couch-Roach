import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../db/database.dart';

/// A media file discovered on disk, before it's persisted. Produced by the
/// scanner, consumed by [LibraryRepository]. `tmdbId` is resolved later (M2), so
/// it isn't part of a scan.
class ScannedFile {
  const ScannedFile({
    required this.filePath,
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
  });

  final String filePath;
  final String title;

  /// 'tv' or 'movie'.
  final String mediaType;
  final int? season;
  final int? episode;
}

/// Persists the on-disk library into the `library` table and answers the
/// library-listing queries the UI watches. Reads return drift [LibraryItem] rows.
abstract class LibraryRepository {
  /// Insert, or update in place if a row with the same `file_path` exists.
  Future<void> upsert(ScannedFile file);

  /// Batched [upsert] for a whole scan.
  Future<void> upsertAll(Iterable<ScannedFile> files);

  /// Flags rows under [rootPath] whose path isn't in [presentPaths] as missing.
  /// Scoped to one root so an offline disk never false-flags another's files.
  /// Returns how many rows were newly/again flagged.
  Future<int> markMissingUnder({
    required String rootPath,
    required Set<String> presentPaths,
  });

  /// Present (non-missing) items, for the library grid. Live.
  Stream<List<LibraryItem>> watchPresent();

  /// Every row including missing ones. Live.
  Stream<List<LibraryItem>> watchAll();

  Future<List<LibraryItem>> getAll();
  Future<LibraryItem?> findByPath(String path);

  /// Present items not yet matched to a TMDB id (for back-fill).
  Future<List<LibraryItem>> unmatched();

  /// Record a TMDB match: id, canonical name, and poster path.
  Future<void> setTmdbMatch({
    required int id,
    required int tmdbId,
    String? name,
    String? posterPath,
  });

  /// Hard-deletes the row and cascades its `watch_history` — a deliberate
  /// "forget this title entirely". NOT for a file that merely disappeared: for
  /// a gone/offline file use [markMissingUnder], which keeps the row and its
  /// watch history so "what I watched / where I left off" survives the delete.
  Future<void> removeByPath(String path);
}

@LazySingleton(as: LibraryRepository)
class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._db);

  final AppDatabase _db;

  LibraryItemsCompanion _insert(ScannedFile f) => LibraryItemsCompanion.insert(
        mediaType: f.mediaType,
        title: f.title,
        filePath: f.filePath,
        season: Value(f.season),
        episode: Value(f.episode),
      );

  // On conflict we refresh only the scan-derived fields (and clear `missing`);
  // tmdbId / managed / keep / addedAt are preserved.
  LibraryItemsCompanion _onConflict(ScannedFile f) => LibraryItemsCompanion(
        title: Value(f.title),
        mediaType: Value(f.mediaType),
        season: Value(f.season),
        episode: Value(f.episode),
        missing: const Value(false),
      );

  @override
  Future<void> upsert(ScannedFile file) async {
    await _db.into(_db.libraryItems).insert(
          _insert(file),
          onConflict: DoUpdate(
            (_) => _onConflict(file),
            target: [_db.libraryItems.filePath],
          ),
        );
  }

  @override
  Future<void> upsertAll(Iterable<ScannedFile> files) async {
    await _db.batch((b) {
      for (final f in files) {
        b.insert(
          _db.libraryItems,
          _insert(f),
          onConflict: DoUpdate(
            (_) => _onConflict(f),
            target: [_db.libraryItems.filePath],
          ),
        );
      }
    });
  }

  @override
  Future<int> markMissingUnder({
    required String rootPath,
    required Set<String> presentPaths,
  }) async {
    final rows = await _db.select(_db.libraryItems).get();
    final goneIds = [
      for (final r in rows)
        if (r.filePath.startsWith(rootPath) && !presentPaths.contains(r.filePath))
          r.id,
    ];
    if (goneIds.isEmpty) return 0;
    return (_db.update(_db.libraryItems)..where((t) => t.id.isIn(goneIds)))
        .write(const LibraryItemsCompanion(missing: Value(true)));
  }

  @override
  Stream<List<LibraryItem>> watchPresent() {
    return (_db.select(_db.libraryItems)
          ..where((t) => t.missing.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.title)]))
        .watch();
  }

  @override
  Stream<List<LibraryItem>> watchAll() {
    return (_db.select(_db.libraryItems)
          ..orderBy([(t) => OrderingTerm(expression: t.title)]))
        .watch();
  }

  @override
  Future<List<LibraryItem>> getAll() => _db.select(_db.libraryItems).get();

  @override
  Future<LibraryItem?> findByPath(String path) {
    return (_db.select(_db.libraryItems)..where((t) => t.filePath.equals(path)))
        .getSingleOrNull();
  }

  @override
  Future<void> removeByPath(String path) async {
    await (_db.delete(_db.libraryItems)..where((t) => t.filePath.equals(path)))
        .go();
  }

  @override
  Future<List<LibraryItem>> unmatched() {
    return (_db.select(_db.libraryItems)
          ..where((t) => t.tmdbId.isNull() & t.missing.equals(false)))
        .get();
  }

  @override
  Future<void> setTmdbMatch({
    required int id,
    required int tmdbId,
    String? name,
    String? posterPath,
  }) async {
    await (_db.update(_db.libraryItems)..where((t) => t.id.equals(id))).write(
      LibraryItemsCompanion(
        tmdbId: Value(tmdbId),
        tmdbName: Value(name),
        tmdbPosterPath: Value(posterPath),
      ),
    );
  }
}
