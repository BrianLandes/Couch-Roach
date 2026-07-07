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
