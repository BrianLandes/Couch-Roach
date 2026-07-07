import 'dart:io';

/// A configured storage root (one per disk, typically).
class StorageRoot {
  const StorageRoot({
    required this.path,
    this.label,
    this.enabled = true,
    this.priority = 0,
  });

  final String path;
  final String? label;
  final bool enabled;
  final int priority;
}

/// Spreads content across multiple disks and answers "where should this file
/// go / where does the library live" (see DECISIONS: multi-disk storage).
///
/// The library scanner reads *all* enabled roots. New downloads pick a target
/// by free space above a floor.
abstract class StorageManager {
  /// All enabled roots, to be scanned for existing media.
  List<StorageRoot> get roots;

  /// Choose a download target disk with enough free space for [estimatedBytes].
  /// Returns the root path, or null if none has room above the floor.
  Future<String?> chooseTarget({required int estimatedBytes});

  /// Free bytes available on the volume containing [path].
  Future<int?> freeSpaceBytes(String path);
}

class ConfiguredStorageManager implements StorageManager {
  ConfiguredStorageManager(
    this._roots, {
    this.minFreeFloorBytes = 5 * 1024 * 1024 * 1024, // keep 5 GB headroom
  });

  final List<StorageRoot> _roots;
  final int minFreeFloorBytes;

  @override
  List<StorageRoot> get roots =>
      _roots.where((r) => r.enabled).toList(growable: false);

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
    // TODO(storage): Dart has no cross-platform free-space API. Implement via a
    // small platform channel — Win32 GetDiskFreeSpaceEx on Windows, statvfs on
    // Linux — or a maintained package. Until then, target selection is inert.
    if (!Directory(path).existsSync()) return null;
    return null;
  }
}
