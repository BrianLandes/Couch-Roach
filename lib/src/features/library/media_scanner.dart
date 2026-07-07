import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart' show ScannedFile;

/// Walks every configured storage root and turns video files into
/// [ScannedFile]s using filename-derived titles. TMDB matching happens later
/// (M2) — this is the M1 scanner (see DECISIONS: TMDB matching in M1).
@lazySingleton
class MediaScanner {
  MediaScanner(this._storage);

  final StorageManager _storage;

  static const _videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.m4v', '.webm', '.ts', '.wmv', '.flv',
  };

  // Directories we never descend into: OS-managed junk that's unreadable anyway
  // (Windows recycle bin, restore metadata) or filesystem bookkeeping. Anything
  // starting with `$` (e.g. `$RECYCLE.BIN`, `$Recycle.Bin`) is skipped too.
  static const _skipDirNames = {
    'system volume information',
    'lost+found',
    '.trash-1000',
    '#recycle',
  };

  // Show.Name.S01E02.1080p... / Show Name - S01E02 / Show.1x02
  static final _tvPattern = RegExp(
    r'^(?<title>.+?)[\s._-]+[sS](?<season>\d{1,2})[\s._-]*[eE](?<episode>\d{1,3})',
  );
  static final _tvAltPattern = RegExp(
    r'^(?<title>.+?)[\s._-]+(?<season>\d{1,2})x(?<episode>\d{1,3})',
  );

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

  ScannedFile _parse(String filePath) {
    final name = p.basenameWithoutExtension(filePath);
    final match = _tvPattern.firstMatch(name) ?? _tvAltPattern.firstMatch(name);
    if (match != null) {
      return ScannedFile(
        filePath: filePath,
        title: _clean(match.namedGroup('title')!),
        mediaType: 'tv',
        season: int.tryParse(match.namedGroup('season')!),
        episode: int.tryParse(match.namedGroup('episode')!),
      );
    }
    return ScannedFile(
      filePath: filePath,
      title: _clean(name),
      mediaType: 'movie',
    );
  }

  String _clean(String raw) =>
      raw.replaceAll(RegExp(r'[._]'), ' ').trim();
}
