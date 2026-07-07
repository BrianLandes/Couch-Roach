import 'package:couch_roach/src/core/storage/storage_manager.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/storage_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercises the real drift schema against an in-memory DB (see CLAUDE.md →
// Testing). Catches migration/constraint issues mocks can't.
void main() {
  late AppDatabase db;
  late StorageRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftStorageRepository(db);
  });
  tearDown(() async => db.close());

  group('StorageRepository', () {
    test('adds and reads back roots', () async {
      await repo.addRoot(path: '/media/a', label: 'A');
      await repo.addRoot(path: '/media/b');
      final roots = await repo.getRoots();
      expect(roots.map((r) => r.path), containsAll(['/media/a', '/media/b']));
      expect(roots.every((r) => r.enabled), isTrue);
    });

    test('ignores a duplicate path (unique)', () async {
      await repo.addRoot(path: '/media/a');
      await repo.addRoot(path: '/media/a');
      expect((await repo.getRoots()).length, 1);
    });

    test('toggles enabled and removes', () async {
      await repo.addRoot(path: '/media/a');
      final id = (await repo.getRoots()).single.id!;

      await repo.setEnabled(id, false);
      expect((await repo.getRoots()).single.enabled, isFalse);

      await repo.removeRoot(id);
      expect(await repo.getRoots(), isEmpty);
    });
  });

  group('ConfiguredStorageManager', () {
    test('load() exposes only enabled roots', () async {
      await repo.addRoot(path: '/media/a');
      await repo.addRoot(path: '/media/b');
      final id = (await repo.getRoots()).first.id!;
      await repo.setEnabled(id, false);

      final manager = ConfiguredStorageManager(repo);
      await manager.load();

      expect(manager.roots.length, 1);
      expect(manager.roots.single.enabled, isTrue);
    });

    test('mutations persist through the repository', () async {
      final manager = ConfiguredStorageManager(repo);
      await manager.load();
      expect(manager.roots, isEmpty);

      await manager.addRoot(path: '/media/a');
      expect((await repo.getRoots()).single.path, '/media/a');
    });
  });
}
