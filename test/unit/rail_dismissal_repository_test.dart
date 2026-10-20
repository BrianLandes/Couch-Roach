import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/rail_dismissal_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RailDismissalRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftRailDismissalRepository(db);
  });
  tearDown(() => db.close());

  test('a dismissal shows up for its lane, keyed mediaType:tmdbId', () async {
    await repo.dismiss(rail: 'newEpisodes', tmdbId: 42, mediaType: 'tv');
    final map = await repo.watch('newEpisodes').first;
    expect(map.keys, ['tv:42']);
  });

  test('lanes are independent', () async {
    await repo.dismiss(rail: 'newEpisodes', tmdbId: 42, mediaType: 'tv');
    expect(await repo.watch('recent').first, isEmpty);
  });

  test('re-dismissing refreshes the time rather than duplicating', () async {
    await repo.dismiss(rail: 'recent', tmdbId: 1, mediaType: 'movie');
    final first = (await repo.watch('recent').first)['movie:1']!;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.dismiss(rail: 'recent', tmdbId: 1, mediaType: 'movie');
    final map = await repo.watch('recent').first;
    expect(map, hasLength(1));
    expect(map['movie:1']!.isBefore(first), isFalse);
  });

  test('restore removes only that lane\'s entry', () async {
    await repo.dismiss(rail: 'recent', tmdbId: 7, mediaType: 'tv');
    await repo.dismiss(rail: 'newEpisodes', tmdbId: 7, mediaType: 'tv');
    await repo.restore(rail: 'recent', tmdbId: 7, mediaType: 'tv');
    expect(await repo.watch('recent').first, isEmpty);
    expect((await repo.watch('newEpisodes').first).keys, ['tv:7']);
  });
}
