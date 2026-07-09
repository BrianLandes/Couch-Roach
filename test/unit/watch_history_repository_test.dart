import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart';
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
}
