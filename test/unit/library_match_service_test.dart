import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/storage/storage_manager.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/features/library/library_match_service.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_app_config.dart';

/// Reports a fixed set of library roots; nothing else on StorageManager is used
/// by the matcher.
class _FakeStorageManager implements StorageManager {
  _FakeStorageManager(this._paths);
  final Set<String> _paths;

  @override
  List<StorageRoot> get roots =>
      [for (final p in _paths) StorageRoot(path: p)];

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

void main() {
  late AppDatabase db;
  late LibraryRepository library;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = DriftLibraryRepository(db);
  });
  tearDown(() async => db.close());

  /// A service wired to a scripted TMDB endpoint. [configured] drives the
  /// `hasTmdbKey` gate: the real config is always empty under `flutter test`,
  /// so the fake is what makes the matching path reachable at all. [roots] are
  /// the configured library roots — a file sitting loose in one of them must not
  /// be searched for by the root's own name.
  LibraryMatchService serviceFor(
    MockClient mock, {
    bool configured = true,
    Set<String> roots = const {},
  }) =>
      LibraryMatchService(
        library,
        TmdbClient(mock, ErrorLogService()),
        ErrorLogService(),
        FakeAppConfig(hasTmdbKey: configured),
        _FakeStorageManager(roots),
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
    final service = serviceFor(
        MockClient((_) async => http.Response('{}', 404)),
        configured: false);
    await library.upsert(const ScannedFile(
        filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));
    await service.matchUnmatched();
    expect((await library.getAll()).single.tmdbId, isNull);
  });

  test('matchItem no-ops without a TMDB key (and tolerates a missing id)',
      () async {
    final service = serviceFor(
        MockClient((_) async => http.Response('{}', 404)),
        configured: false);
    await library.upsert(const ScannedFile(
        filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));
    final id = (await library.findByPath('/m/a.mkv'))!.id;

    // Real id and a never-registered id both return cleanly, leaving the row
    // untouched.
    await service.matchItem(id);
    await service.matchItem(999999);
    expect((await library.getAll()).single.tmdbId, isNull);
  });

  // ── The matching path itself ────────────────────────────────────────────
  // Reachable now that AppConfig is injected. A TMDB router lets each test say
  // what the API answers per endpoint; unrouted paths 404 so an unexpected call
  // shows up as a failure rather than a silent miss.
  MockClient tmdbRouter({
    List<Map<String, dynamic>> tv = const [],
    List<Map<String, dynamic>> movies = const [],
    Map<String, dynamic>? tvDetails,
    Map<String, dynamic>? movieDetails,
    List<Uri>? log,
  }) =>
      MockClient((req) async {
        log?.add(req.url);
        final path = req.url.path;
        if (path.endsWith('/search/tv')) {
          return http.Response(jsonEncode({'results': tv}), 200);
        }
        if (path.endsWith('/search/movie')) {
          return http.Response(jsonEncode({'results': movies}), 200);
        }
        if (tvDetails != null && RegExp(r'/tv/\d+$').hasMatch(path)) {
          return http.Response(jsonEncode(tvDetails), 200);
        }
        if (movieDetails != null && RegExp(r'/movie/\d+$').hasMatch(path)) {
          return http.Response(jsonEncode(movieDetails), 200);
        }
        return http.Response('{}', 404);
      });

  Future<LibraryItem> seed(ScannedFile file) async {
    await library.upsert(file);
    return (await library.findByPath(file.filePath))!;
  }

  group('matchUnmatched', () {
    test('matches a TV row against TMDB and caches id, name, and poster',
        () async {
      await seed(const ScannedFile(
          filePath: '/tv/The Show/The.Show.S01E01.mkv',
          title: 'The Show',
          mediaType: 'tv',
          season: 1,
          episode: 1));

      await serviceFor(tmdbRouter(tv: [
        {'id': 4242, 'name': 'The Show', 'poster_path': '/show.jpg'},
      ])).matchUnmatched();

      final row = (await library.getAll()).single;
      expect(row.tmdbId, 4242);
      expect(row.tmdbName, 'The Show');
      expect(row.tmdbPosterPath, '/show.jpg');
    });

    test('matches a movie row', () async {
      await seed(const ScannedFile(
          filePath: '/m/Inception.mkv', title: 'Inception', mediaType: 'movie'));

      await serviceFor(tmdbRouter(movies: [
        {'id': 27205, 'title': 'Inception', 'poster_path': '/i.jpg'},
      ])).matchUnmatched();

      final row = (await library.getAll()).single;
      expect(row.tmdbId, 27205);
      expect(row.tmdbName, 'Inception');
    });

    // An episode that parsed as a "movie" (no SxxExx in the name) must still
    // find its show, and the row's mediaType gets corrected on the way.
    test('falls back to the other media type and corrects mediaType', () async {
      await seed(const ScannedFile(
          filePath: '/tv/The Show/ep1.mkv',
          title: 'The Show',
          mediaType: 'movie'));

      await serviceFor(tmdbRouter(tv: [
        {'id': 4242, 'name': 'The Show', 'poster_path': '/s.jpg'},
      ])).matchUnmatched();

      final row = (await library.getAll()).single;
      expect(row.tmdbId, 4242);
      expect(row.mediaType, 'tv');
    });

    test('a row nothing matches stays null for the next pass', () async {
      await seed(const ScannedFile(
          filePath: '/m/Unknowable.mkv',
          title: 'Unknowable',
          mediaType: 'movie'));

      await serviceFor(tmdbRouter()).matchUnmatched();

      final row = (await library.getAll()).single;
      expect(row.tmdbId, isNull);
      expect(await library.unmatched(), hasLength(1));
    });

    // pickBestMatchIndex guards this: a noisy query must not grab whatever
    // TMDB happened to return first.
    test('a result that does not validate against the query is rejected',
        () async {
      await seed(const ScannedFile(
          filePath: '/movies/Inception (2010)/Inception.mkv',
          title: 'Inception',
          mediaType: 'movie'));

      await serviceFor(tmdbRouter(movies: [
        {'id': 99, 'title': 'Something Entirely Different'},
      ])).matchUnmatched();

      expect((await library.getAll()).single.tmdbId, isNull);
    });

    // The containing folder is tried as a second query after the stored title.
    // A folder that names the show rescues a row whose filename didn't.
    test('falls back to the containing folder name as a second query',
        () async {
      await seed(const ScannedFile(
          filePath: '/tv/The Office/random.release.name.mkv',
          title: 'random.release.name',
          mediaType: 'tv'));

      await serviceFor(tmdbRouter(tv: [
        {'id': 2316, 'name': 'The Office', 'poster_path': '/o.jpg'},
      ])).matchUnmatched();

      expect((await library.getAll()).single.tmdbId, 2316);
    });

    // End-to-end guard for the false-match bug. Before the fix, the stored
    // title missed, the folder name went in as a second query, and containment
    // handed back whatever TMDB had returned.
    group('a library root never becomes a search query', () {
      test('a short root name no longer sweeps up an unrelated title',
          () async {
        await seed(const ScannedFile(
            filePath: '/m/Inception.mkv',
            title: 'Inception',
            mediaType: 'movie'));

        await serviceFor(
          tmdbRouter(movies: [
            {'id': 99, 'title': 'Something Entirely Different'},
          ]),
          roots: {'/m'},
        ).matchUnmatched();

        expect((await library.getAll()).single.tmdbId, isNull);
      });

      // The canonical layout: "/movies" is 6 characters, so the length floor
      // alone wouldn't have saved this one.
      test('the conventional "movies" root does not match a title named Movie',
          () async {
        await seed(const ScannedFile(
            filePath: '/movies/Inception.mkv',
            title: 'Inception',
            mediaType: 'movie'));

        await serviceFor(
          tmdbRouter(movies: [
            {'id': 99, 'title': 'Movie'},
          ]),
          roots: {'/movies'},
        ).matchUnmatched();

        expect((await library.getAll()).single.tmdbId, isNull);
      });

      test('a real show folder under a root still rescues a bad filename',
          () async {
        await seed(const ScannedFile(
            filePath: '/tv/The Office/xyz.release.name.mkv',
            title: 'xyz.release.name',
            mediaType: 'tv'));

        await serviceFor(
          tmdbRouter(tv: [
            {'id': 2316, 'name': 'The Office', 'poster_path': '/o.jpg'},
          ]),
          roots: {'/tv'},
        ).matchUnmatched();

        expect((await library.getAll()).single.tmdbId, 2316);
      });
    });

    test('an already-matched row is left alone', () async {
      final item = await seed(const ScannedFile(
          filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));
      await library.setTmdbMatch(
          id: item.id, tmdbId: 111, name: 'A!', posterPath: '/p.jpg');

      final calls = <Uri>[];
      await serviceFor(tmdbRouter(log: calls)).matchUnmatched();

      expect(calls, isEmpty);
      expect((await library.getAll()).single.tmdbName, 'A!');
    });

    // A trailing year is stripped so the title matches TMDB's canonical name.
    // Note it's `cleanShowName` (inside tmdbSearchCandidates) that removes it,
    // before LibraryMatchService's own _splitYear ever sees the candidate — so
    // the year is dropped rather than forwarded to TMDB as a `year` filter.
    test('a trailing year is stripped from the search query', () async {
      await seed(const ScannedFile(
          filePath: '/movies/Dune (2021)/Dune 2021.mkv',
          title: 'Dune 2021',
          mediaType: 'movie'));

      final calls = <Uri>[];
      await serviceFor(tmdbRouter(
        movies: [
          {'id': 438631, 'title': 'Dune', 'poster_path': '/d.jpg'},
        ],
        log: calls,
      )).matchUnmatched();

      final search = calls.firstWhere((u) => u.path.endsWith('/search/movie'));
      expect(search.queryParameters['query'], 'Dune');
      expect(search.queryParameters['year'], isNull);
      expect((await library.getAll()).single.tmdbId, 438631);
    });

    test('a TMDB failure is swallowed so the scan pass continues', () async {
      await seed(const ScannedFile(
          filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));

      final svc = serviceFor(MockClient((_) async => throw Exception('boom')));

      await expectLater(svc.matchUnmatched(), completes);
      expect((await library.getAll()).single.tmdbId, isNull);
    });
  });

  group('matchItem', () {
    // An acquire stamps the tmdbId up front but leaves the poster null, so the
    // back-fill goes by id — deterministic, no fuzzy title search.
    test('back-fills name and poster by id, without searching', () async {
      final item = await seed(const ScannedFile(
          filePath: '/tv/s.S01E01.mkv',
          title: 'raw.release.name',
          mediaType: 'tv',
          season: 1,
          episode: 1));
      await library.setTmdbMatch(id: item.id, tmdbId: 4242, name: null);

      final calls = <Uri>[];
      await serviceFor(tmdbRouter(
        tvDetails: {'id': 4242, 'name': 'The Show', 'poster_path': '/s.jpg'},
        log: calls,
      )).matchItem(item.id);

      final row = (await library.getAll()).single;
      expect(row.tmdbName, 'The Show');
      expect(row.tmdbPosterPath, '/s.jpg');
      expect(calls.where((u) => u.path.contains('/search/')), isEmpty);
    });

    test('a fully-matched row is skipped entirely', () async {
      final item = await seed(const ScannedFile(
          filePath: '/m/a.mkv', title: 'A', mediaType: 'movie'));
      await library.setTmdbMatch(
          id: item.id, tmdbId: 111, name: 'A!', posterPath: '/p.jpg');

      final calls = <Uri>[];
      await serviceFor(tmdbRouter(log: calls)).matchItem(item.id);

      expect(calls, isEmpty);
    });

    test('a missing id returns cleanly', () async {
      await expectLater(
          serviceFor(tmdbRouter()).matchItem(999999), completes);
    });
  });
}
