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

  // Show.Name.S01E02.1080p... / Show Name - S01E02 / Show.1x02
  static final _tvPattern = RegExp(
    r'^(?<title>.+?)[\s._-]+[sS](?<season>\d{1,2})[\s._-]*[eE](?<episode>\d{1,3})',
  );
  static final _tvAltPattern = RegExp(
    r'^(?<title>.+?)[\s._-]+(?<season>\d{1,2})x(?<episode>\d{1,3})',
  );

  Stream<ScannedFile> scan() async* {
    for (final root in _storage.roots) {
      final dir = Directory(root.path);
      if (!dir.existsSync()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_videoExtensions.contains(ext)) continue;
        yield _parse(entity.path);
      }
    }
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
