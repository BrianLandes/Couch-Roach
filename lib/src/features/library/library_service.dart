import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart';
import 'media_scanner.dart';

/// Orchestrates library scans: walk every storage root, persist what's found
/// through [LibraryRepository], and reconcile what's gone. Kicked off at startup
/// and by the manual "Rescan" action.
@LazySingleton()
class LibraryService {
  LibraryService(this._scanner, this._library, this._storage, this._log);

  final MediaScanner _scanner;
  final LibraryRepository _library;
  final StorageManager _storage;
  final ErrorLogService _log;

  // Upsert in chunks so a large root streams into the grid instead of landing
  // in one big write at the end.
  static const _batchSize = 200;

  final ValueNotifier<bool> _scanning = ValueNotifier(false);

  /// True while a scan is running — the UI watches this to show progress and
  /// disable the Rescan button.
  ValueListenable<bool> get scanning => _scanning;
  bool get isScanning => _scanning.value;

  /// Scan every enabled root and reconcile the library with disk. Safe to call
  /// concurrently — a second call while one is running is a no-op.
  Future<void> rescan() async {
    if (_scanning.value) return;
    _scanning.value = true;
    try {
      for (final root in _storage.roots) {
        // Isolate per root: a permission error or offline disk on one root must
        // not abort the others, and only this root's rows get reconciled.
        try {
          final present = <String>{};
          final buffer = <ScannedFile>[];
          await for (final file in _scanner.scanRoot(root.path)) {
            present.add(file.filePath);
            buffer.add(file);
            if (buffer.length >= _batchSize) {
              await _library.upsertAll(buffer);
              buffer.clear();
            }
          }
          if (buffer.isNotEmpty) await _library.upsertAll(buffer);
          await _library.markMissingUnder(
            rootPath: root.path,
            presentPaths: present,
          );
        } catch (e, st) {
          _log.logError(e, stackTrace: st, source: 'LibraryService.rescan(${root.path})');
        }
      }
    } finally {
      _scanning.value = false;
    }
  }
}
