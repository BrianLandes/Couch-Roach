import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:drift/drift.dart' show Value;
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

  // Insert a row directly so a test can fix `addedAt` (the repo stamps "now",
  // which isn't distinguishable across rows inserted in the same millisecond).
  Future<void> insertRow(
    String path, {
    required DateTime addedAt,
    String mediaType = 'tv',
    int? tmdbId,
    String? tmdbName,
    int? season,
    int? episode,
    bool managed = true,
    bool missing = false,
  }) async {
    await db.into(db.libraryItems).insert(LibraryItemsCompanion.insert(
          mediaType: mediaType,
          title: path,
          filePath: path,
          tmdbId: Value(tmdbId),
          tmdbName: Value(tmdbName),
          season: Value(season),
          episode: Value(episode),
          managed: Value(managed),
          missing: Value(missing),
          addedAt: Value(addedAt),
        ));
  }

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

  group('watchRecentlyDownloaded', () {
    final t0 = DateTime(2026, 1, 1, 12);

    test('only managed, present files appear', () async {
      await insertRow('/tv/managed.mkv',
          tmdbId: 1, addedAt: t0, managed: true);
      await insertRow('/tv/scanned.mkv',
          tmdbId: 2, addedAt: t0, managed: false); // a plain-scan file
      await insertRow('/tv/gone.mkv',
          tmdbId: 3, addedAt: t0, managed: true, missing: true);

      final rows = await repo.watchRecentlyDownloaded().first;
      expect(rows.map((r) => r.filePath), ['/tv/managed.mkv']);
    });

    test('collapses a show to its newest episode and orders newest-first',
        () async {
      // Show 10: two episodes; the newer one represents the show.
      await insertRow('/tv/show10.S01E01.mkv',
          tmdbId: 10, tmdbName: 'Show 10', season: 1, episode: 1,
          addedAt: t0);
      await insertRow('/tv/show10.S01E02.mkv',
          tmdbId: 10, tmdbName: 'Show 10', season: 1, episode: 2,
          addedAt: t0.add(const Duration(hours: 2)));
      // A movie downloaded in between.
      await insertRow('/movies/film.mkv',
          mediaType: 'movie', tmdbId: 20, tmdbName: 'Film',
          addedAt: t0.add(const Duration(hours: 1)));

      final rows = await repo.watchRecentlyDownloaded().first;
      // One entry per title: Show 10 (via its newest ep) then the movie.
      expect(rows.map((r) => r.tmdbId), [10, 20]);
      expect(rows.first.filePath, '/tv/show10.S01E02.mkv');
    });

    test('a movie and tv show sharing a tmdbId are distinct entries', () async {
      await insertRow('/tv/s.mkv',
          mediaType: 'tv', tmdbId: 5, addedAt: t0);
      await insertRow('/movies/m.mkv',
          mediaType: 'movie', tmdbId: 5,
          addedAt: t0.add(const Duration(hours: 1)));

      final rows = await repo.watchRecentlyDownloaded().first;
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.mediaType).toSet(), {'tv', 'movie'});
    });

    test('limit caps the number of distinct titles', () async {
      for (var i = 0; i < 5; i++) {
        await insertRow('/tv/show$i.mkv',
            tmdbId: 100 + i, addedAt: t0.add(Duration(minutes: i)));
      }
      final rows = await repo.watchRecentlyDownloaded(limit: 3).first;
      expect(rows, hasLength(3));
      // Newest three (minutes 4,3,2).
      expect(rows.map((r) => r.tmdbId), [104, 103, 102]);
    });

    test('an acquire stamps managed even when a scan inserted the row first',
        () async {
      // Plain scan sees the file first (managed defaults false)...
      await repo.upsert(const ScannedFile(
          filePath: '/tv/race.mkv', title: 'race', mediaType: 'tv'));
      expect(await repo.watchRecentlyDownloaded().first, isEmpty);

      // ...then the acquire re-upserts the same path as managed.
      await repo.upsert(const ScannedFile(
        filePath: '/tv/race.mkv',
        title: 'Show — S01E01',
        mediaType: 'tv',
        tmdbId: 77,
        tmdbName: 'Show',
        managed: true,
      ));
      final rows = await repo.watchRecentlyDownloaded().first;
      expect(rows.map((r) => r.tmdbId), [77]);
    });
  });

  test('preferred audio/subtitle track ids persist and clear', () async {
    await repo.upsert(movie('/m/a.mkv', 'A'));
    final id = (await repo.findByPath('/m/a.mkv'))!.id;

    // Default: no manual choice recorded.
    var row = await repo.findById(id);
    expect(row!.preferredAudioTrackId, isNull);
    expect(row.preferredSubtitleTrackId, isNull);

    await repo.setPreferredAudioTrack(id, '2');
    await repo.setPreferredSubtitleTrack(id, 'no'); // subtitles off
    row = await repo.findById(id);
    expect(row!.preferredAudioTrackId, '2');
    expect(row.preferredSubtitleTrackId, 'no');

    // Passing null clears the choice (back to auto).
    await repo.setPreferredAudioTrack(id, null);
    row = await repo.findById(id);
    expect(row!.preferredAudioTrackId, isNull);
    expect(row.preferredSubtitleTrackId, 'no'); // unaffected
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
