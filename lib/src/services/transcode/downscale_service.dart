import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/media/ffmpeg.dart';
import '../../core/media/playback_activity.dart';
import '../../core/media/video_extensions.dart';
import '../../core/settings/settings_service.dart';
import '../../data/repositories/library_repository.dart';
import '../subtitles/subtitle_skip_check.dart';
import 'downscale_command.dart';

/// A downscale in flight, for the Downloads screen to render.
typedef DownscaleJob = ({String filePath, String title, double? progress});

/// Re-encodes a downloaded file that's too large for this machine to play
/// smoothly down to the user's resolution cap.
///
/// Why: on a box that can't do zero-copy hardware decoding, every frame is
/// hauled between GPU and system memory at the *decoded* resolution — so 4K
/// stutters no matter how small it's drawn (see TASKS.md). The download cap
/// avoids fetching 4K in the common case; this handles the rest, where 4K was
/// the only release available.
///
/// **State is the file itself.** A downscaled file measures at the cap, so the
/// next sweep sees nothing to do — idempotent and self-terminating, with no
/// schema change and no bookkeeping to drift out of sync. Failures are
/// remembered in memory only, so a transient failure gets one more chance on
/// the next launch rather than looping.
@LazySingleton()
class DownscaleService {
  DownscaleService(this._library, this._settings, this._log);

  /// The job running right now, or null when idle. A [ValueListenable] so the
  /// UI can watch it directly — the alternative (polling) would be worse for a
  /// job that reports progress once a second.
  ValueListenable<DownscaleJob?> get current => _current;
  final ValueNotifier<DownscaleJob?> _current = ValueNotifier(null);

  final LibraryRepository _library;
  final SettingsService _settings;
  final ErrorLogService _log;

  bool _busy = false;

  /// Paths we've measured this session, so a sweep doesn't re-probe the whole
  /// library every time. Cleared only by restarting.
  final Map<String, int?> _heightCache = {};

  /// Paths whose downscale failed this session — not retried until restart.
  final Set<String> _failed = {};

  /// Resolved once: the hardware encoder to use, or null when the build has
  /// none (feature stays off).
  String? _encoder;
  bool _encoderResolved = false;

