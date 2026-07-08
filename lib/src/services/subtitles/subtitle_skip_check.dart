import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/process/bundled_executable.dart';

/// Decides whether a video already has English subtitles, so the fetcher can
/// skip it (HANDOFF §4.6 step 1). Tries cheapest-first:
///   1. a `.srt` sidecar next to the file,
///   2. `ffprobe` (if it's on PATH) to read embedded subtitle streams,
///   3. media_kit/libmpv as the last resort (opens the file to read its tracks).
@LazySingleton()
class SubtitleSkipCheck {
  SubtitleSkipCheck(this._log);

  final ErrorLogService _log;

  Future<bool> hasEnglish(String videoPath) async {
    final sidecar = englishSidecarPath(videoPath);
    if (sidecar != null) {
      _log.info('skip-check: English sidecar already present ($sidecar)',
          source: 'SubtitleSkipCheck');
      return true;
    }

    final viaFfprobe = await _ffprobeEmbeddedEnglish(videoPath);
    if (viaFfprobe != null) {
      _log.info(
          'skip-check: ffprobe ${viaFfprobe ? 'found an' : 'found no'} '
          'embedded English subtitle track',
          source: 'SubtitleSkipCheck');
      return viaFfprobe;
    }

    final viaMediaKit = await _mediaKitEmbeddedEnglish(videoPath);
    _log.info(
        'skip-check: ffprobe unavailable, media_kit '
        '${viaMediaKit ? 'found an' : 'found no'} embedded English track',
        source: 'SubtitleSkipCheck');
    return viaMediaKit;
  }

  // ── 1. Sidecar ─────────────────────────────────────────────────────────────
  static const _sidecarSuffixes = ['.en.srt', '.eng.srt', '.english.srt', '.srt'];

  static bool hasEnglishSidecar(String videoPath) =>
      englishSidecarPath(videoPath) != null;

  /// The path of an existing English `.srt` sidecar next to [videoPath], or null
  /// if there isn't one. Lets a caller reuse the sidecar it already has instead
  /// of re-downloading.
  static String? englishSidecarPath(String videoPath) {
    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    for (final suffix in _sidecarSuffixes) {
      final candidate = p.join(dir, '$base$suffix');
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  // ── 2. ffprobe (null when unavailable → fall through) ──────────────────────

  /// The ffprobe command to run: the copy the packaging step bundles next to the
  /// app executable if present (resolved by absolute path — Linux `Process.run`
  /// doesn't search the exe's own directory), else the bare name off PATH so a
  /// dev machine with ffmpeg installed still works. Static + pure-ish (only reads
  /// the filesystem) so the resolution is exercised in tests.
  static String ffprobeCommand() {
    final name = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    return bundledExecutable([name]) ?? name;
  }

  Future<bool?> _ffprobeEmbeddedEnglish(String path) async {
    try {
      final res = await Process.run(ffprobeCommand(), [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_streams',
        path,
      ]);
      if (res.exitCode != 0) return null;
      return ffprobeJsonHasEnglish(res.stdout as String);
    } on ProcessException {
      return null; // ffprobe not installed — let the next layer try
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'SubtitleSkipCheck.ffprobe');
      return null;
    }
  }

  /// Parses `ffprobe -show_streams -print_format json` output for an English
  /// subtitle stream. Static + pure so it's unit-testable.
  static bool ffprobeJsonHasEnglish(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final streams = (json['streams'] as List<dynamic>?) ?? const [];
      for (final entry in streams) {
        final stream = entry as Map<String, dynamic>;
        if (stream['codec_type'] != 'subtitle') continue;
        final tags = (stream['tags'] as Map<String, dynamic>?) ?? const {};
        final lang = (tags['language'] ?? tags['LANGUAGE'])?.toString();
        final title = (tags['title'] ?? tags['TITLE'])?.toString();
        if (isEnglish(lang, title)) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── 3. media_kit / libmpv fallback ─────────────────────────────────────────
  Future<bool> _mediaKitEmbeddedEnglish(String path) async {
    final player = Player();
    try {
      await player.open(Media(path), play: false);
      // Give libmpv a moment to parse the container and populate tracks.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return player.state.tracks.subtitle
          .any((s) => isEnglish(s.language, s.title));
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'SubtitleSkipCheck.mediaKit');
      return false; // inconclusive → treat as "no English" (safe: we'll fetch)
    } finally {
      await player.dispose();
    }
  }

  /// True when a track's `language`/`title` names English (`en`/`eng`/`english`,
  /// or a title mentioning "english"). Shared with the player so a downloaded
  /// sidecar isn't loaded on top of an English track libmpv already has.
  static bool isEnglish(String? language, String? title) {
    final l = language?.toLowerCase();
    if (l == 'en' || l == 'eng' || l == 'english') return true;
    final t = title?.toLowerCase();
    return t != null && t.contains('english');
  }
}
