import 'dart:async';
import 'dart:io';

import '../../data/repositories/storage_repository.dart';
import '../logging/error_log_service.dart';
import 'disk_space.dart';
import 'storage_root.dart';

export 'storage_root.dart';

/// Spreads content across multiple disks and answers "where does the library
/// live / where should this download go" (see DECISIONS: multi-disk storage).
///
/// Backed by the `storage_locations` table via [StorageRepository]. Call [load]
/// once at startup; after that the cached [roots] stay in sync with the DB, and
/// mutations ([addRoot] / [removeRoot] / [setEnabled]) persist.
abstract class StorageManager {
  /// Enabled roots, to be scanned for existing media. Synchronous — reads the
  /// cache populated by [load]; empty until then.
  List<StorageRoot> get roots;

  /// Load roots from the DB and start tracking changes. Await before scanning.
  Future<void> load();

  Future<void> addRoot({required String path, String? label});
  Future<void> removeRoot(int id);
  Future<void> setEnabled(int id, bool enabled);

  /// Choose a download target disk with enough free space for [estimatedBytes].
  /// Returns the root path, or null if none has room above the floor.
  Future<String?> chooseTarget({required int estimatedBytes});

  /// Free bytes available on the volume containing [path].
  Future<int?> freeSpaceBytes(String path);
}

class ConfiguredStorageManager implements StorageManager {
  ConfiguredStorageManager(
    this._repo, {
    this.minFreeFloorBytes = 5 * 1024 * 1024 * 1024, // keep 5 GB headroom
    ErrorLogService? log,
  }) : _log = log;

  final StorageRepository _repo;
  final int minFreeFloorBytes;
  final ErrorLogService? _log;

  List<StorageRoot> _cached = const [];
  StreamSubscription<List<StorageRoot>>? _sub;

  @override
  Future<void> load() async {
    _cached = await _repo.getRoots();
    _sub ??= _repo.watchRoots().listen((roots) => _cached = roots);
  }

  @override
  List<StorageRoot> get roots =>
      _cached.where((r) => r.enabled).toList(growable: false);

  @override
  Future<void> addRoot({required String path, String? label}) =>
      _repo.addRoot(path: path, label: label);

  @override
  Future<void> removeRoot(int id) => _repo.removeRoot(id);

  @override
  Future<void> setEnabled(int id, bool enabled) =>
      _repo.setEnabled(id, enabled);

  @override
  Future<String?> chooseTarget({required int estimatedBytes}) async {
    String? best;
    var bestFree = -1;
    for (final root in roots) {
      final free = await freeSpaceBytes(root.path);
      if (free == null) continue;
      if (free - estimatedBytes < minFreeFloorBytes) continue;
      if (free > bestFree) {
        bestFree = free;
        best = root.path;
      }
    }
    return best;
  }

  @override
  Future<int?> freeSpaceBytes(String path) async {
    if (!Directory(path).existsSync()) return null;
    try {
      return await freeDiskSpaceBytes(path);
    } catch (e, st) {
      _log?.logError(e, stackTrace: st, source: 'StorageManager.freeSpaceBytes');
      return null;
    }
  }
}
