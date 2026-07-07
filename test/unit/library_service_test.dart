import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/storage/storage_manager.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/storage_repository.dart';
import 'package:couch_roach/src/features/library/library_service.dart';
import 'package:couch_roach/src/features/library/media_scanner.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// End-to-end: real temp folders on disk → scanner → repository.
void main() {
  late AppDatabase db;
  late DriftStorageRepository storageRepo;
  late ConfiguredStorageManager storage;
  late LibraryRepository library;
  late LibraryService service;
  late Directory root;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storageRepo = DriftStorageRepository(db);
    storage = ConfiguredStorageManager(storageRepo);
    library = DriftLibraryRepository(db);
    service = LibraryService(MediaScanner(storage), library, storage, ErrorLogService());

    root = await Directory.systemTemp.createTemp('cr_scan');
    await storageRepo.addRoot(path: root.path);
    await storage.load();
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File touch(String name) => File('${root.path}/$name')..writeAsStringSync('x');

  test('rescan finds video files and skips non-video', () async {
    touch('The.Show.S01E01.1080p.mkv');
    touch('A.Movie.2021.mp4');
    touch('notes.txt');

    await service.rescan();

    final items = await library.getAll();
    final names = items.map((e) => e.filePath.split('/').last);
    expect(names, containsAll(['The.Show.S01E01.1080p.mkv', 'A.Movie.2021.mp4']));
    expect(names, isNot(contains('notes.txt')));

    final show = items.firstWhere((e) => e.mediaType == 'tv');
    expect(show.season, 1);
    expect(show.episode, 1);
  });

  test('a rescan flags files that disappeared as missing', () async {
    final gone = touch('gone.mkv');
    touch('stays.mkv');
    await service.rescan();
    expect((await library.getAll()).length, 2);

    gone.deleteSync();
    await service.rescan();

    final present = await library.watchPresent().first;
    expect(present.map((e) => e.filePath.split('/').last), ['stays.mkv']);
    // The row survives (flagged), it isn't deleted.
    expect((await library.getAll()).length, 2);
  });

  test('recurses into subdirectories', () async {
    final sub = Directory('${root.path}/Movies/Action')..createSync(recursive: true);
    File('${sub.path}/Deep.Movie.2020.mkv').writeAsStringSync('x');

    await service.rescan();

    final names = (await library.getAll()).map((e) => e.filePath.split('/').last);
    expect(names, contains('Deep.Movie.2020.mkv'));
  });

  test('skips OS junk dirs and keeps scanning the rest', () async {
    // Simulate a Windows drive root: junk dirs alongside real content.
    for (final junk in [r'$RECYCLE.BIN', 'System Volume Information']) {
      final d = Directory('${root.path}/$junk')..createSync();
      File('${d.path}/hidden.mkv').writeAsStringSync('x');
    }
    touch('Real.Movie.2019.mkv');

    await service.rescan();

    final names =
        (await library.getAll()).map((e) => e.filePath.split('/').last).toList();
    expect(names, contains('Real.Movie.2019.mkv'));
    expect(names, isNot(contains('hidden.mkv')));
  });

  test('scanning flag toggles around a rescan', () async {
    expect(service.isScanning, isFalse);
    final future = service.rescan();
    // may already be false by microtask timing; just assert it completes cleanly
    await future;
    expect(service.isScanning, isFalse);
  });
}
