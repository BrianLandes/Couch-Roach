import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';
import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import 'media_file_delete.dart';

/// Manual deletion of downloaded titles — the user-driven counterpart to the
/// [WatchedReaper]'s auto-cleanup. Both remove the same files
/// ([deleteMediaFileAndSidecars]), but where the reaper keeps the row (flags it
/// `missing`) so watch history survives an auto-cleanup, an explicit delete is a
/// "forget this entirely": it hard-removes the row and cascades its watch
/// history. An explicit delete ignores the `keep` pin — the user asked for it.
@LazySingleton()
class MediaDeleter {
  MediaDeleter(this._library, this._log);

  final LibraryRepository _library;
  final ErrorLogService _log;

  /// Delete one item's video + English sidecars, then hard-remove its row.
  /// Best-effort: a file on a disconnected drive still removes the row. Returns
  /// true when the row was removed, false (logged) on error.
  Future<bool> deleteItem(LibraryItem item) async {
    try {
      deleteMediaFileAndSidecars(item.filePath);
      await _library.removeByPath(item.filePath);
      _log.info('deleted "${item.tmdbName ?? item.title}" (${item.filePath})',
          source: 'MediaDeleter');
      return true;
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'MediaDeleter.deleteItem');
      return false;
    }
  }

  /// Delete a batch (a season, a whole show), returning how many rows were
  /// removed. Each file is independent — one failure doesn't stop the rest.
  Future<int> deleteItems(Iterable<LibraryItem> items) async {
    var removed = 0;
    for (final item in items) {
      if (await deleteItem(item)) removed++;
    }
    return removed;
  }
}
