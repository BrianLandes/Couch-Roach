import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/saved_titles_repository.dart';
import 'package:couch_roach/src/features/discover/discover_providers.dart';
import 'package:couch_roach/src/features/discover/discover_tile.dart';
import 'package:couch_roach/src/features/discover/movie_detail_screen.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _StubDiscovery implements DiscoveryClient {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

class _FakeSavedTitlesRepo implements SavedTitlesRepository {
  @override
  Stream<SavedTitle?> watchTitle(
          {required int tmdbId, required String mediaType}) =>
      Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// What the landing rails hand the detail page for a saved / Alexa-queued title:
/// only what the SavedTitles row cached. This is the shape the hydration exists
/// for — see `_savedTile` in library_screen.dart.
const _alexaTile = DiscoverTile(
  tmdbId: 693134,
  title: 'Dune: Part Two',
  mediaType: 'movie',
  posterPath: '/saved.jpg',
);

/// The same title as a discovery rail builds it, straight from a TMDB search.
const _richTile = DiscoverTile(
  tmdbId: 693134,
  title: 'Dune: Part Two',
  mediaType: 'movie',
  posterPath: '/tmdb.jpg',
  overview: 'Paul Atreides unites with the Fremen.',
  year: 2024,
  voteAverage: 8.2,
);

void main() {
  setUp(() async {
    await getIt.reset();
    getIt
      ..registerLazySingleton<SavedTitlesRepository>(_FakeSavedTitlesRepo.new)
      ..registerLazySingleton<DiscoveryClient>(_StubDiscovery.new);
  });

  tearDown(() async => getIt.reset());

  Future<void> pump(
    WidgetTester tester,
    DiscoverTile tile, {
    DiscoverTile? fetched,
  }) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => MovieDetailScreen(tile: tile)),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        movieTileProvider(tile.tmdbId)
            .overrideWith((ref) => Future.value(fetched)),
        trailerUrlProvider((tile.tmdbId, false))
            .overrideWith((ref) => Future.value(null)),
        localTitleProvider(tile.tmdbId).overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // The regression this task is about: a title added by voice lands on
  // Want-to-watch with only id/name/poster, so before hydration its detail page
  // had no overview, year or rating at all.
  testWidgets('a sparse Alexa-queued tile gets the full TMDB profile',
      (tester) async {
    await pump(tester, _alexaTile, fetched: _richTile);

    expect(find.text('Paul Atreides unites with the Fremen.'), findsOneWidget);
    expect(find.text('2024  ·  ★ 8.2'), findsOneWidget);
  });

  testWidgets('without hydration the sparse tile shows no profile',
      (tester) async {
    // Guards the fallback: a TMDB miss must still render a usable page rather
    // than an error or a blank one.
    await pump(tester, _alexaTile, fetched: null);

    expect(find.text('Dune: Part Two'), findsWidgets);
    expect(find.textContaining('★'), findsNothing);
    expect(find.text('Paul Atreides unites with the Fremen.'), findsNothing);
  });

  testWidgets('a tile that already has its profile renders it unchanged',
      (tester) async {
    // A discovery-rail tile arrives complete; hydration must not disturb it.
    await pump(tester, _richTile, fetched: null);

    expect(find.text('Paul Atreides unites with the Fremen.'), findsOneWidget);
    expect(find.text('2024  ·  ★ 8.2'), findsOneWidget);
  });

  testWidgets('a partial TMDB response does not blank what was on screen',
      (tester) async {
    await pump(
      tester,
      _richTile,
      fetched: const DiscoverTile(
        tmdbId: 693134,
        title: 'Dune: Part Two',
        mediaType: 'movie',
      ),
    );

    expect(find.text('Paul Atreides unites with the Fremen.'), findsOneWidget);
    expect(find.text('2024  ·  ★ 8.2'), findsOneWidget);
  });

  testWidgets('an unowned movie offers Acquire rather than Play',
      (tester) async {
    await pump(tester, _alexaTile, fetched: _richTile);

    expect(find.text('Play'), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });
}