  /// Downscale at most one file. Returns the path it processed, or null when
  /// there was nothing to do.
  ///
  /// One file per sweep on purpose: this is a long, GPU-heavy job and finishing
  /// one title is more useful than making progress on several.
  Future<String?> sweep() async {
    final cap = _settings.maxDownloadHeight;
    if (cap <= 0) return null; // feature is keyed off the download cap
    if (playbackActive.value) return null; // never compete with the player
    if (_busy) return null;

    _busy = true;
    try {
      final encoder = await _resolveEncoder();
      if (encoder == null) return null;

      for (final item in await _library.getAll()) {
        if (item.missing || !item.managed) continue;
        if (!kVideoExtensions.contains(p.extension(item.filePath).toLowerCase())) {
          continue;
        }
        if (_failed.contains(item.filePath)) continue;
        if (!File(item.filePath).existsSync()) continue;

        final height = await _heightOf(item.filePath);
        if (!needsDownscale(height: height, maxHeight: cap)) continue;

        // Re-check: probing and encoding both take time, and the user may have
        // started watching something in between.
        if (playbackActive.value) return null;
        await _downscale(item.filePath, encoder: encoder, maxHeight: cap);
        return item.filePath;
      }
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'DownscaleService.sweep');
    } finally {
      _busy = false;
    }
    return null;
  }

  /// Downscale [filePath] now, ahead of the periodic sweep — the manual
  /// trigger behind the episode menu's "Make it play smoothly".
  ///
  /// Returns null when the job started, or a short human-readable reason it
  /// couldn't. The reasons are surfaced to the user, so this deliberately does
  /// **not** silently no-op the way [sweep] does: someone who asked for this
  /// explicitly deserves to be told why nothing happened.
  Future<String?> requestDownscale(String filePath) async {
    final cap = _settings.maxDownloadHeight;
    if (cap <= 0) {
      return 'Set a maximum download quality in Settings first.';
    }
    if (_busy) return 'Already converting something else.';
    if (playbackActive.value) return 'Not while a video is playing.';
    if (!File(filePath).existsSync()) return "That file isn't on disk.";

    _busy = true;
    try {
      final encoder = await _resolveEncoder();
      if (encoder == null) {
        return 'No hardware video encoder available on this machine.';
      }
      // Re-probe rather than trusting the cache: the user may be asking
      // *because* something changed.
      _heightCache.remove(filePath);
      final height = await _heightOf(filePath);
      if (height == null) return "Couldn't read that file's resolution.";
      if (!needsDownscale(height: height, maxHeight: cap)) {
        return 'Already ${height}p — no conversion needed.';
      }
      _failed.remove(filePath); // an explicit ask overrides an earlier failure
      await _downscale(filePath, encoder: encoder, maxHeight: cap);
      return null;
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'DownscaleService.request');
      return 'Conversion failed — see the error log.';
    } finally {
      _busy = false;
    }
  }

  Future<String?> _resolveEncoder() async {
    if (_encoderResolved) return _encoder;
    _encoderResolved = true;
    try {
      if (!await ffmpegAvailable()) {
        _log.warn('downscale unavailable: no ffmpeg in the sidecar bundle',
            source: 'DownscaleService');
        return null;
      }
      final res = await Process.run(ffmpegCommand(), ['-hide_banner', '-encoders']);
      _encoder = pickHardwareEncoder('${res.stdout}');
      if (_encoder == null) {
        _log.warn(
            'downscale unavailable: this ffmpeg build has no hardware HEVC '
            'encoder (LGPL builds carry no x264/x265, and software encoding 4K '
            'is not viable here)',
            source: 'DownscaleService');
      } else {
        _log.info('downscale will use $_encoder', source: 'DownscaleService');
      }
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'DownscaleService.resolveEncoder');
    }
    return _encoder;
  }

  Future<int?> _heightOf(String path) async {
    if (_heightCache.containsKey(path)) return _heightCache[path];
    int? height;
    try {
      final res = await Process.run(
          SubtitleSkipCheck.ffprobeCommand(), probeVideoStreamArgs(path));
      height = parseFfprobeVideoHeight('${res.stdout}');
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'DownscaleService.probe');
    }
    _heightCache[path] = height;
    return height;
  }

  /// Encode to a temp file beside the original, then swap. The original is only
  /// removed once a plausible output exists, so a crashed or killed encode
  /// leaves the watchable file untouched.
  Future<void> _downscale(String path,
      {required String encoder, required int maxHeight}) async {
    final temp = '$path.downscaling.mkv';
    final title = p.basenameWithoutExtension(path);
    final duration = await _durationOf(path);
    _log.info('downscaling to ${maxHeight}p: $path', source: 'DownscaleService');
    _current.value = (filePath: path, title: title, progress: null);

    try {
      final proc = await Process.start(
        ffmpegCommand(),
        downscaleArgs(
            input: path, output: temp, encoder: encoder, maxHeight: maxHeight),
      );
      // ffmpeg writes a key=value block to stdout once a second under
      // `-progress`; keep the newest output time we recognise.
      final progressDone = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final us = parseFfmpegOutTimeUs(line);
        if (us == null) return;
        _current.value = (
          filePath: path,
          title: title,
          progress: ffmpegProgressFraction(
              outTimeUs: us, durationSeconds: duration),
        );
      });
      // Drain stderr so a chatty encode can't fill the pipe buffer and wedge.
      final errDone = proc.stderr.drain<void>();
      final exitCode = await proc.exitCode;
      await progressDone.cancel();
      await errDone;

      final out = File(temp);
      if (exitCode != 0 || !out.existsSync() || out.lengthSync() <= 0) {
        _failed.add(path);
        if (out.existsSync()) out.deleteSync();
        _log.warn('downscale failed (exit $exitCode): $path',
            source: 'DownscaleService');
        return;
      }
      // Swap in place: the library row's path is unchanged, so watch history,
      // subtitles and the cleanup lifecycle all still point at the right file.
      File(path).deleteSync();
      out.renameSync(path);
      _heightCache[path] = maxHeight;
      _log.info('downscaled $path', source: 'DownscaleService');
    } catch (e, st) {
      _failed.add(path);
      _log.logError(e, stackTrace: st, source: 'DownscaleService.downscale');
    } finally {
      _current.value = null;
    }
  }

  /// Container duration, cached with the height probe it shares a call with.
  Future<double?> _durationOf(String path) async {
    try {
      final res = await Process.run(
          SubtitleSkipCheck.ffprobeCommand(), probeVideoStreamArgs(path));
      return parseFfprobeDurationSeconds('${res.stdout}');
    } catch (_) {
      return null; // an unknown duration just means an indeterminate bar
    }
  }
}
