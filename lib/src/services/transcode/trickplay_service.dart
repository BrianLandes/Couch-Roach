import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/media/ffmpeg.dart';
import '../../core/media/playback_activity.dart';
import '../../core/media/video_extensions.dart';
import '../../data/repositories/library_repository.dart';
import '../acquisition/acquisition.dart';
import '../subtitles/subtitle_skip_check.dart';
import 'downscale_command.dart';
import 'trickplay.dart';

/// Builds and serves the seek-bar preview sheets (see trickplay.dart).
///
/// Runs only while nothing is playing — it decodes on the same CPU/GPU the
/// player needs — and kills its ffmpeg the moment playback starts. Newest
/// library files first, so what was just downloaded is ready soonest.
///
/// **The cache is the state.** A file's sheets live in
/// `<app-support>/trickplay/<key>/`, keyed by path + size + mtime, and count as
/// done only once `manifest.json` exists. No schema, nothing to drift: a changed
/// file simply has a new key, and directories no library file maps to any more
/// are pruned after a full pass.
@LazySingleton()
class TrickplayService {
  TrickplayService(this._library, this._daemon, this._log);

  final LibraryRepository _library;
  final TorrentDaemon _daemon;
  final ErrorLogService _log;

  /// Overrides the cache directory (tests).
  @visibleForTesting
  Directory? rootOverride;

  /// Files modified this recently are presumed still being written (a
  /// download, a downscale swap) and are left for a later sweep.
  static const settleTime = Duration(minutes: 5);

  bool _busy = false;
  bool? _ffmpegOk;
  Process? _proc;

  /// Keys already attempted this session, so a file ffmpeg can't handle isn't
  /// retried every sweep. A changed file has a new key and gets a fresh try.
  final Set<String> _attempted = {};

