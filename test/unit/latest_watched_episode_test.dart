import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftWatchHistoryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftWatchHistoryRepository(db);
  });
  tearDown(() => db.close());

  Future<void> watchedEpisode({
    required int tmdbId,
    required String name,
    required int season,
    required int episode,
    required DateTime at,
    String? poster,
  }) async {
    final id = await db.into(db.libraryItems).insert(
          LibraryItemsCompanion.insert(
            mediaType: 'tv',
            title: name,
            filePath: '/f/$tmdbId-$season-$episode',
            tmdbId: Value(tmdbId),
            tmdbName: Value(name),
            tmdbPosterPath: Value(poster),
            season: Value(season),
            episode: Value(episode),
          ),
        );
    await db.into(db.watchHistory).insert(
          WatchHistoryCompanion.insert(
            libraryItemId: id,
            lastWatchedAt: Value(at),
          ),
        );
  }

  test('keeps the furthest-watched episode per show', () async {
    await watchedEpisode(
        tmdbId: 1, name: 'Silo', season: 1, episode: 2, at: DateTime(2026, 1, 1));
    await watchedEpisode(
        tmdbId: 1,
        name: 'Silo',
        season: 1,
        episode: 5,
        at: DateTime(2026, 1, 2),
        poster: '/s.jpg');
    await watchedEpisode(
        tmdbId: 2, name: 'Other', season: 2, episode: 1, at: DateTime(2026, 1, 3));

    final shows = await repo.latestWatchedEpisodePerShow();
    expect(shows, hasLength(2));

    final silo = shows.firstWhere((s) => s.tmdbId == 1);
    expect(silo.season, 1);
    expect(silo.episode, 5); // the furthest, not the earlier E2
    expect(silo.posterPath, '/s.jpg');
  });

  test('excludes watched movies', () async {
    final movieId = await db.into(db.libraryItems).insert(
          LibraryItemsCompanion.insert(
            mediaType: 'movie',
            title: 'Film',
            filePath: '/m',
            tmdbId: const Value(9),
          ),
        );
    await db.into(db.watchHistory).insert(
          WatchHistoryCompanion.insert(
            libraryItemId: movieId,
            lastWatchedAt: Value(DateTime(2026, 1, 1)),
          ),
        );

    expect(await repo.latestWatchedEpisodePerShow(), isEmpty);
  });
}
