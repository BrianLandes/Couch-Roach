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
  /// Drives what's "on disk", so a test can land a downloaded episode while the
  /// page is already built — the season-download case this screen has to react
  /// to. Broadcast because several providers watch the same show.
  final controller = StreamController<List<LibraryItem>>.broadcast();
  List<LibraryItem> _current = const [];

  /// Replay the current value to each new listener before following the
  /// controller, the way a drift `.watch()` query does. Without this a provider
  /// that subscribes late would sit in `loading` forever instead of seeing
  /// "nothing on disk yet".
  @override
  Stream<List<LibraryItem>> watchLocalEpisodes(int tmdbId) async* {
    yield _current;
    yield* controller.stream;
  }

  /// Land (or remove) files, notifying everything already watching.
  void emit(List<LibraryItem> items) {
    _current = items;
    controller.add(items);
  }

  @override
  Future<List<LibraryItem>> localEpisodes(int tmdbId) async => _current;

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// A downloaded episode file as the scanner would have recorded it.
LibraryItem _episodeFile({int id = 1, int season = 1, int episode = 1}) =>
    LibraryItem(
      id: id,
      filePath: 'C:\\media\\tv\\got.s0${season}e0$episode.mkv',
      title: 'Game of Thrones',
      mediaType: 'tv',
      season: season,
      episode: episode,
      tmdbId: 1399,
      tmdbName: 'Game of Thrones',
      keep: false,
      missing: false,
      hasEmbeddedEnSub: false,
      addedAt: DateTime(2026),
      subtitleOffsetMs: 0,
      managed: true,
    );

/// One aired season, so the rows render a Download control rather than an
/// unreleased badge.
final _season1 = SeasonDetails(
  seasonNumber: 1,
  name: 'Season 1',
  episodes: [
    EpisodeSummary(
        episodeNumber: 1, name: 'Winter Is Coming', airDate: '2011-04-17'),
    EpisodeSummary(
        episodeNumber: 2, name: 'The Kingsroad', airDate: '2011-04-24'),
  ],
);

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
  late _FakeLibraryRepo library;

  setUp(() async {
    library = _FakeLibraryRepo();
    await getIt.reset();
    getIt
      ..registerLazySingleton<SavedTitlesRepository>(_FakeSavedTitlesRepo.new)
      ..registerLazySingleton<LibraryRepository>(() => library)
      ..registerLazySingleton<WatchHistoryRepository>(_FakeWatchHistoryRepo.new)
      ..registerLazySingleton<DiscoveryClient>(_StubDiscovery.new);
  });

  tearDown(() async {
    await library.controller.close();
    await getIt.reset();
  });

  Future<void> pump(
    WidgetTester tester, {
    required TvShowDetails? details,
    Object? error,
    SeasonDetails? season,
  }) async {
    // DetailScaffold lays its children out in a lazy ListView, so on the default
    // 800x600 surface the episode rows never build. Give the test a tall enough
    // viewport that the whole page is in the tree.
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const args = ShowDetailArgs(tmdbId: 1399, name: 'Game of Thrones');
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ShowDetailScreen(args: args)),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tvDetailsProvider(1399).overrideWith(
            (ref) => error != null ? Future.error(error) : Future.value(details)),
        trailerUrlProvider((1399, true)).overrideWith((ref) => Future.value(null)),
        seasonProvider((1399, 1)).overrideWith((ref) => Future.value(season)),
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

  // The task: while a season downloads, an episode that finishes must flip its
  // row to Play without a manual refresh. Before this, localEpisodesProvider was
  // a FutureProvider read once when the page opened, so the row stayed on
  // "Download" until you navigated away and back.
  group('live episode availability', () {
    testWidgets('an episode landing mid-download flips its row to Play',
        (tester) async {
      await pump(tester, details: _details, season: _season1);

      expect(find.text('Play'), findsNothing);
      expect(find.text('1. Winter Is Coming'), findsOneWidget);

      // The download completes and the scanner registers the file.
      library.emit([_episodeFile(episode: 1)]);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('each episode flips independently as its own file lands',
        (tester) async {
      await pump(tester, details: _details, season: _season1);
      library.emit([_episodeFile(id: 1, episode: 1)]);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Play'), findsOneWidget);

      library.emit([
        _episodeFile(id: 1, episode: 1),
        _episodeFile(id: 2, episode: 2),
      ]);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Play'), findsNWidgets(2));
    });

    // The same liveness in reverse: deleting an episode drops its row back to a
    // Download control, which is why the hand-rolled ref.invalidate calls could
    // go away.
    testWidgets('a deleted episode drops its row back off Play', (tester) async {
      await pump(tester, details: _details, season: _season1);
      library.emit([_episodeFile(episode: 1)]);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Play'), findsOneWidget);

      library.emit(const []);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Play'), findsNothing);
    });
  });
}
