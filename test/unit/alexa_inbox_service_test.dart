import 'dart:convert';

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
  final List<http.Request> requests = [];
  final List<List<String>> ackedBatches = [];

  http.Client client() => MockClient((req) async {
        requests.add(req);
        if (req.url.path.endsWith('/pending')) {
          return http.Response(pendingBody, 200,
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
    DiscoveryClient tmdb,
  ) =>
      AlexaInboxService(worker.client(), tmdb, saved, ErrorLogService());

  // NOTE: hasAlexaInbox / hasTmdbKey both read compile-time --dart-define
  // values, which are empty under `flutter test`, so drain() short-circuits.
  // These tests exercise addFromAlexa (the resolve+save unit) directly and the
  // drain plumbing where the guard allows.

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
      // Under `flutter test` there's no --dart-define, so hasAlexaInbox is
      // false: drain must never hit the Worker.
      final worker = _Worker(pendingBody: '[]');
      final svc = serviceWith(worker, _FakeDiscovery());

      await svc.drain(minGap: Duration.zero);

      expect(worker.requests, isEmpty);
    });
  });
}
