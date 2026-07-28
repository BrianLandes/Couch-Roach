import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/season_pack_source_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SeasonPackSourceRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftSeasonPackSourceRepository(db);
  });
  tearDown(() async => db.close());

  test('remembers a pack and finds it back', () async {
    expect(await repo.find(1399, 1), isNull);

    await repo.remember(
        tmdbId: 1399,
        season: 1,
        downloadUrl: 'magnet:pack-s1',
        displayName: 'Show S01 1080p');

    final row = await repo.find(1399, 1);
    expect(row, isNotNull);
    expect(row!.downloadUrl, 'magnet:pack-s1');
    expect(row.displayName, 'Show S01 1080p');
  });

  test('remember replaces the pack for the same show+season', () async {
    await repo.remember(tmdbId: 1399, season: 1, downloadUrl: 'magnet:old');
    await repo.remember(
        tmdbId: 1399, season: 1, downloadUrl: 'magnet:new', displayName: 'New');

    final row = await repo.find(1399, 1);
    expect(row!.downloadUrl, 'magnet:new');
    expect(row.displayName, 'New');
  });

  test('seasons and shows are keyed independently', () async {
    await repo.remember(tmdbId: 1399, season: 1, downloadUrl: 'magnet:s1');
    await repo.remember(tmdbId: 1399, season: 2, downloadUrl: 'magnet:s2');
    await repo.remember(tmdbId: 42, season: 1, downloadUrl: 'magnet:other-s1');

    expect((await repo.find(1399, 1))!.downloadUrl, 'magnet:s1');
    expect((await repo.find(1399, 2))!.downloadUrl, 'magnet:s2');
    expect((await repo.find(42, 1))!.downloadUrl, 'magnet:other-s1');
  });

  test('forget drops one show+season only', () async {
    await repo.remember(tmdbId: 1399, season: 1, downloadUrl: 'magnet:s1');
    await repo.remember(tmdbId: 1399, season: 2, downloadUrl: 'magnet:s2');

    await repo.forget(1399, 1);

    expect(await repo.find(1399, 1), isNull);
    expect(await repo.find(1399, 2), isNotNull); // untouched
  });
}
