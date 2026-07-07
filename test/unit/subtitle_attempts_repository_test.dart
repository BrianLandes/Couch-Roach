import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/subtitle_attempts_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftLibraryRepository library;
  late DriftSubtitleAttemptsRepository attempts;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = DriftLibraryRepository(db);
    attempts = DriftSubtitleAttemptsRepository(db);
  });
  tearDown(() async => db.close());

  Future<int> addItem(String path, {bool missing = false}) async {
    await library.upsert(ScannedFile(
      filePath: path,
      title: path.split('/').last,
      mediaType: 'movie',
    ));
    final row = (await library.findByPath(path))!;
    if (missing) {
      await (db.update(db.libraryItems)..where((t) => t.id.equals(row.id)))
          .write(const LibraryItemsCompanion(missing: Value(true)));
    }
    return row.id;
  }

  test('itemsNeedingSubtitles returns items with no attempt', () async {
    await addItem('/v/a.mkv');
    await addItem('/v/b.mkv');

    final need = await attempts.itemsNeedingSubtitles();
    expect(need.map((e) => e.filePath), containsAll(['/v/a.mkv', '/v/b.mkv']));
  });

  test('a terminal attempt takes an item out of the queue', () async {
    final a = await addItem('/v/a.mkv');
    await addItem('/v/b.mkv');
    await attempts.record(a, SubtitleAttemptStatus.found);

    final need = await attempts.itemsNeedingSubtitles();
    expect(need.map((e) => e.filePath), ['/v/b.mkv']);
  });

  test('present and not_found are terminal too', () async {
    final a = await addItem('/v/a.mkv');
    final b = await addItem('/v/b.mkv');
    await addItem('/v/c.mkv');
    await attempts.record(a, SubtitleAttemptStatus.present);
    await attempts.record(b, SubtitleAttemptStatus.notFound);

    final need = await attempts.itemsNeedingSubtitles();
    expect(need.map((e) => e.filePath), ['/v/c.mkv']);
  });

  test('a transient attempt (quota) leaves the item eligible', () async {
    final a = await addItem('/v/a.mkv');
    await attempts.record(a, SubtitleAttemptStatus.quota);

    final need = await attempts.itemsNeedingSubtitles();
    expect(need.map((e) => e.filePath), ['/v/a.mkv']);
  });

  test('missing items are excluded', () async {
    await addItem('/v/gone.mkv', missing: true);
    await addItem('/v/here.mkv');

    final need = await attempts.itemsNeedingSubtitles();
    expect(need.map((e) => e.filePath), ['/v/here.mkv']);
  });

  test('limit bounds the batch', () async {
    for (var i = 0; i < 5; i++) {
      await addItem('/v/$i.mkv');
    }
    expect(await attempts.itemsNeedingSubtitles(limit: 2), hasLength(2));
  });

  test('downloadsToday counts only found rows from today', () async {
    final a = await addItem('/v/a.mkv');
    final b = await addItem('/v/b.mkv');
    final c = await addItem('/v/c.mkv');

    await attempts.record(a, SubtitleAttemptStatus.found); // counts
    await attempts.record(b, SubtitleAttemptStatus.present); // not a download
    await attempts.record(c, SubtitleAttemptStatus.notFound); // not a download
    // A found row from yesterday must not count.
    await db.into(db.subtitleAttempts).insert(
          SubtitleAttemptsCompanion.insert(
            libraryItemId: a,
            status: SubtitleAttemptStatus.found.wire,
            attemptedAt: Value(DateTime.now().subtract(const Duration(days: 1))),
          ),
        );

    expect(await attempts.downloadsToday(), 1);
  });
}
