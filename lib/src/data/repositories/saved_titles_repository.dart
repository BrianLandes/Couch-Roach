import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../db/database.dart';

/// Persists the user's Favorites and Want-to-watch lists (TMDB shows/movies).
/// Both are backed by one row per title with a nullable timestamp per list — set
/// means "on the list" (and orders it newest-first), null means off. A title
/// with both timestamps null is deleted.
abstract class SavedTitlesRepository {
  /// Favorites, newest-favorited first.
  Stream<List<SavedTitle>> watchFavorites();

  /// Want-to-watch, newest-added first.
  Stream<List<SavedTitle>> watchWantToWatch();

  /// Live saved-state for a single title (its favorite / want-to-watch flags),
  /// so a detail page's toggle buttons reflect the current state. Emits null
  /// when the title is on neither list.
  Stream<SavedTitle?> watchTitle({
    required int tmdbId,
    required String mediaType,
  });

  /// Add or remove [tmdbId]/[mediaType] from Favorites. [name]/[posterPath] are
  /// cached on the row for offline tile rendering.
  Future<void> setFavorite({
    required int tmdbId,
    required String mediaType,
    required String name,
    String? posterPath,
    required bool value,
  });

  /// Add or remove [tmdbId]/[mediaType] from Want-to-watch.
  Future<void> setWantToWatch({
    required int tmdbId,
    required String mediaType,
    required String name,
    String? posterPath,
    required bool value,
  });
}

@LazySingleton(as: SavedTitlesRepository)
class DriftSavedTitlesRepository implements SavedTitlesRepository {
  DriftSavedTitlesRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<SavedTitle>> watchFavorites() {
    return (_db.select(_db.savedTitles)
          ..where((t) => t.favoritedAt.isNotNull())
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.favoritedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  @override
  Stream<List<SavedTitle>> watchWantToWatch() {
    return (_db.select(_db.savedTitles)
          ..where((t) => t.wantToWatchAt.isNotNull())
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.wantToWatchAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  @override
  Stream<SavedTitle?> watchTitle({
    required int tmdbId,
    required String mediaType,
  }) {
    return (_db.select(_db.savedTitles)
          ..where((t) => t.tmdbId.equals(tmdbId) & t.mediaType.equals(mediaType)))
        .watchSingleOrNull();
  }

  @override
  Future<void> setFavorite({
    required int tmdbId,
    required String mediaType,
    required String name,
    String? posterPath,
    required bool value,
  }) {
    return _apply(
      tmdbId: tmdbId,
      mediaType: mediaType,
      name: name,
      posterPath: posterPath,
      favorite: value,
    );
  }

  @override
  Future<void> setWantToWatch({
    required int tmdbId,
    required String mediaType,
    required String name,
    String? posterPath,
    required bool value,
  }) {
    return _apply(
      tmdbId: tmdbId,
      mediaType: mediaType,
      name: name,
      posterPath: posterPath,
      want: value,
    );
  }

  /// Flip one list flag while preserving the other. Turning a flag on stamps
  /// `now` (only if it wasn't already set, so ordering is stable across
  /// re-saves); turning it off nulls it. When both end up null the row is
  /// removed entirely rather than left as a tombstone.
  Future<void> _apply({
    required int tmdbId,
    required String mediaType,
    required String name,
    String? posterPath,
    bool? favorite,
    bool? want,
  }) async {
    final existing = await (_db.select(_db.savedTitles)
          ..where((t) => t.tmdbId.equals(tmdbId) & t.mediaType.equals(mediaType)))
        .getSingleOrNull();

    final now = DateTime.now();
    var favoritedAt = existing?.favoritedAt;
    var wantAt = existing?.wantToWatchAt;
    if (favorite != null) favoritedAt = favorite ? (favoritedAt ?? now) : null;
    if (want != null) wantAt = want ? (wantAt ?? now) : null;

    if (favoritedAt == null && wantAt == null) {
      await (_db.delete(_db.savedTitles)
            ..where((t) =>
                t.tmdbId.equals(tmdbId) & t.mediaType.equals(mediaType)))
          .go();
      return;
    }

    await _db.into(_db.savedTitles).insertOnConflictUpdate(
          SavedTitlesCompanion.insert(
            tmdbId: tmdbId,
            mediaType: mediaType,
            name: name,
            posterPath: Value(posterPath),
            favoritedAt: Value(favoritedAt),
            wantToWatchAt: Value(wantAt),
          ),
        );
  }
}
