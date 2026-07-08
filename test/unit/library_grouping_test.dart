import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/features/library/library_grouping.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add({
    required String mediaType,
    required String title,
    required String filePath,
    int? tmdbId,
    String? tmdbName,
    String? tmdbPosterPath,
    int? season,
    int? episode,
  }) =>
      db.into(db.libraryItems).insert(LibraryItemsCompanion.insert(
            mediaType: mediaType,
            title: title,
            filePath: filePath,
            tmdbId: Value(tmdbId),
            tmdbName: Value(tmdbName),
            tmdbPosterPath: Value(tmdbPosterPath),
            season: Value(season),
            episode: Value(episode),
          ));

  Future<List<LibraryEntry>> grouped() async =>
      groupLibraryItems(await db.select(db.libraryItems).get());

  test("collapses a matched show's episodes into one ShowEntry", () async {
    await add(
        mediaType: 'tv',
        title: 'Silo S01E01',
        tmdbId: 125988,
        tmdbName: 'Silo',
        tmdbPosterPath: '/s.jpg',
        season: 1,
        episode: 1,
        filePath: '/a');
    // Second episode: no poster on this row — the group should still find one.
    await add(
        mediaType: 'tv',
        title: 'Silo S01E02',
        tmdbId: 125988,
        tmdbName: 'Silo',
        season: 1,
        episode: 2,
        filePath: '/b');

    final show = (await grouped()).single as ShowEntry;
    expect(show.tmdbId, 125988);
    expect(show.name, 'Silo');
    expect(show.posterPath, '/s.jpg');
    expect(show.episodeCount, 2);
  });

  test('movies and unmatched files stay individual items', () async {
    await add(mediaType: 'movie', title: 'Fight Club', tmdbId: 550, filePath: '/m');
    // A TV file with no tmdbId (unmatched) is not grouped.
    await add(mediaType: 'tv', title: 'Unmatched S01E01', filePath: '/u');

    final entries = await grouped();
    expect(entries.whereType<ItemEntry>(), hasLength(2));
    expect(entries.whereType<ShowEntry>(), isEmpty);
  });

  test('a show slots where its first episode appears (stable order)', () async {
    await add(mediaType: 'movie', title: 'A', tmdbId: 1, filePath: '/1');
    await add(
        mediaType: 'tv',
        title: 'Show E1',
        tmdbId: 99,
        tmdbName: 'Show',
        season: 1,
        episode: 1,
        filePath: '/2');
    await add(mediaType: 'movie', title: 'B', tmdbId: 2, filePath: '/3');
    await add(
        mediaType: 'tv',
        title: 'Show E2',
        tmdbId: 99,
        tmdbName: 'Show',
        season: 1,
        episode: 2,
        filePath: '/4');

    final entries = await grouped();
    expect(entries, hasLength(3));
    expect((entries[0] as ItemEntry).item.title, 'A');
    expect((entries[1] as ShowEntry).name, 'Show');
    expect((entries[2] as ItemEntry).item.title, 'B');
  });
}
