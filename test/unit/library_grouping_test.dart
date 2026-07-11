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

  Future<List<LibraryEntry>> grouped({Set<String> rootPaths = const {}}) async =>
      groupLibraryItems(await db.select(db.libraryItems).get(),
          rootPaths: rootPaths);

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

  test('folds 2+ unmatched episodes of one folder into an UnmatchedShowEntry',
      () async {
    await add(
        mediaType: 'tv',
        title: 'Dark',
        filePath: '/tv/Dark/Season 1/01.mkv',
        season: 1,
        episode: 1);
    await add(
        mediaType: 'tv',
        title: 'Dark',
        filePath: '/tv/Dark/Season 1/02.mkv',
        season: 1,
        episode: 2);

    final entries = await grouped();
    final unmatched = entries.whereType<UnmatchedShowEntry>().single;
    expect(unmatched.name, 'Dark');
    expect(unmatched.episodeCount, 2);
    expect(entries.whereType<ItemEntry>(), isEmpty);
  });

  test('folds 2+ unmatched *movie*-parsed files of one folder (foreign title)',
      () async {
    // An obscure/foreign show the parser couldn't tell was TV (no SxxExx, no
    // season folder) — its files parse as movies but share a folder, so the
    // last-resort fold still groups them.
    await add(
        mediaType: 'movie',
        title: 'Estranha 01',
        filePath: '/media/Serie Estranha/01.mkv');
    await add(
        mediaType: 'movie',
        title: 'Estranha 02',
        filePath: '/media/Serie Estranha/02.mkv');

    final entries = await grouped();
    final unmatched = entries.whereType<UnmatchedShowEntry>().single;
    expect(unmatched.name, 'Serie Estranha');
    expect(unmatched.episodeCount, 2);
    expect(entries.whereType<ItemEntry>(), isEmpty);
  });

  test('does not fold unmatched files sitting loose in a library root',
      () async {
    // Two unrelated films dumped directly in a root share the root folder, but
    // that isn't a show folder — they must stay separate tiles.
    await add(mediaType: 'movie', title: 'Film A', filePath: '/media/a.mkv');
    await add(mediaType: 'movie', title: 'Film B', filePath: '/media/b.mkv');

    final entries = await grouped(rootPaths: {'/media'});
    expect(entries.whereType<UnmatchedShowEntry>(), isEmpty);
    expect(entries.whereType<ItemEntry>(), hasLength(2));
  });

  test('a matched movie is never swept into a folder fold', () async {
    // A real, TMDB-matched film shares a folder with an unmatched clip — the
    // matched one keeps its own tile (and detail page); only the unmatched
    // sibling would fold, and a lone file doesn't.
    await add(
        mediaType: 'movie',
        title: 'Fight Club',
        tmdbId: 550,
        filePath: '/media/Fight Club/movie.mkv');
    await add(
        mediaType: 'movie',
        title: 'extra',
        filePath: '/media/Fight Club/extra.mkv');

    final entries = await grouped();
    expect(entries.whereType<ItemEntry>(), hasLength(2));
    expect(entries.whereType<UnmatchedShowEntry>(), isEmpty);
  });

  test('a lone unmatched episode stays an ItemEntry (not folded)', () async {
    await add(
        mediaType: 'tv',
        title: 'Solo',
        filePath: '/tv/Solo/Season 1/01.mkv',
        season: 1,
        episode: 1);

    final entries = await grouped();
    expect(entries.whereType<UnmatchedShowEntry>(), isEmpty);
    expect(entries.whereType<ItemEntry>(), hasLength(1));
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
