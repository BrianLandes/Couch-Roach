import 'dart:convert';
import 'dart:io';

import 'package:couch_roach/src/core/config/app_config.dart';
import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/saved_titles_repository.dart';
import 'package:couch_roach/src/data/tmdb/movie_summary.dart';
import 'package:couch_roach/src/data/tmdb/tv_show_summary.dart';
import 'package:couch_roach/src/services/alexa/alexa_inbox_service.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_app_config.dart';

/// A DiscoveryClient stub: canned movie/tv search results, everything else
/// unimplemented (the service only calls the two search methods).
class _FakeDiscovery implements DiscoveryClient {
  _FakeDiscovery({this.movies = const [], this.shows = const []});
  List<MovieSummary> movies;
  List<TvShowSummary> shows;
  final searchedMovies = <String>[];
  final searchedTv = <String>[];

  @override
  Future<List<MovieSummary>> searchMovies(String query, {int? year}) async {
    searchedMovies.add(query);
    return movies;
  }

  @override
  Future<List<TvShowSummary>> searchTv(String query, {int? year}) async {
    searchedTv.add(query);
    return shows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Records the request log and replays scripted responses per path.
class _Worker {
  _Worker({required this.pendingBody});
  String pendingBody;
  int pendingStatus = 200;
  final List<http.Request> requests = [];
  final List<List<String>> ackedBatches = [];

  http.Client client() => MockClient((req) async {
        requests.add(req);
        if (req.url.path.endsWith('/pending')) {
          return http.Response(pendingBody, pendingStatus,
              headers: {'content-type': 'application/json'});
        }
        if (req.url.path.endsWith('/ack')) {
          final ids = (jsonDecode(req.body) as Map)['ids'] as List;
          ackedBatches.add(ids.cast<String>());
          return http.Response(jsonEncode({'ok': true}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('nope', 404);
      });
}

MovieSummary _movie(int id, String title) =>
    MovieSummary(tmdbId: id, title: title, posterPath: '/p.jpg');
TvShowSummary _show(int id, String name) =>
    TvShowSummary(tmdbId: id, name: name, posterPath: '/s.jpg');

void main() {
  late AppDatabase db;
  late SavedTitlesRepository saved;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    saved = DriftSavedTitlesRepository(db);
  });
  tearDown(() async => db.close());

  AlexaInboxService serviceWith(
    _Worker worker,
    DiscoveryClient tmdb, {
    AppConfig config = const FakeAppConfig(),
  }) =>
      AlexaInboxService(
          worker.client(), tmdb, saved, ErrorLogService(), config);

  // `hasAlexaInbox` / `hasTmdbKey` read compile-time --dart-define values, which
  // are always empty under `flutter test`. The service takes its AppConfig as a
  // constructor dependency so [FakeAppConfig] can stand in and make the whole
  // drain path reachable here.

  group('addFromAlexa', () {
    test('resolves a movie top-hit onto Want-to-watch tagged alexa', () async {
      final tmdb = _FakeDiscovery(movies: [_movie(693134, 'Dune: Part Two')]);
      final svc = serviceWith(_Worker(pendingBody: '[]'), tmdb);

      await svc.addFromAlexa('dune part two');

      final rows = await saved.watchWantToWatch().first;
      expect(rows.single.tmdbId, 693134);
      expect(rows.single.mediaType, 'movie');
      expect(rows.single.name, 'Dune: Part Two');
      expect(rows.single.source, 'alexa');
      expect(tmdb.searchedMovies.single, 'dune part two');
      // Movie hit short-circuits before the TV fallback.
      expect(tmdb.searchedTv, isEmpty);
    });

    test('falls back to a TV top-hit when no movie matches', () async {
      final tmdb = _FakeDiscovery(movies: const [], shows: [_show(1399, 'GoT')]);
      final svc = serviceWith(_Worker(pendingBody: '[]'), tmdb);

      await svc.addFromAlexa('game of thrones');

      final rows = await saved.watchWantToWatch().first;
      expect(rows.single.tmdbId, 1399);
      expect(rows.single.mediaType, 'tv');
      expect(rows.single.source, 'alexa');
    });

    test('no TMDB match: no row inserted, returns normally (acks)', () async {
      final tmdb = _FakeDiscovery(); // both searches empty
      final svc = serviceWith(_Worker(pendingBody: '[]'), tmdb);

      await svc.addFromAlexa('xzqvbn zzz'); // must not throw

      expect(await saved.watchWantToWatch().first, isEmpty);
    });

    test('dedupe: the same title twice yields one row', () async {
      final tmdb = _FakeDiscovery(movies: [_movie(1, 'Inception')]);
      final svc = serviceWith(_Worker(pendingBody: '[]'), tmdb);

      await svc.addFromAlexa('inception');
      await svc.addFromAlexa('inception');

      final rows = await saved.watchWantToWatch().first;
      expect(rows, hasLength(1));
    });

    test('a title already manually saved keeps its original source (null)',
        () async {
      // User watchlisted it in-app first (no source), then Alexa re-adds it.
      await saved.setWantToWatch(
          tmdbId: 5, mediaType: 'movie', name: 'Heat', value: true);
      final tmdb = _FakeDiscovery(movies: [_movie(5, 'Heat')]);
      final svc = serviceWith(_Worker(pendingBody: '[]'), tmdb);

      await svc.addFromAlexa('heat');

      final row = await saved.watchTitle(tmdbId: 5, mediaType: 'movie').first;
      expect(row!.source, isNull); // manual origin preserved, not overwritten
    });
  });

  group('drain', () {
    test('is a no-op when the inbox token is not configured', () async {
      // An unconfigured build must never talk to the Worker at all.
      final worker = _Worker(pendingBody: '[]');
      final svc = serviceWith(worker, _FakeDiscovery(),
          config: const FakeAppConfig(hasAlexaInbox: false));

      await svc.drain(minGap: Duration.zero);

      expect(worker.requests, isEmpty);
    });

    test('is a no-op when TMDB is unavailable to resolve titles', () async {
      // Draining without TMDB would ack titles it can't resolve, losing them.
      final worker = _Worker(pendingBody: '[]');
      final svc = serviceWith(worker, _FakeDiscovery(),
          config: const FakeAppConfig(hasTmdbKey: false));

      await svc.drain(minGap: Duration.zero);

      expect(worker.requests, isEmpty);
    });

    test('an empty queue polls but sends no ack', () async {
      final worker = _Worker(pendingBody: '[]');
      final svc = serviceWith(worker, _FakeDiscovery());

      await svc.drain(minGap: Duration.zero);

      expect(worker.requests.map((r) => r.url.path), ['/pending']);
      expect(worker.ackedBatches, isEmpty);
    });

    test('resolves a queued title onto Want-to-watch and acks it', () async {
      final worker = _Worker(
          pendingBody: jsonEncode([
        {'id': 'q1', 'title': 'dune part two'},
      ]));
      final tmdb = _FakeDiscovery(movies: [_movie(693134, 'Dune: Part Two')]);
      final svc = serviceWith(worker, tmdb);

      await svc.drain(minGap: Duration.zero);

      expect(tmdb.searchedMovies, ['dune part two']);
      final rows = await saved.watchWantToWatch().first;
      expect(rows.single.tmdbId, 693134);
      expect(rows.single.source, 'alexa');
      expect(worker.ackedBatches, [
        ['q1']
      ]);
    });

    test('drains a whole batch in order and acks all of it', () async {
      final worker = _Worker(
          pendingBody: jsonEncode([
        {'id': 'q1', 'title': 'heat'},
        {'id': 'q2', 'title': 'dune'},
      ]));
      final tmdb = _FakeDiscovery(movies: [_movie(1, 'Heat')]);
      final svc = serviceWith(worker, tmdb);

      await svc.drain(minGap: Duration.zero);

      expect(tmdb.searchedMovies, ['heat', 'dune']);
      expect(worker.ackedBatches, [
        ['q1', 'q2']
      ]);
    });

    // A title TMDB can't resolve is still acked — otherwise the Worker would
    // redeliver it forever and block the queue behind it.
    test('acks a no-match instead of looping on it', () async {
      final worker = _Worker(
          pendingBody: jsonEncode([
        {'id': 'q1', 'title': 'asdfqwer nonsense'},
      ]));
      final svc = serviceWith(worker, _FakeDiscovery()); // no results at all

      await svc.drain(minGap: Duration.zero);

      expect(await saved.watchWantToWatch().first, isEmpty);
      expect(worker.ackedBatches, [
        ['q1']
      ]);
    });

    test('a non-200 from /pending is swallowed and acks nothing', () async {
      final worker = _Worker(pendingBody: '[]')..pendingStatus = 401;
      final svc = serviceWith(worker, _FakeDiscovery());

      await svc.drain(minGap: Duration.zero);

      expect(worker.ackedBatches, isEmpty);
    });

    test('a network failure is swallowed, not thrown', () async {
      final svc = AlexaInboxService(
        MockClient((_) async => throw const SocketException('no route')),
        _FakeDiscovery(),
        saved,
        ErrorLogService(),
        const FakeAppConfig(),
      );

      await expectLater(svc.drain(minGap: Duration.zero), completes);
    });

    test('a second drain inside the throttle window is skipped', () async {
      final worker = _Worker(pendingBody: '[]');
      final svc = serviceWith(worker, _FakeDiscovery());

      await svc.drain(minGap: Duration.zero);
      await svc.drain(minGap: const Duration(seconds: 30));

      expect(worker.requests, hasLength(1));
    });

    test('a zero gap bypasses the throttle for a manual refresh', () async {
      final worker = _Worker(pendingBody: '[]');
      final svc = serviceWith(worker, _FakeDiscovery());

      await svc.drain(minGap: Duration.zero);
      await svc.drain(minGap: Duration.zero);

      expect(worker.requests, hasLength(2));
    });

    // Only a *completed* cycle stamps the throttle, so a blip lets the next
    // trigger retry immediately rather than being throttled out.
    test('a failed drain does not start the throttle window', () async {
      final worker = _Worker(pendingBody: '[]')..pendingStatus = 503;
      final svc = serviceWith(worker, _FakeDiscovery());

      await svc.drain(minGap: Duration.zero);
      await svc.drain(minGap: const Duration(seconds: 30));

      expect(worker.requests, hasLength(2));
    });

    test('re-delivery of an already-saved title is idempotent', () async {
      final body = jsonEncode([
        {'id': 'q1', 'title': 'dune'},
      ]);
      final tmdb = _FakeDiscovery(movies: [_movie(693134, 'Dune')]);

      await serviceWith(_Worker(pendingBody: body), tmdb)
          .drain(minGap: Duration.zero);
      await serviceWith(_Worker(pendingBody: body), tmdb)
          .drain(minGap: Duration.zero);

      final rows = await saved.watchWantToWatch().first;
      expect(rows, hasLength(1));
      expect(rows.single.source, 'alexa');
    });
  });
}
