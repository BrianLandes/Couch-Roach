import 'dart:convert';

import 'package:couch_roach/src/app.dart';
import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/storage/storage_manager.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/storage_repository.dart';
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart';
import 'package:couch_roach/src/features/discover/show_detail_screen.dart';
import 'package:couch_roach/src/features/library/library_service.dart';
import 'package:couch_roach/src/features/library/media_scanner.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // The app resolves services from get_it, so register an in-memory graph.
  setUp(() async {
    await getIt.reset();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<AppDatabase>(db)
      ..registerSingleton<StorageRepository>(DriftStorageRepository(db))
      ..registerSingleton<LibraryRepository>(DriftLibraryRepository(db))
      ..registerSingleton<WatchHistoryRepository>(
          DriftWatchHistoryRepository(db))
      ..registerLazySingleton<StorageManager>(
          () => ConfiguredStorageManager(getIt<StorageRepository>()))
      ..registerLazySingleton<MediaScanner>(
          () => MediaScanner(getIt<StorageManager>()))
      ..registerLazySingleton<ErrorLogService>(ErrorLogService.new)
      ..registerLazySingleton<http.Client>(
          () => MockClient((_) async => http.Response('{}', 200)))
      ..registerLazySingleton<DiscoveryClient>(
          () => TmdbClient(getIt<http.Client>(), getIt<ErrorLogService>()))
      ..registerLazySingleton<LibraryService>(
          () => LibraryService(getIt(), getIt(), getIt(), getIt()));
  });
  tearDown(() => getIt.reset());

  testWidgets('app shell renders the title', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CouchRoachApp()));
    await tester.pump(); // let the library stream emit
    expect(find.text('Couch Roach'), findsOneWidget);

    // Tear the tree down inside the test so drift's stream-cleanup timer fires
    // before the framework's pending-timer check.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('renders a tile per library item', (tester) async {
    final repo = getIt<LibraryRepository>();
    await repo.upsert(
        const ScannedFile(filePath: '/m/dune.mkv', title: 'Dune', mediaType: 'movie'));
    await repo.upsert(const ScannedFile(
        filePath: '/tv/show.S01E01.mkv',
        title: 'The Show',
        mediaType: 'tv',
        season: 1,
        episode: 1));

    await tester.pumpWidget(const ProviderScope(child: CouchRoachApp()));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('The Show'), findsOneWidget);
    expect(find.text('S1 · E1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('shows a Continue Watching rail for in-progress items', (tester) async {
    final library = getIt<LibraryRepository>();
    final history = getIt<WatchHistoryRepository>();
    await library.upsert(
        const ScannedFile(filePath: '/m/dune.mkv', title: 'Dune', mediaType: 'movie'));
    final id = (await library.findByPath('/m/dune.mkv'))!.id;
    await history.record(
      libraryItemId: id,
      position: const Duration(seconds: 60),
      duration: const Duration(seconds: 120),
    );

    await tester.pumpWidget(const ProviderScope(child: CouchRoachApp()));
    await tester.pumpAndSettle();

    expect(find.text('CONTINUE WATCHING'), findsOneWidget);
    expect(find.textContaining('left'), findsOneWidget); // "1:00 left"

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('show detail renders info and episodes', (tester) async {
    getIt.unregister<DiscoveryClient>();
    getIt.registerSingleton<DiscoveryClient>(TmdbClient(
      MockClient((req) async {
        const jsonUtf8 = {'content-type': 'application/json; charset=utf-8'};
        final p = req.url.path;
        if (p.contains('/tv/1399/season/1')) {
          return http.Response(
              jsonEncode({
                'season_number': 1,
                'name': 'Season 1',
                'episodes': [
                  {'episode_number': 1, 'name': 'Winter Is Coming', 'runtime': 62},
                ],
              }),
              200,
              headers: jsonUtf8);
        }
        if (p.contains('/tv/1399')) {
          return http.Response(
              jsonEncode({
                'id': 1399,
                'name': 'Game of Thrones',
                'overview': 'Nine noble families vie for control.',
                'number_of_seasons': 1,
                'seasons': [
                  {'season_number': 1, 'name': 'Season 1'},
                ],
              }),
              200,
              headers: jsonUtf8);
        }
        return http.Response('{}', 404);
      }),
      getIt<ErrorLogService>(),
    ));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ShowDetailScreen(
            args: ShowDetailArgs(tmdbId: 1399, name: 'Game of Thrones'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Game of Thrones'), findsOneWidget);
    expect(find.textContaining('Winter Is Coming'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
