import 'dart:io';

import 'package:couch_roach/src/core/storage/storage_manager.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/storage_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1024 * 1024 * 1024;

/// Manager with canned free-space so target selection can be tested without
/// touching real disks.
class _StubSpaceManager extends ConfiguredStorageManager {
  _StubSpaceManager(
    super.repo,
    this._free, {
    super.minFreeFloorBytes,
  });

  final Map<String, int?> _free;

  @override
  Future<int?> freeSpaceBytes(String path) async => _free[path];
}

void main() {
  late AppDatabase db;
  late DriftStorageRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftStorageRepository(db);
  });
  tearDown(() => db.close());

  Future<_StubSpaceManager> managerWith(
    Map<String, int?> free, {
    int floor = 5 * _gb,
  }) async {
    for (final path in free.keys) {
      await repo.addRoot(path: path);
    }
    final mgr = _StubSpaceManager(repo, free, minFreeFloorBytes: floor);
    await mgr.load();
    return mgr;
  }

  group('chooseTarget', () {
    test('picks the disk with the most free space', () async {
      final mgr = await managerWith({
        '/a': 100 * _gb,
        '/b': 200 * _gb,
        '/c': 50 * _gb,
      });
      expect(await mgr.chooseTarget(estimatedBytes: 10 * _gb), '/b');
    });

    test('skips a disk that would drop below the floor', () async {
      final mgr = await managerWith({
        '/small': 6 * _gb, // 6 - 10 = -4 GB, under the 5 GB floor
        '/big': 200 * _gb,
      });
      expect(await mgr.chooseTarget(estimatedBytes: 10 * _gb), '/big');
    });

    test('returns null when nothing has room above the floor', () async {
      final mgr = await managerWith({'/a': 6 * _gb, '/b': 8 * _gb});
      expect(await mgr.chooseTarget(estimatedBytes: 10 * _gb), isNull);
    });

    test('ignores a root whose free space could not be read', () async {
      final mgr = await managerWith({'/broken': null, '/ok': 100 * _gb});
      expect(await mgr.chooseTarget(estimatedBytes: 10 * _gb), '/ok');
    });

    test('accounts for the estimated size against the floor', () async {
      // 20 GB free, 5 GB floor: a 14 GB download fits (leaves 6), 16 doesn't.
      final mgr = await managerWith({'/a': 20 * _gb});
      expect(await mgr.chooseTarget(estimatedBytes: 14 * _gb), '/a');
      expect(await mgr.chooseTarget(estimatedBytes: 16 * _gb), isNull);
    });
  });

  group('freeSpaceBytes (real probe)', () {
    test('returns a positive byte count for a real directory', () async {
      final mgr = ConfiguredStorageManager(repo);
      final tmp = await Directory.systemTemp.createTemp('cr_space');
      try {
        final free = await mgr.freeSpaceBytes(tmp.path);
        expect(free, isNotNull);
        expect(free, greaterThan(0));
      } finally {
        tmp.deleteSync();
      }
    });

    test('is null for a path that does not exist', () async {
      final mgr = ConfiguredStorageManager(repo);
      expect(await mgr.freeSpaceBytes('/no/such/dir/cr_xyz_123'), isNull);
    });
  });
}