  Future<Directory> _root() async {
    final override = rootOverride;
    if (override != null) return override;
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'trickplay'));
  }

  /// The cache key for [filePath] as it is on disk now, or null if it's gone.
  Future<String?> _keyFor(String filePath) async {
    try {
      final stat = await File(filePath).stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return trickplayKey(
        path: filePath,
        sizeBytes: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }

  /// The finished preview sheets for [filePath], or null when none exist yet.
  /// Cheap (a stat and a small read) — the player calls it on open.
  Future<TrickplaySheets?> sheetsFor(String filePath) async {
    try {
      final key = await _keyFor(filePath);
      if (key == null) return null;
      final dir = p.join((await _root()).path, key);
      final manifestFile = File(p.join(dir, kTrickplayManifestName));
      if (!await manifestFile.exists()) return null;
      final manifest =
          TrickplayManifest.tryParse(await manifestFile.readAsString());
      return manifest == null ? null : TrickplaySheets(dir, manifest);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'TrickplayService.sheetsFor');
      return null;
    }
  }

  /// Generate previews for every library video that lacks them, newest first,
  /// until done or a video starts playing. Returns how many files it finished.
  Future<int> sweep() async {
    if (_busy || playbackActive.value) return 0;
    _busy = true;
    void standDown() {
      if (playbackActive.value) _proc?.kill();
    }

    playbackActive.addListener(standDown);
    var made = 0;
    try {
      if (!await _ffmpegAvailable()) return 0;
      final root = await _root();
      final incomplete = await _incompleteDownloads();
      final items = (await _library.getAll())
          .where((i) =>
              !i.missing &&
              kVideoExtensions
                  .contains(p.extension(i.filePath).toLowerCase()))
          .toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

      final liveKeys = <String>{};
      var finishedPass = true;
      for (final item in items) {
        final key = await _keyFor(item.filePath);
        if (key == null) continue;
        liveKeys.add(key);
        if (playbackActive.value) {
          finishedPass = false;
          break;
        }
        if (_attempted.contains(key)) continue;
        if (incomplete.contains(p.normalize(item.filePath))) continue;
        final dir = Directory(p.join(root.path, key));
        if (await File(p.join(dir.path, kTrickplayManifestName)).exists()) {
          continue;
        }
        final modified = await File(item.filePath).lastModified();
        if (DateTime.now().difference(modified) < settleTime) continue;

        _attempted.add(key);
        if (await _generate(item.filePath, dir)) made++;
      }
      if (finishedPass) await _prune(root, liveKeys);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'TrickplayService.sweep');
    } finally {
      playbackActive.removeListener(standDown);
      _busy = false;
    }
    return made;
  }

  Future<bool> _ffmpegAvailable() async {
    final ok = _ffmpegOk ??= await ffmpegAvailable();
    if (!ok) {
      _log.info('seek previews unavailable: no ffmpeg',
          source: 'TrickplayService');
    }
    return ok;
  }

  /// Absolute paths of files our torrents haven't finished — thumbnails of a
  /// half-downloaded file would be garbage past the downloaded part.
  Future<Set<String>> _incompleteDownloads() async {
    final out = <String>{};
    try {
      for (final t in await _daemon.listTorrents()) {
        if (t.isComplete || t.savePath.isEmpty) continue;
        for (final f in await _daemon.torrentFiles(t.hash)) {
          final name = f['name'] as String?;
          final progress = (f['progress'] as num?)?.toDouble() ?? 0;
          if (name != null && progress < 1.0) {
            out.add(p.normalize(p.join(t.savePath, name)));
          }
        }
      }
    } catch (_) {
      // Daemon down: the settle-time check still guards files being written.
    }
    return out;
  }

  /// Run ffmpeg into a temp directory, check every expected sheet landed, then
  /// write the manifest and move the directory into place — so a killed or
  /// failed run never leaves a directory that looks finished.
  Future<bool> _generate(String filePath, Directory dir) async {
    final duration = await _durationOf(filePath);
    if (duration == null || duration <= 0) {
      _log.info('seek previews skipped (no duration): $filePath',
          source: 'TrickplayService');
      return false;
    }
    final tiles = trickplayTileCount(duration);
    final sheets = trickplaySheetCount(tiles);
    final temp = Directory('${dir.path}.partial');
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
      await temp.create(recursive: true);
      _log.info('building seek previews ($tiles tiles): $filePath',
          source: 'TrickplayService');
      final proc = _proc = await Process.start(
          ffmpegCommand(), trickplayArgs(input: filePath, outputDir: temp.path));
      final errText = StringBuffer();
      final errDone = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(errText.write)
          .asFuture<void>();
      await proc.stdout.drain<void>();
      final exitCode = await proc.exitCode;
      await errDone;
      _proc = null;

      if (playbackActive.value) {
        // Killed to make way for the player — not a failure; try again later.
        _attempted.remove(p.basename(dir.path));
        await temp.delete(recursive: true);
        return false;
      }
      final missing = [
        for (var i = 0; i < sheets; i++)
          if (!File(p.join(temp.path, trickplaySheetName(i))).existsSync()) i,
      ];
      if (exitCode != 0 || missing.isNotEmpty) {
        _log.warn(
            'seek previews failed (exit $exitCode, '
            '${missing.length}/$sheets sheets missing) for $filePath: '
            '${errText.toString().trim()}',
            source: 'TrickplayService');
        await temp.delete(recursive: true);
        return false;
      }
      await File(p.join(temp.path, kTrickplayManifestName)).writeAsString(
          jsonEncode(
              TrickplayManifest(tileCount: tiles, sheetCount: sheets).toJson()));
      if (await dir.exists()) await dir.delete(recursive: true);
      await temp.rename(dir.path);
      _log.info('seek previews ready: $filePath', source: 'TrickplayService');
      return true;
    } catch (e, st) {
      _proc = null;
      _log.logError(e, stackTrace: st, source: 'TrickplayService.generate');
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } catch (_) {}
      return false;
    }
  }

  Future<double?> _durationOf(String path) async {
    try {
      final res = await Process.run(
          SubtitleSkipCheck.ffprobeCommand(), probeVideoStreamArgs(path));
      return parseFfprobeDurationSeconds('${res.stdout}');
    } catch (_) {
      return null;
    }
  }

  /// Delete cache directories no current library file maps to (deleted,
  /// reaped, downscaled, or re-downloaded files), and stray partials.
  Future<void> _prune(Directory root, Set<String> liveKeys) async {
    if (!await root.exists()) return;
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (liveKeys.contains(name)) continue;
      try {
        await entry.delete(recursive: true);
      } catch (e) {
        _log.warn('could not prune ${entry.path}: $e',
            source: 'TrickplayService');
      }
    }
  }
}

/// A finished set of sheets on disk: the manifest plus where they live.
class TrickplaySheets {
  const TrickplaySheets(this.directory, this.manifest);
  final String directory;
  final TrickplayManifest manifest;

  String sheetPath(int index) =>
      p.join(directory, trickplaySheetName(index));
}
