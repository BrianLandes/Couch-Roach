import 'package:couch_roach/src/app.dart';
import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/storage/storage_manager.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/storage_repository.dart';
import 'package:couch_roach/src/features/library/library_service.dart';
import 'package:couch_roach/src/features/library/media_scanner.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The app resolves services from get_it, so register an in-memory graph.
  setUp(() async {
    await getIt.reset();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<AppDatabase>(db)
      ..registerSingleton<StorageRepository>(DriftStorageRepository(db))
      ..registerSingleton<LibraryRepository>(DriftLibraryRepository(db))
      ..registerLazySingleton<StorageManager>(
          () => ConfiguredStorageManager(getIt<StorageRepository>()))
      ..registerLazySingleton<MediaScanner>(
          () => MediaScanner(getIt<StorageManager>()))
      ..registerLazySingleton<ErrorLogService>(ErrorLogService.new)
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
}
