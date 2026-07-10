import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/media/video_extensions.dart';
import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart' show ScannedFile;
import 'library_path_parse.dart';

/// Walks every configured storage root and turns video files into
/// [ScannedFile]s using filename-derived titles. TMDB matching happens later
/// (M2) — this is the M1 scanner (see DECISIONS: TMDB matching in M1).
@lazySingleton
class MediaScanner {
  MediaScanner(this._storage);

  final StorageManager _storage;

  static const _videoExtensions = kVideoExtensions;

  // Directories we never descend into: OS-managed junk that's unreadable anyway
  // (Windows recycle bin, restore metadata) or filesystem bookkeeping. Anything
  // starting with `$` (e.g. `$RECYCLE.BIN`, `$Recycle.Bin`) is skipped too.
  static const _skipDirNames = {
    'system volume information',
    'lost+found',
    '.trash-1000',
    '#recycle',
  };

  /// Walk every enabled root.
  Stream<ScannedFile> scan() async* {
    for (final root in _storage.roots) {
      yield* scanRoot(root.path);
    }
  }

  /// Walk a single root. Used by the reconcile-per-root scan so an offline disk
  /// only affects its own rows.
  ///
  /// Recurses one directory at a time (rather than `list(recursive: true)`) so a
  /// single unreadable subdirectory — a permission-denied `$RECYCLE.BIN`,
  /// `System Volume Information`, etc. at a drive root — is skipped instead of
  /// aborting the whole scan.
  Stream<ScannedFile> scanRoot(String rootPath) async* {
    final root = Directory(rootPath);
    if (!root.existsSync()) return;

    final stack = <Directory>[root];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      final subdirs = <Directory>[];
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is Directory) {
            if (!_isSkippableDir(entity.path)) subdirs.add(entity);
          } else if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (_videoExtensions.contains(ext)) yield _parse(entity.path);
          }
        }
      } on FileSystemException {
        continue; // unreadable directory — skip it, keep walking the rest
      }
      stack.addAll(subdirs);
    }
  }

  static bool _isSkippableDir(String dirPath) {
    final name = p.basename(dirPath);
    if (name.startsWith(r'$')) return true; // $RECYCLE.BIN, $Recycle.Bin, …
    return _skipDirNames.contains(name.toLowerCase());
  }

  /// Turn a file path into a [ScannedFile], reading the folder layout as well as
  /// the filename (see [parseLibraryPath]) so a `Show/Season NN/…` episode
  /// resolves even when its filename is messy.
  ScannedFile _parse(String filePath) {
    final m = parseLibraryPath(filePath);
    return ScannedFile(
      filePath: filePath,
      title: m.title,
      mediaType: m.mediaType,
      season: m.season,
      episode: m.episode,
    );
  }
}
