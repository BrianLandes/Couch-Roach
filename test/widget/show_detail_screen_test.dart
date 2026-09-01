import 'dart:async';

import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/saved_titles_repository.dart';
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart';
import 'package:couch_roach/src/data/tmdb/season.dart';
import 'package:couch_roach/src/data/tmdb/tv_show_details.dart';
import 'package:couch_roach/src/features/discover/discover_providers.dart';
import 'package:couch_roach/src/features/discover/show_detail_screen.dart';
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

class _FakeLibraryRepo implements LibraryRepository {
  @override
  Future<List<LibraryItem>> localEpisodes(int tmdbId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

class _FakeWatchHistoryRepo implements WatchHistoryRepository {
  @override
  Stream<Set<(int, int)>> watchCompletedEpisodes(int tmdbId) =>
      Stream.value(const {});

  @override
  Future<int?> lastWatchedSeason(int tmdbId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// The full profile TMDB returns for the show.
final _details = TvShowDetails(
  tmdbId: 1399,
  name: 'Game of Thrones',
  overview: 'Nine noble families fight for control of Westeros.',
  firstAirDate: '2011-04-17',
  voteAverage: 8.4,
  seasons: [
    SeasonSummary(seasonNumber: 1, name: 'Season 1', episodeCount: 10),
  ],
);

void main() {
  setUp(() async {
    await getIt.reset();
    getIt
      ..registerLazySingleton<SavedTitlesRepository>(_FakeSavedTitlesRepo.new)
      ..registerLazySingleton<LibraryRepository>(_FakeLibraryRepo.new)
      ..registerLazySingleton<WatchHistoryRepository>(_FakeWatchHistoryRepo.new)
      ..registerLazySingleton<DiscoveryClient>(_StubDiscovery.new);
  });

  tearDown(() async => getIt.reset());

  Future<void> pump(
    WidgetTester tester, {
    required TvShowDetails? details,
    Object? error,
  }) async {
    const args = ShowDetailArgs(tmdbId: 1399, name: 'Game of Thrones');
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ShowDetailScreen(args: args)),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tvDetailsProvider(1399).overrideWith(
            (ref) => error != null ? Future.error(error) : Future.value(details)),
        trailerUrlProvider((1399, true)).overrideWith((ref) => Future.value(null)),
        seasonProvider((1399, 1)).overrideWith((ref) => Future.value(null)),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // The TV half of the Alexa hydration task. A voice-added show lands on
  // Want-to-watch with only {tmdbId, name, poster}, and the rail pushes just
  // (tmdbId, name) here — so unlike the movie page there's no sparse tile to
  // merge: this screen is hydration by construction, fetching the profile by id.
  // This pins that, so a future refactor can't quietly start rendering off the
  // sparse args instead.
  testWidgets('a saved show hydrates its full profile from just (id, name)',
      (tester) async {
    await pump(tester, details: _details);

    expect(find.text('Nine noble families fight for control of Westeros.'),
        findsOneWidget);
    expect(find.textContaining('2011'), findsOneWidget);
    expect(find.textContaining('★ 8.4'), findsOneWidget);
  });

  testWidgets('the header shows the saved name before TMDB answers',
      (tester) async {
    // The page must be usable (and poppable) during the fetch, so the pinned
    // header comes from the route args rather than the response.
    const args = ShowDetailArgs(tmdbId: 1399, name: 'Game of Thrones');
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ShowDetailScreen(args: args)),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Never completes — holds the screen in its loading state.
        tvDetailsProvider(1399)
            .overrideWith((ref) => Completer<TvShowDetails?>().future),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    await tester.pump();

    expect(find.text('Game of Thrones'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // A TMDB failure must not strand files already on disk, so the page degrades
  // to a playable list rather than an error.
  testWidgets('a TMDB failure falls back with a notice, not a dead page',
      (tester) async {
    await pump(tester, details: null, error: Exception('offline'));

    expect(find.textContaining('Could not load details'), findsOneWidget);
    expect(find.text('Game of Thrones'), findsWidgets);
  });

  testWidgets('a TMDB miss says so rather than showing an empty show',
      (tester) async {
    await pump(tester, details: null);

    expect(find.text('Not found on TMDB.'), findsOneWidget);
  });
}
