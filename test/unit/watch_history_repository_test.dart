import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository library;
  late WatchHistoryRepository history;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = DriftLibraryRepository(db);
    history = DriftWatchHistoryRepository(db);
  });
  tearDown(() async => db.close());

  Future<int> seedItem(String path) async {
    await library.upsert(
        ScannedFile(filePath: path, title: 'T', mediaType: 'movie'));
    return (await library.findByPath(path))!.id;
  }

  test('record inserts then updates a single row per item', () async {
    final id = await seedItem('/m/a.mkv');

    await history.record(
        libraryItemId: id,
        position: const Duration(seconds: 60),
        duration: const Duration(minutes: 90));
    await history.record(
        libraryItemId: id,
        position: const Duration(seconds: 125),
        duration: const Duration(minutes: 90));

    final row = await history.forItem(id);
    expect(row, isNotNull);
    expect(row!.resumePositionSec, 125);
    expect(row.durationSec, 90 * 60);
    expect(row.completed, isFalse);
    // Still one row.
    expect((await history.watchRecent().first).length, 1);
  });

  test('completed clears the resume position', () async {
    final id = await seedItem('/m/a.mkv');
    await history.record(
        libraryItemId: id, position: const Duration(seconds: 800));
    await history.record(
        libraryItemId: id,
        position: const Duration(seconds: 900),
        completed: true);

    final row = await history.forItem(id);
    expect(row!.completed, isTrue);
    expect(row.resumePositionSec, 0);
  });

  test('recentlyWatchedTmdbIds returns distinct matched shows', () async {
    final e1 = await seedItem('/tv/s1e1.mkv');
    final e2 = await seedItem('/tv/s1e2.mkv');
    final e3 = await seedItem('/tv/s2e1.mkv');
    await library.setTmdbMatch(id: e1, tmdbId: 100);
    await library.setTmdbMatch(id: e2, tmdbId: 100); // same show
    await library.setTmdbMatch(id: e3, tmdbId: 200);

    await history.record(libraryItemId: e1, position: const Duration(seconds: 10));
    await history.record(libraryItemId: e3, position: const Duration(seconds: 10));
    await history.record(libraryItemId: e2, position: const Duration(seconds: 10));

    // Unmatched/unwatched shows excluded; ids deduped (drift stores time at
    // second resolution, so assert the set rather than intra-second order).
    final ids = await history.recentlyWatchedTmdbIds(limit: 5);
    expect(ids.toSet(), {100, 200});
    expect(ids.length, 2);
  });

  test('dismissFromContinueWatching drops the item from the rail but keeps '
      'the row and does not mark it completed', () async {
    final id = await seedItem('/m/a.mkv');
    await history.record(
        libraryItemId: id,
        position: const Duration(seconds: 300),
        duration: const Duration(minutes: 90));

    // In the rail to start with.
    expect((await history.watchContinueWatching().first).length, 1);

    await history.dismissFromContinueWatching(id);

    // Gone from the rail (resume cleared)...
    expect(await history.watchContinueWatching().first, isEmpty);
    // ...but the row survives, resume is 0, and it's NOT completed (so the
    // reaper won't touch it and recommendation rails still see the history).
    final row = await history.forItem(id);
    expect(row, isNotNull);
    expect(row!.resumePositionSec, 0);
    expect(row.completed, isFalse);
  });

  test('dismissFromContinueWatching is a no-op when there is no history row',
      () async {
    final id = await seedItem('/m/a.mkv');
    // No record() call — nothing to dismiss.
    await history.dismissFromContinueWatching(id);
    expect(await history.forItem(id), isNull);
  });

  // Seed a TV episode row and return its library id.
  Future<int> seedEpisode(String path,
      {int? tmdbId,
      required int season,
      required int episode,
      String title = 'Show'}) async {
    await library.upsert(ScannedFile(
      filePath: path,
      title: title,
      mediaType: 'tv',
      season: season,
      episode: episode,
      tmdbId: tmdbId,
    ));
    return (await library.findByPath(path))!.id;
  }

  // Force a deterministic last-watched time (record() stamps now() at second
  // resolution, so fast successive records can't be ordered otherwise).
  Future<void> setWatchedAt(int itemId, DateTime when) =>
      (db.update(db.watchHistory)
            ..where((w) => w.libraryItemId.equals(itemId)))
          .write(WatchHistoryCompanion(lastWatchedAt: Value(when)));

  test('continue watching keeps only the most-recent episode per show',
      () async {
    final e1 = await seedEpisode('/tv/s1e1.mkv', tmdbId: 100, season: 1, episode: 1);
    final e2 = await seedEpisode('/tv/s1e2.mkv', tmdbId: 100, season: 1, episode: 2);
    final movie = await seedItem('/m/film.mkv');

    for (final id in [e1, e2, movie]) {
      await history.record(
          libraryItemId: id, position: const Duration(seconds: 120));
    }
    // e2 is the most recently watched episode of show 100.
    await setWatchedAt(e1, DateTime(2026, 1, 1));
    await setWatchedAt(e2, DateTime(2026, 1, 2));
    await setWatchedAt(movie, DateTime(2026, 1, 3));

    final rail = await history.watchContinueWatching().first;
    // Movie (newest) + the single surviving episode of show 100 — e1 collapsed.
    expect(rail.map((e) => e.item.id), [movie, e2]);
  });

  test('advanceToNextEpisode keeps the show on the rail at the next episode',
      () async {
    final e1 = await seedEpisode('/tv/s1e1.mkv', tmdbId: 100, season: 1, episode: 1);
    final e2 = await seedEpisode('/tv/s1e2.mkv', tmdbId: 100, season: 1, episode: 2);

    // An older episode was left half-watched (the one that would wrongly
    // resurface once a later episode is finished + drops off the rail).
    await history.record(
        libraryItemId: e1, position: const Duration(seconds: 120));
    await setWatchedAt(e1, DateTime(2026, 1, 1));

    // Finishing a later episode seeds the next one — which supersedes e1.
    await history.advanceToNextEpisode(e2);

    final rail = await history.watchContinueWatching().first;
    expect(rail.map((e) => e.item.id), [e2]);
    expect(rail.single.resumePositionSec, 1); // near-zero → starts fresh
  });

  test('advanceToNextEpisode never clobbers an episode already in progress',
      () async {
    final e2 = await seedEpisode('/tv/s1e2.mkv', tmdbId: 100, season: 1, episode: 2);
    await history.record(
        libraryItemId: e2, position: const Duration(seconds: 500));

    await history.advanceToNextEpisode(e2); // already watched → no-op

    expect((await history.forItem(e2))!.resumePositionSec, 500);
  });

  test('continue watching does not collapse distinct shows or movies', () async {
    final showA = await seedEpisode('/tv/a.mkv', tmdbId: 100, season: 1, episode: 1);
    final showB = await seedEpisode('/tv/b.mkv', tmdbId: 200, season: 1, episode: 1);
    // Unmatched episodes of two different shows (grouped by clean title).
    final unX = await seedEpisode('/tv/x.mkv', season: 1, episode: 1, title: 'X');
    final unY = await seedEpisode('/tv/y.mkv', season: 1, episode: 1, title: 'Y');
    final movie = await seedItem('/m/film.mkv');

    for (final id in [showA, showB, unX, unY, movie]) {
      await history.record(
          libraryItemId: id, position: const Duration(seconds: 90));
    }

    final rail = await history.watchContinueWatching().first;
    // Nothing shares a show identity, so all five survive.
    expect(rail.map((e) => e.item.id).toSet(), {showA, showB, unX, unY, movie});
  });

  test('watchReapCandidates lists completed, present, unpinned items only',
      () async {
    final done = await seedItem('/m/done.mkv');
    final inProgress = await seedItem('/m/wip.mkv');
    await history.record(
        libraryItemId: done,
        position: const Duration(seconds: 900),
        completed: true);
    await history.record(
        libraryItemId: inProgress, position: const Duration(seconds: 300));

    final queue = await history.watchReapCandidates().first;
    expect(queue.map((c) => c.item.id), [done]);
    // The candidate carries when it was last watched (drives the "deletes in N
    // days" countdown in Settings).
    expect(queue.single.lastWatchedAt, isNotNull);
  });

  test('watchReapCandidates excludes pinned (keep) and missing items',
      () async {
    final kept = await seedItem('/m/kept.mkv');
    final gone = await seedItem('/m/gone.mkv');
    final reapable = await seedItem('/m/reap.mkv');
    for (final id in [kept, gone, reapable]) {
      await history.record(
          libraryItemId: id,
          position: const Duration(seconds: 900),
          completed: true);
    }
    // Pin one and flag another missing — both drop out of the queue.
    await library.setKeep(kept, true);
    await library.markMissing(gone);

    final queue = await history.watchReapCandidates().first;
    expect(queue.map((c) => c.item.id), [reapable]);

    // Pinning a queued item live-removes it from the stream.
    await library.setKeep(reapable, true);
    expect(await history.watchReapCandidates().first, isEmpty);
  });

  test('watch history survives the file disappearing (flag, not delete)', () async {
    final id = await seedItem('/disk1/a.mkv');
    await history.record(
        libraryItemId: id, position: const Duration(seconds: 300));

    // File vanished on a later scan — row is flagged missing, not deleted.
    await library.markMissingUnder(rootPath: '/disk1', presentPaths: const {});

    // The library row and its watch history both survive.
    expect(await library.findByPath('/disk1/a.mkv'), isNotNull);
    final row = await history.forItem(id);
    expect(row, isNotNull);
    expect(row!.resumePositionSec, 300);
  });

  group('watchCompletedEpisodes', () {
    Future<int> seedEpisode(String path,
        {required int tmdbId, required int season, required int episode}) async {
      await library.upsert(ScannedFile(
        filePath: path,
        title: 'Show S${season}E$episode',
        mediaType: 'tv',
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      ));
      return (await library.findByPath(path))!.id;
    }

    test('returns only completed episodes, as (season, episode)', () async {
      final e1 = await seedEpisode('/tv/s1e1.mkv', tmdbId: 9, season: 1, episode: 1);
      final e2 = await seedEpisode('/tv/s1e2.mkv', tmdbId: 9, season: 1, episode: 2);
      await seedEpisode('/tv/s1e3.mkv', tmdbId: 9, season: 1, episode: 3);

      await history.record(
          libraryItemId: e1, position: Duration.zero, completed: true);
      await history.record(
          libraryItemId: e2, position: const Duration(seconds: 90)); // in progress

      final watched = await history.watchCompletedEpisodes(9).first;
      expect(watched, {(1, 1)});
    });

    test('scopes to the requested show', () async {
      final a = await seedEpisode('/tv/a.mkv', tmdbId: 1, season: 2, episode: 4);
      final b = await seedEpisode('/tv/b.mkv', tmdbId: 2, season: 1, episode: 1);
      await history.record(libraryItemId: a, position: Duration.zero, completed: true);
      await history.record(libraryItemId: b, position: Duration.zero, completed: true);

      expect(await history.watchCompletedEpisodes(1).first, {(2, 4)});
      expect(await history.watchCompletedEpisodes(2).first, {(1, 1)});
    });

    test('a watched episode stays marked after its file is reaped', () async {
      final id = await seedEpisode('/tv/reaped.mkv', tmdbId: 5, season: 1, episode: 7);
      await history.record(
          libraryItemId: id, position: Duration.zero, completed: true);

      // File cleaned up — row flagged missing, history kept.
      await library.markMissing(id);

      expect(await history.watchCompletedEpisodes(5).first, {(1, 7)});
    });
  });
}
