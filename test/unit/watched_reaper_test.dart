import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart';
import 'package:couch_roach/src/services/cleanup/watched_reaper.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late DriftLibraryRepository library;
  late DriftWatchHistoryRepository history;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = DriftLibraryRepository(db);
    history = DriftWatchHistoryRepository(db);
    tmp = await Directory.systemTemp.createTemp('cr_reap');
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String sidecarPath(String videoPath) =>
      p.join(p.dirname(videoPath), '${p.basenameWithoutExtension(videoPath)}.en.srt');

  Future<int> addItem(
    String name, {
    bool keep = false,
    bool withSidecar = false,
  }) async {
    final path = p.join(tmp.path, name);
    File(path).writeAsStringSync('video');
    if (withSidecar) File(sidecarPath(path)).writeAsStringSync('subs');
    await library
        .upsert(ScannedFile(filePath: path, title: name, mediaType: 'movie'));
    final id = (await library.findByPath(path))!.id;
    if (keep) await library.setKeep(id, true);
    return id;
  }

  Future<void> watched(
    int id, {
    required bool completed,
    required int daysAgo,
  }) async {
    await db.into(db.watchHistory).insert(
          WatchHistoryCompanion.insert(
            libraryItemId: id,
            completed: Value(completed),
            resumePositionSec: Value(completed ? 0 : 300),
            lastWatchedAt:
                Value(DateTime.now().subtract(Duration(days: daysAgo))),
          ),
        );
  }

  DriftWatchedReaper reaper({bool enabled = true}) => DriftWatchedReaper(
        history,
        library,
        ErrorLogService(),
        WatchedReaperConfig(enabled: enabled),
      );

  test('reaps a completed, past-grace, non-kept file + its sidecar', () async {
    final id = await addItem('A.mkv', withSidecar: true);
    await watched(id, completed: true, daysAgo: 8);
    final path = p.join(tmp.path, 'A.mkv');

    final removed = await reaper().sweep();

    expect(removed, [path]);
    expect(File(path).existsSync(), isFalse); // video gone
    expect(File(sidecarPath(path)).existsSync(), isFalse); // sidecar gone

    // The library row survives, flagged missing…
    final row = await library.findByPath(path);
    expect(row, isNotNull);
    expect(row!.missing, isTrue);
    // …and so does its watch history ("what I watched" outlives the file).
    expect(await history.forItem(id), isNotNull);
  });

  test('never reaps a kept title', () async {
    final id = await addItem('keep.mkv', keep: true);
    await watched(id, completed: true, daysAgo: 30);

    expect(await reaper().sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'keep.mkv')).existsSync(), isTrue);
  });

  test('never reaps within the grace period', () async {
    final id = await addItem('recent.mkv');
    await watched(id, completed: true, daysAgo: 1); // < 7-day grace

    expect(await reaper().sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'recent.mkv')).existsSync(), isTrue);
  });

  test('never reaps an in-progress (not completed) title', () async {
    final id = await addItem('midway.mkv');
    await watched(id, completed: false, daysAgo: 30);

    expect(await reaper().sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'midway.mkv')).existsSync(), isTrue);
  });

  test('never reaps a title with no watch history', () async {
    await addItem('unwatched.mkv');

    expect(await reaper().sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'unwatched.mkv')).existsSync(), isTrue);
  });

  test('sweeps multiple eligible files and leaves the rest', () async {
    final a = await addItem('a.mkv');
    final b = await addItem('b.mkv');
    final keep = await addItem('keep.mkv', keep: true);
    await watched(a, completed: true, daysAgo: 10);
    await watched(b, completed: true, daysAgo: 10);
    await watched(keep, completed: true, daysAgo: 10);

    final removed = await reaper().sweep();

    expect(removed.map((r) => p.basename(r)), containsAll(['a.mkv', 'b.mkv']));
    expect(removed, hasLength(2));
    expect(File(p.join(tmp.path, 'keep.mkv')).existsSync(), isTrue);
  });

  test('disabled config reaps nothing', () async {
    final id = await addItem('a.mkv');
    await watched(id, completed: true, daysAgo: 10);

    expect(await reaper(enabled: false).sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'a.mkv')).existsSync(), isTrue);
  });

  test('setKeep persists on the library row', () async {
    final id = await addItem('a.mkv');
    await library.setKeep(id, true);
    expect((await library.findByPath(p.join(tmp.path, 'a.mkv')))!.keep, isTrue);
    await library.setKeep(id, false);
    expect((await library.findByPath(p.join(tmp.path, 'a.mkv')))!.keep, isFalse);
  });
}
