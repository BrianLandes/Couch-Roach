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
    this.managed = false,
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

  /// True when the app acquired this file (torrent / archive), false for a plain
  /// disk scan of a file already in a library folder. Stamped on insert and
  /// preserved across later rescans; powers the "Recently Downloaded" rail.
  final bool managed;
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

  /// Recently-downloaded titles for the landing "Recently Downloaded" rail: the
  /// newest [limit] app-acquired (`managed`), present titles — collapsed to one
  /// entry per show (matched `tmdbId` + media type, else the clean title) keeping
  /// each show's most-recent file, ordered by `addedAt` newest-first — with
  /// **titles watched since they were downloaded excluded** (those live on
  /// Continue Watching / are done). No time limit: a title stays until it's
  /// watched. Live — updates as downloads land and as titles get watched.
  Stream<List<LibraryItem>> watchRecentlyDownloaded({int limit});

  /// Every row including missing ones. Live.
  Stream<List<LibraryItem>> watchAll();

  Future<List<LibraryItem>> getAll();
  Future<LibraryItem?> findByPath(String path);
  Future<LibraryItem?> findById(int id);

  /// Persist the user's subtitle timing offset (ms) for a title, applied as
  /// mpv's `sub-delay` on playback. Kept per file so a re-watch stays corrected.
  Future<void> setSubtitleOffset(int id, int offsetMs);

  /// Persist the user's *manual* audio-track choice (a libmpv track id) for a
  /// file, restored on the next play and overriding the auto-pick. Null clears
  /// it (back to auto).
  Future<void> setPreferredAudioTrack(int id, String? trackId);

  /// Persist the user's *manual* subtitle-track choice (a libmpv track id, or
  /// `'no'` for off) for a file, restored on the next play and overriding the
  /// auto-English pick. Null clears it (back to auto).
  Future<void> setPreferredSubtitleTrack(int id, String? trackId);

  /// Present items not yet matched to a TMDB id (for back-fill).
  Future<List<LibraryItem>> unmatched();

  /// All present local files matched to a show (for episode availability).
  /// One-shot — for imperative callers (the player's next-episode lookup,
  /// prefetch). UI should use [watchLocalEpisodes] instead.
  Future<List<LibraryItem>> localEpisodes(int tmdbId);

  /// Live [localEpisodes]. A detail page left open while a season downloads has
  /// to flip each episode row to "Play" as its file lands, so what's on disk is
  /// reactive state, not a value fetched once when the page opened.
  Stream<List<LibraryItem>> watchLocalEpisodes(int tmdbId);

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

  /// Pin/unpin a single title (a movie / loose file) as "keep" — exempt from
  /// auto-cleanup even after a full watch (see DECISIONS: auto-cleanup). A whole
  /// matched *show* is pinned instead via `SavedTitlesRepository.setKeep`, which
  /// is per-show (tmdbId) so it also covers episodes acquired after pinning.
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
        managed: Value(f.managed),
      );

  // On conflict we refresh only the scan-derived fields (and clear `missing`);
  // keep / addedAt are preserved. The TMDB identity is stamped only when this
  // file carries one (an acquire): a plain scan has no tmdbId and must never
  // clobber an existing match. `managed` is likewise one-way — an acquire sets
  // it true (even if a scan inserted the row first), and a later plain scan
  // never clears it.
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
        managed: f.managed ? const Value(true) : const Value.absent(),
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
  Stream<List<LibraryItem>> watchRecentlyDownloaded({int limit = 20}) {
    // Join watch history so the query is reactive to *both* new downloads and
    // titles getting watched (a left join keeps not-yet-watched downloads). No
    // time window — the newest [limit] unwatched downloads stay until watched.
    final query = _db.select(_db.libraryItems).join([
      leftOuterJoin(
        _db.watchHistory,
        _db.watchHistory.libraryItemId.equalsExp(_db.libraryItems.id),
      ),
    ])
      ..where(_db.libraryItems.managed.equals(true) &
          _db.libraryItems.missing.equals(false))
      ..orderBy([
        OrderingTerm(
            expression: _db.libraryItems.addedAt, mode: OrderingMode.desc),
      ]);
    return query.watch().map((rows) {
      final paired = [
        for (final row in rows)
          (
            item: row.readTable(_db.libraryItems),
            history: row.readTableOrNull(_db.watchHistory),
          ),
      ];
      return _collapseUnwatched(paired, limit);
    });
  }

  /// Show identity for the Recently-Downloaded collapse: matched titles group by
  /// `'<mediaType>:<tmdbId>'` (so a show's several fresh episodes fold to one
  /// entry, and movie/tv id namespaces never collide); an unmatched file falls
  /// back to its clean lowercased title.
  String _showKey(LibraryItem i) => i.tmdbId != null
      ? '${i.mediaType}:${i.tmdbId}'
      : 'title:${i.title.toLowerCase()}';

  /// Collapse recent downloads to one newest entry per show, dropping any show
  /// **watched since it was downloaded** — a file counts as watched-since when it
  /// has watch history stamped at/after its own `addedAt` (so an old, since-reaped
  /// title that's freshly re-downloaded still shows: its old history predates the
  /// new download). [rows] arrive newest-first; result is capped to [limit].
  List<LibraryItem> _collapseUnwatched(
    List<({LibraryItem item, WatchHistoryData? history})> rows,
    int limit,
  ) {
    // A show is out if any of its within-window downloads was watched since it
    // arrived.
    final watchedSince = <String>{};
    for (final r in rows) {
      final h = r.history;
      if (h != null && !h.lastWatchedAt.isBefore(r.item.addedAt)) {
        watchedSince.add(_showKey(r.item));
      }
    }

    final seen = <String>{};
    final out = <LibraryItem>[];
    for (final r in rows) {
      final key = _showKey(r.item);
      if (watchedSince.contains(key)) continue;
      if (seen.add(key)) {
        out.add(r.item);
        if (out.length >= limit) break;
      }
    }
    return out;
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
  Future<void> setPreferredAudioTrack(int id, String? trackId) async {
    await (_db.update(_db.libraryItems)..where((t) => t.id.equals(id)))
        .write(LibraryItemsCompanion(preferredAudioTrackId: Value(trackId)));
  }

  @override
  Future<void> setPreferredSubtitleTrack(int id, String? trackId) async {
    await (_db.update(_db.libraryItems)..where((t) => t.id.equals(id)))
        .write(LibraryItemsCompanion(preferredSubtitleTrackId: Value(trackId)));
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
  Future<List<LibraryItem>> localEpisodes(int tmdbId) =>
      _localEpisodesQuery(tmdbId).get();

  @override
  Stream<List<LibraryItem>> watchLocalEpisodes(int tmdbId) =>
      _localEpisodesQuery(tmdbId).watch();

  /// The one query behind both, so the live and one-shot views can never drift
  /// apart on what counts as "on disk".
  SimpleSelectStatement<$LibraryItemsTable, LibraryItem> _localEpisodesQuery(
          int tmdbId) =>
      _db.select(_db.libraryItems)
        ..where((t) => t.tmdbId.equals(tmdbId) & t.missing.equals(false));

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
