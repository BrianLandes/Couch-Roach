import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../core/storage/storage_root.dart';
import '../db/database.dart';

/// Read/write access to the configured storage roots (`storage_locations`).
abstract class StorageRepository {
  Future<List<StorageRoot>> getRoots();
  Stream<List<StorageRoot>> watchRoots();

  /// Adds a root. A duplicate path is ignored (path is unique).
  Future<void> addRoot({required String path, String? label});
  Future<void> removeRoot(int id);
  Future<void> setEnabled(int id, bool enabled);
}

@LazySingleton(as: StorageRepository)
class DriftStorageRepository implements StorageRepository {
  DriftStorageRepository(this._db);

  final AppDatabase _db;

  StorageRoot _map(StorageLocation r) => StorageRoot(
        id: r.id,
        path: r.path,
        label: r.label,
        enabled: r.enabled,
        priority: r.priority,
      );

  @override
  Future<List<StorageRoot>> getRoots() async {
    final rows = await (_db.select(_db.storageLocations)
          ..orderBy([(t) => OrderingTerm(expression: t.priority)]))
        .get();
    return rows.map(_map).toList();
  }

  @override
  Stream<List<StorageRoot>> watchRoots() {
    return (_db.select(_db.storageLocations)
          ..orderBy([(t) => OrderingTerm(expression: t.priority)]))
        .watch()
        .map((rows) => rows.map(_map).toList());
  }

  @override
  Future<void> addRoot({required String path, String? label}) async {
    await _db.into(_db.storageLocations).insert(
          StorageLocationsCompanion.insert(path: path, label: Value(label)),
          mode: InsertMode.insertOrIgnore, // path is unique — ignore dupes
        );
  }

  @override
  Future<void> removeRoot(int id) async {
    await (_db.delete(_db.storageLocations)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> setEnabled(int id, bool enabled) async {
    await (_db.update(_db.storageLocations)..where((t) => t.id.equals(id)))
        .write(StorageLocationsCompanion(enabled: Value(enabled)));
  }
}
