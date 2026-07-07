import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';

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
    if (hasEnglishSidecar(videoPath)) return true;

    final viaFfprobe = await _ffprobeEmbeddedEnglish(videoPath);
    if (viaFfprobe != null) return viaFfprobe;

    return _mediaKitEmbeddedEnglish(videoPath);
  }

  // ── 1. Sidecar ─────────────────────────────────────────────────────────────
  static bool hasEnglishSidecar(String videoPath) {
    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    const suffixes = ['.en.srt', '.eng.srt', '.english.srt', '.srt'];
    for (final suffix in suffixes) {
      if (File(p.join(dir, '$base$suffix')).existsSync()) return true;
    }
    return false;
  }

  // ── 2. ffprobe (null when unavailable → fall through) ──────────────────────
  Future<bool?> _ffprobeEmbeddedEnglish(String path) async {
    try {
      final res = await Process.run('ffprobe', [
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
        if (_isEnglish(lang, title)) return true;
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
          .any((s) => _isEnglish(s.language, s.title));
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'SubtitleSkipCheck.mediaKit');
      return false; // inconclusive → treat as "no English" (safe: we'll fetch)
    } finally {
      await player.dispose();
    }
  }

  static bool _isEnglish(String? language, String? title) {
    final l = language?.toLowerCase();
    if (l == 'en' || l == 'eng' || l == 'english') return true;
    final t = title?.toLowerCase();
    return t != null && t.contains('english');
  }
}
