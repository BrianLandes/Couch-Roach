import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../db/database.dart';

/// A media file discovered on disk, before it's persisted. Produced by the
/// scanner, consumed by [LibraryRepository]. A plain disk scan leaves the TMDB
/// fields null — they're resolved later by [LibraryMatchService] (M2). An
/// acquire-sourced file, however, already knows its TMDB identity (it was
/// downloaded *for* a specific show/movie), so it carries [tmdbId] (and the
/// canonical name/poster) to stamp the row synchronously — otherwise the
/// next-episode gate, which needs a non-null `tmdbId`, races the async match.
class ScannedFile {
  const ScannedFile({
    required this.filePath,
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
    this.tmdbId,
    this.tmdbName,
    this.tmdbPosterPath,
  });

  final String filePath;
  final String title;

  /// 'tv' or 'movie'.
  final String mediaType;
  final int? season;
  final int? episode;

  /// Known TMDB identity for an acquire-sourced file; null for a plain scan.
  final int? tmdbId;
  final String? tmdbName;
  final String? tmdbPosterPath;
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
  Future<LibraryItem?> findById(int id);

  /// Persist the user's subtitle timing offset (ms) for a title, applied as
  /// mpv's `sub-delay` on playback. Kept per file so a re-watch stays corrected.
  Future<void> setSubtitleOffset(int id, int offsetMs);

  /// Present items not yet matched to a TMDB id (for back-fill).
  Future<List<LibraryItem>> unmatched();

  /// All present local files matched to a show (for episode availability).
  Future<List<LibraryItem>> localEpisodes(int tmdbId);

  /// Record a TMDB match: id, canonical name, and poster path. [mediaType], when
  /// given, corrects the row's type — used when a title first parsed as one type
  /// (e.g. an unmarked episode read as a movie) actually matches the other.
  Future<void> setTmdbMatch({
    required int id,
    required int tmdbId,
    String? name,
    String? posterPath,
    String? mediaType,
  });

  /// Pin/unpin a title as "keep" — a kept title is exempt from auto-cleanup even
  /// after a full watch (see DECISIONS: auto-cleanup).
  Future<void> setKeep(int id, bool keep);

  /// Flag a single row `missing` (its file was reaped/deleted), keeping the row
  /// and its watch history. The single-row counterpart to [markMissingUnder].
  Future<void> markMissing(int id);

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
        tmdbId: Value(f.tmdbId),
        tmdbName: Value(f.tmdbName),
        tmdbPosterPath: Value(f.tmdbPosterPath),
      );

  // On conflict we refresh only the scan-derived fields (and clear `missing`);
  // managed / keep / addedAt are preserved. The TMDB identity is stamped only
  // when this file carries one (an acquire): a plain scan has no tmdbId and must
  // never clobber an existing match.
  LibraryItemsCompanion _onConflict(ScannedFile f) => LibraryItemsCompanion(
        title: Value(f.title),
        mediaType: Value(f.mediaType),
        season: Value(f.season),
        episode: Value(f.episode),
        missing: const Value(false),
        tmdbId: f.tmdbId == null ? const Value.absent() : Value(f.tmdbId),
        tmdbName: f.tmdbId == null ? const Value.absent() : Value(f.tmdbName),
        tmdbPosterPath:
            f.tmdbId == null ? const Value.absent() : Value(f.tmdbPosterPath),
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
  Future<LibraryItem?> findById(int id) {
    return (_db.select(_db.libraryItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  @override
  Future<void> setSubtitleOffset(int id, int offsetMs) async {
    await (_db.update(_db.libraryItems)..where((t) => t.id.equals(id)))
        .write(LibraryItemsCompanion(subtitleOffsetMs: Value(offsetMs)));
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
  Future<List<LibraryItem>> localEpisodes(int tmdbId) {
    return (_db.select(_db.libraryItems)
          ..where((t) => t.tmdbId.equals(tmdbId) & t.missing.equals(false)))
        .get();
  }

  @override
  Future<void> setTmdbMatch({
    required int id,
    required int tmdbId,
    String? name,
    String? posterPath,
    String? mediaType,
  }) async {
    await (_db.update(_db.libraryItems)..where((t) => t.id.equals(id))).write(
      LibraryItemsCompanion(
        tmdbId: Value(tmdbId),
        tmdbName: Value(name),
        tmdbPosterPath: Value(posterPath),
        mediaType:
            mediaType == null ? const Value.absent() : Value(mediaType),
      ),
    );
  }

  @override
  Future<void> setKeep(int id, bool keep) async {
    await (_db.update(_db.libraryItems)..where((t) => t.id.equals(id)))
        .write(LibraryItemsCompanion(keep: Value(keep)));
  }

  @override
  Future<void> markMissing(int id) async {
    await (_db.update(_db.libraryItems)..where((t) => t.id.equals(id)))
        .write(const LibraryItemsCompanion(missing: Value(true)));
  }
}
