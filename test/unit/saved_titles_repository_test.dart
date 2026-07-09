import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/saved_titles_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SavedTitlesRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftSavedTitlesRepository(db);
  });
  tearDown(() async => db.close());

  test('favoriting adds to Favorites but not Want-to-watch', () async {
    await repo.setFavorite(
        tmdbId: 1, mediaType: 'tv', name: 'Silo', posterPath: '/p.jpg', value: true);

    final favs = await repo.watchFavorites().first;
    expect(favs.map((s) => s.tmdbId), [1]);
    expect(favs.single.name, 'Silo');
    expect(await repo.watchWantToWatch().first, isEmpty);
  });

  test('a title can be on both lists independently', () async {
    await repo.setFavorite(tmdbId: 7, mediaType: 'movie', name: 'Dune', value: true);
    await repo.setWantToWatch(
        tmdbId: 7, mediaType: 'movie', name: 'Dune', value: true);

    expect((await repo.watchFavorites().first).map((s) => s.tmdbId), [7]);
    expect((await repo.watchWantToWatch().first).map((s) => s.tmdbId), [7]);

    // Removing one leaves the other.
    await repo.setFavorite(tmdbId: 7, mediaType: 'movie', name: 'Dune', value: false);
    expect(await repo.watchFavorites().first, isEmpty);
    expect((await repo.watchWantToWatch().first).map((s) => s.tmdbId), [7]);
  });

  test('clearing both flags deletes the row', () async {
    await repo.setWantToWatch(tmdbId: 9, mediaType: 'tv', name: 'X', value: true);
    await repo.setWantToWatch(tmdbId: 9, mediaType: 'tv', name: 'X', value: false);

    expect(await repo.watchTitle(tmdbId: 9, mediaType: 'tv').first, isNull);
  });

  test('movie and tv with the same tmdbId are distinct rows', () async {
    await repo.setFavorite(tmdbId: 5, mediaType: 'tv', name: 'Show 5', value: true);
    await repo.setFavorite(
        tmdbId: 5, mediaType: 'movie', name: 'Movie 5', value: true);

    final favs = await repo.watchFavorites().first;
    expect(favs.length, 2);
    expect(favs.map((s) => s.mediaType).toSet(), {'tv', 'movie'});
  });

  test('watchTitle reflects the current flags', () async {
    expect(await repo.watchTitle(tmdbId: 2, mediaType: 'tv').first, isNull);

    await repo.setFavorite(tmdbId: 2, mediaType: 'tv', name: 'A', value: true);
    final saved = await repo.watchTitle(tmdbId: 2, mediaType: 'tv').first;
    expect(saved, isNotNull);
    expect(saved!.favoritedAt, isNotNull);
    expect(saved.wantToWatchAt, isNull);
  });

  test('re-favoriting keeps the original timestamp (stable ordering)', () async {
    await repo.setFavorite(tmdbId: 3, mediaType: 'tv', name: 'A', value: true);
    final first = (await repo.watchTitle(tmdbId: 3, mediaType: 'tv').first)!
        .favoritedAt;

    // Toggle want on/off; the favorite timestamp must not move.
    await repo.setWantToWatch(tmdbId: 3, mediaType: 'tv', name: 'A', value: true);
    await repo.setWantToWatch(tmdbId: 3, mediaType: 'tv', name: 'A', value: false);

    final again = (await repo.watchTitle(tmdbId: 3, mediaType: 'tv').first)!
        .favoritedAt;
    expect(again, first);
  });
}
