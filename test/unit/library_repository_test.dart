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

  test('an acquire-sourced file stamps its known TMDB identity on insert',
      () async {
    // The acquire flow knows the id up front, so the row is matched immediately
    // (no async race) — this is what makes the next-episode gate work.
    await repo.upsert(const ScannedFile(
      filePath: '/tv/show.S02E05.mkv',
      title: 'Show — S02E05',
      mediaType: 'tv',
      season: 2,
      episode: 5,
      tmdbId: 42,
      tmdbName: 'Show',
    ));

    final row = (await repo.getAll()).single;
    expect(row.tmdbId, 42);
    expect(row.tmdbName, 'Show');
    // Matched rows are queryable as local episodes for the show.
    expect(await repo.localEpisodes(42), hasLength(1));
  });

  test('a plain scan never clobbers an existing TMDB match', () async {
    // First, an acquire stamps the match.
    await repo.upsert(const ScannedFile(
      filePath: '/tv/show.S02E05.mkv',
      title: 'Show — S02E05',
      mediaType: 'tv',
      season: 2,
      episode: 5,
      tmdbId: 42,
      tmdbName: 'Show',
    ));
    // Then a later disk scan re-upserts the same path carrying no id.
    await repo.upsert(const ScannedFile(
      filePath: '/tv/show.S02E05.mkv',
      title: 'show.S02E05',
      mediaType: 'tv',
      season: 2,
      episode: 5,
    ));

    final row = (await repo.getAll()).single;
    expect(row.tmdbId, 42, reason: 'scan must preserve the match');
    expect(row.tmdbName, 'Show');
  });
}
