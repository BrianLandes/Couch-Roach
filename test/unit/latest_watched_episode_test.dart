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
    bool completed = true,
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
            completed: Value(completed),
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
    expect(silo.lastWatchedAt, DateTime(2026, 1, 2)); // the furthest ep's watch
  });

  test('counts only finished episodes, not in-progress ones', () async {
    await watchedEpisode(
        tmdbId: 3, name: 'Show', season: 1, episode: 2,
        at: DateTime(2026, 1, 1), completed: true);
    // A later episode only *started* (e.g. the next-episode seed) — not finished.
    await watchedEpisode(
        tmdbId: 3, name: 'Show', season: 1, episode: 3,
        at: DateTime(2026, 1, 2), completed: false);

    final show = (await repo.latestWatchedEpisodePerShow()).single;
    expect(show.episode, 2); // furthest *finished*, not the started E3
    expect(show.lastWatchedAt, DateTime(2026, 1, 1));
  });

  test('a show with no finished episodes is excluded', () async {
    await watchedEpisode(
        tmdbId: 4, name: 'Started', season: 1, episode: 1,
        at: DateTime(2026, 1, 1), completed: false);

    expect(await repo.latestWatchedEpisodePerShow(), isEmpty);
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
            completed: const Value(true),
          ),
        );

    expect(await repo.latestWatchedEpisodePerShow(), isEmpty);
  });
}
