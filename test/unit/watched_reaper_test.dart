import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/saved_titles_repository.dart';
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

  Future<DriftWatchedReaper> reaper({bool enabled = true}) async {
    final settings = SettingsService(db);
    await settings.load();
    if (!enabled) await settings.setCleanupEnabled(false);
    return DriftWatchedReaper(history, library, ErrorLogService(), settings);
  }

  test('reaps a completed, past-grace, non-kept file + its sidecar', () async {
    final id = await addItem('A.mkv', withSidecar: true);
    await watched(id, completed: true, daysAgo: 8);
    final path = p.join(tmp.path, 'A.mkv');

    final removed = await (await reaper()).sweep();

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

    expect(await (await reaper()).sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'keep.mkv')).existsSync(), isTrue);
  });

  test('never reaps within the grace period', () async {
    final id = await addItem('recent.mkv');
    await watched(id, completed: true, daysAgo: 1); // < 7-day grace

    expect(await (await reaper()).sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'recent.mkv')).existsSync(), isTrue);
  });

  test('never reaps an in-progress (not completed) title', () async {
    final id = await addItem('midway.mkv');
    await watched(id, completed: false, daysAgo: 30);

    expect(await (await reaper()).sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'midway.mkv')).existsSync(), isTrue);
  });

  test('never reaps a title with no watch history', () async {
    await addItem('unwatched.mkv');

    expect(await (await reaper()).sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'unwatched.mkv')).existsSync(), isTrue);
  });

  test('sweeps multiple eligible files and leaves the rest', () async {
    final a = await addItem('a.mkv');
    final b = await addItem('b.mkv');
    final keep = await addItem('keep.mkv', keep: true);
    await watched(a, completed: true, daysAgo: 10);
    await watched(b, completed: true, daysAgo: 10);
    await watched(keep, completed: true, daysAgo: 10);

    final removed = await (await reaper()).sweep();

    expect(removed.map((r) => p.basename(r)), containsAll(['a.mkv', 'b.mkv']));
    expect(removed, hasLength(2));
    expect(File(p.join(tmp.path, 'keep.mkv')).existsSync(), isTrue);
  });

  test('disabled config reaps nothing', () async {
    final id = await addItem('a.mkv');
    await watched(id, completed: true, daysAgo: 10);

    expect(await (await reaper(enabled: false)).sweep(), isEmpty);
    expect(File(p.join(tmp.path, 'a.mkv')).existsSync(), isTrue);
  });

  test('setKeep persists on the library row', () async {
    final id = await addItem('a.mkv');
    await library.setKeep(id, true);
    expect((await library.findByPath(p.join(tmp.path, 'a.mkv')))!.keep, isTrue);
    await library.setKeep(id, false);
    expect((await library.findByPath(p.join(tmp.path, 'a.mkv')))!.keep, isFalse);
  });

  test('a show-level keep spares its episodes — including ones added later',
      () async {
    final saved = DriftSavedTitlesRepository(db);

    Future<int> addEpisode(String name, int season, int episode) async {
      final path = p.join(tmp.path, name);
      File(path).writeAsStringSync('video');
      await library.upsert(ScannedFile(
        filePath: path,
        title: 'Kept Show',
        mediaType: 'tv',
        season: season,
        episode: episode,
        tmdbId: 555,
        tmdbName: 'Kept Show',
      ));
      return (await library.findByPath(path))!.id;
    }

    // Two watched, past-grace episodes — reapable on their own.
    final e1 = await addEpisode('kept.S01E01.mkv', 1, 1);
    final e2 = await addEpisode('kept.S01E02.mkv', 1, 2);
    await watched(e1, completed: true, daysAgo: 30);
    await watched(e2, completed: true, daysAgo: 30);

    // Pin the whole show (per-show, on SavedTitles).
    await saved.setKeep(
        tmdbId: 555, mediaType: 'tv', name: 'Kept Show', value: true);

    // A *future* episode acquired after pinning — must also be spared.
    final e3 = await addEpisode('kept.S01E03.mkv', 1, 3);
    await watched(e3, completed: true, daysAgo: 30);

    expect(await (await reaper()).sweep(), isEmpty);
    for (final n in ['kept.S01E01.mkv', 'kept.S01E02.mkv', 'kept.S01E03.mkv']) {
      expect(File(p.join(tmp.path, n)).existsSync(), isTrue, reason: n);
    }

    // Un-pinning lets them reap again.
    await saved.setKeep(
        tmdbId: 555, mediaType: 'tv', name: 'Kept Show', value: false);
    expect((await (await reaper()).sweep()).length, 3);
  });
}
