import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/services/cleanup/media_deleter.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftLibraryRepository library;
  late MediaDeleter deleter;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = DriftLibraryRepository(db);
    deleter = MediaDeleter(library, ErrorLogService());
    tmp = await Directory.systemTemp.createTemp('cr_del');
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String sidecar(String videoPath) => p.join(
      p.dirname(videoPath), '${p.basenameWithoutExtension(videoPath)}.en.srt');

  Future<LibraryItem> add(String name, {bool withSidecar = true}) async {
    final path = p.join(tmp.path, name);
    File(path).writeAsStringSync('video');
    if (withSidecar) File(sidecar(path)).writeAsStringSync('subs');
    await library
        .upsert(ScannedFile(filePath: path, title: name, mediaType: 'movie'));
    return (await library.findByPath(path))!;
  }

  test('deleteItem removes the video + sidecar and the row', () async {
    final item = await add('Movie.mkv');
    final path = item.filePath;

    expect(await deleter.deleteItem(item), isTrue);
    expect(File(path).existsSync(), isFalse);
    expect(File(sidecar(path)).existsSync(), isFalse);
    expect(await library.findByPath(path), isNull);
  });

  test('a missing file still removes the row (forget a gone title)', () async {
    final item = await add('Gone.mkv', withSidecar: false);
    File(item.filePath).deleteSync(); // drive disconnected / already gone

    expect(await deleter.deleteItem(item), isTrue);
    expect(await library.findByPath(item.filePath), isNull);
  });

  test('deleteItems returns how many rows were removed', () async {
    final a = await add('A.mkv');
    final b = await add('B.mkv');
    final c = await add('C.mkv');

    expect(await deleter.deleteItems([a, b, c]), 3);
    expect(await library.getAll(), isEmpty);
  });

  test('deleting one title leaves the others untouched', () async {
    final a = await add('A.mkv');
    await add('B.mkv');

    await deleter.deleteItem(a);
    final left = await library.getAll();
    expect(left.map((e) => e.title), ['B.mkv']);
    expect(File(p.join(tmp.path, 'B.mkv')).existsSync(), isTrue);
  });
}
