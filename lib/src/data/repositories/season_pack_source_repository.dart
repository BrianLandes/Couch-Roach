import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../db/database.dart';

/// Remembers the whole-season pack torrent chosen for a show's season, so
/// downloading other episodes of that season reuses the same pack instead of
/// re-searching — persisted, so the reuse survives a restart or the pack leaving
/// the torrent client. Keyed by TMDB show id + season number.
abstract class SeasonPackSourceRepository {
  /// The remembered pack for [tmdbId]/[season], or null if none.
  Future<SeasonPackSource?> find(int tmdbId, int season);

  /// Remember (or replace) the pack chosen for [tmdbId]/[season].
  Future<void> remember({
    required int tmdbId,
    required int season,
    required String downloadUrl,
    String? displayName,
  });

  /// Drop the remembered pack for [tmdbId]/[season] — used when the user "tries
  /// another source" off it, so it isn't reused again.
  Future<void> forget(int tmdbId, int season);
}

@LazySingleton(as: SeasonPackSourceRepository)
class DriftSeasonPackSourceRepository implements SeasonPackSourceRepository {
  DriftSeasonPackSourceRepository(this._db);

  final AppDatabase _db;

  @override
  Future<SeasonPackSource?> find(int tmdbId, int season) {
    return (_db.select(_db.seasonPackSources)
          ..where((t) => t.tmdbId.equals(tmdbId) & t.season.equals(season)))
        .getSingleOrNull();
  }

  @override
  Future<void> remember({
    required int tmdbId,
    required int season,
    required String downloadUrl,
    String? displayName,
  }) async {
    await _db.into(_db.seasonPackSources).insertOnConflictUpdate(
          SeasonPackSourcesCompanion.insert(
            tmdbId: tmdbId,
            season: season,
            downloadUrl: downloadUrl,
            displayName: Value(displayName),
          ),
        );
  }

  @override
  Future<void> forget(int tmdbId, int season) async {
    await (_db.delete(_db.seasonPackSources)
          ..where((t) => t.tmdbId.equals(tmdbId) & t.season.equals(season)))
        .go();
  }
}
