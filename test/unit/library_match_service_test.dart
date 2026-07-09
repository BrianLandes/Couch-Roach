import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/features/library/library_match_service.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository library;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = DriftLibraryRepository(db);
  });
  tearDown(() async => db.close());

  // NOTE: matchUnmatched() early-returns when no TMDB key is set. These tests
  // exercise the repository + client wiring directly (which don't gate on the
  // key) so they run without a --dart-define.
  LibraryMatchService serviceFor(MockClient mock) => LibraryMatchService(
        library,
        TmdbClient(mock, ErrorLogService()),
        ErrorLogService(),
      );

  test('unmatched returns only rows without a tmdb id', () async {
    await library.upsert(const ScannedFile(
        filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));
    await library.upsert(const ScannedFile(
        filePath: '/m/b.mkv', title: 'B', mediaType: 'movie'));
    final aId = (await library.findByPath('/m/a.mkv'))!.id;
    await library.setTmdbMatch(id: aId, tmdbId: 111, name: 'A!', posterPath: '/p.jpg');

    final unmatched = await library.unmatched();
    expect(unmatched.map((e) => e.filePath), ['/m/b.mkv']);
  });

  test('setTmdbMatch caches id, name, and poster on the row', () async {
    await library.upsert(const ScannedFile(
        filePath: '/tv/s.S01E01.mkv',
        title: 'The Show',
        mediaType: 'tv',
        season: 1,
        episode: 1));
    final id = (await library.findByPath('/tv/s.S01E01.mkv'))!.id;

    // Drive the client directly with a canned TMDB search result and apply it.
    final client = TmdbClient(
      MockClient((req) async => http.Response(
          jsonEncode({
            'results': [
              {'id': 4242, 'name': 'The Show', 'poster_path': '/show.jpg'},
            ],
          }),
          200)),
      ErrorLogService(),
    );
    final results = await client.searchTv('The Show');
    await library.setTmdbMatch(
      id: id,
      tmdbId: results.first.tmdbId,
      name: results.first.name,
      posterPath: results.first.posterPath,
    );

    final row = (await library.getAll()).single;
    expect(row.tmdbId, 4242);
    expect(row.tmdbName, 'The Show');
    expect(row.tmdbPosterPath, '/show.jpg');
    expect(await library.unmatched(), isEmpty);
  });

  test('service constructs and no-ops without a TMDB key', () async {
    // No --dart-define in tests, so matchUnmatched() should return immediately.
    final service = serviceFor(MockClient((_) async => http.Response('{}', 404)));
    await library.upsert(const ScannedFile(
        filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));
    await service.matchUnmatched();
    expect((await library.getAll()).single.tmdbId, isNull);
  });

  test('matchItem no-ops without a TMDB key (and tolerates a missing id)',
      () async {
    final service = serviceFor(MockClient((_) async => http.Response('{}', 404)));
    await library.upsert(const ScannedFile(
        filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));
    final id = (await library.findByPath('/m/a.mkv'))!.id;

    // Real id and a never-registered id both return cleanly, leaving the row
    // untouched (the happy path needs a TMDB key, verified on-device).
    await service.matchItem(id);
    await service.matchItem(999999);
    expect((await library.getAll()).single.tmdbId, isNull);
  });
}
