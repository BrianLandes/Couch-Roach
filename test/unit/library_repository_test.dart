import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
  });
  tearDown(() async => db.close());

  ScannedFile movie(String path, String title) =>
      ScannedFile(filePath: path, title: title, mediaType: 'movie');

  test('upsert inserts, then dedupes on file_path and refreshes fields', () async {
    await repo.upsert(movie('/m/a.mkv', 'A'));
    await repo.upsert(movie('/m/a.mkv', 'A (better title)'));

    final all = await repo.getAll();
    expect(all.length, 1);
    expect(all.single.title, 'A (better title)');
    expect(all.single.tmdbId, isNull); // stays null until M2
  });

  test('upsertAll batches a whole scan', () async {
    await repo.upsertAll([
      movie('/m/a.mkv', 'A'),
      const ScannedFile(
          filePath: '/tv/s.S01E02.mkv',
          title: 'S',
          mediaType: 'tv',
          season: 1,
          episode: 2),
    ]);
    expect((await repo.getAll()).length, 2);
  });

  test('markMissingUnder flags gone files scoped to one root only', () async {
    await repo.upsertAll([
      movie('/disk1/a.mkv', 'A'),
      movie('/disk1/b.mkv', 'B'),
      movie('/disk2/c.mkv', 'C'),
    ]);

    // Rescan of disk1 finds only a.mkv (b was deleted); disk2 wasn't scanned.
    final flagged = await repo.markMissingUnder(
      rootPath: '/disk1',
      presentPaths: {'/disk1/a.mkv'},
    );
    expect(flagged, 1);

    final present = (await repo.watchPresent().first).map((e) => e.filePath);
    expect(present, containsAll(['/disk1/a.mkv', '/disk2/c.mkv']));
    expect(present, isNot(contains('/disk1/b.mkv')));
  });

  test('re-upsert clears the missing flag', () async {
    await repo.upsert(movie('/d/a.mkv', 'A'));
    await repo.markMissingUnder(rootPath: '/d', presentPaths: const {});
    expect((await repo.getAll()).single.missing, isTrue);

    await repo.upsert(movie('/d/a.mkv', 'A'));
    expect((await repo.getAll()).single.missing, isFalse);
  });

  test('findByPath and removeByPath', () async {
    await repo.upsert(movie('/d/a.mkv', 'A'));
    expect(await repo.findByPath('/d/a.mkv'), isNotNull);

    await repo.removeByPath('/d/a.mkv');
    expect(await repo.findByPath('/d/a.mkv'), isNull);
  });
}
