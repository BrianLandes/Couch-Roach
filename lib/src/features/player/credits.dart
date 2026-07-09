import 'dart:convert';
import 'dart:io';

import '../../core/process/bundled_executable.dart';

/// A chapter marker within a video file (from ffprobe `-show_chapters`).
class VideoChapter {
  const VideoChapter({required this.start, required this.title});
  final Duration start;
  final String title;
}

/// The position at which "Up Next" should roll — the detected start of the
/// credits. In order of confidence:
///  1. a credits-named chapter in the back third of the runtime (precise);
///  2. the episode's TMDB [contentRuntime], when the file runs *meaningfully
///     longer* than it — the extra tail is credits/extras, so credits start
///     around there;
///  3. a heuristic tail: [tailFraction] of the runtime, clamped to
///     [minTail]..[maxTail].
///
/// Returns null when the runtime is unknown or shorter than [minDuration] (then
/// only the natural end triggers). Pure + tested.
Duration? creditsStart({
  required Duration duration,
  List<VideoChapter> chapters = const [],
  Duration? contentRuntime,
  double tailFraction = 0.06,
  Duration minTail = const Duration(seconds: 45),
  Duration maxTail = const Duration(minutes: 3),
  Duration minDuration = const Duration(minutes: 5),
}) {
  if (duration < minDuration) return null;

  // 1) An explicit credits chapter in the last third wins (precise).
  final backThird = duration * (2 / 3);
  for (final ch in chapters) {
    if (ch.start >= backThird && ch.start < duration && _looksLikeCredits(ch.title)) {
      return ch.start;
    }
  }

  // 2) TMDB content length. When the file runs meaningfully longer than the
  // episode's aired runtime, that extra tail is credits/extras → start there.
  // When the file ≈ the runtime, the runtime spans the credits too and tells us
  // nothing, so we fall through. Ignore an implausible runtime (< half the file
  // — wrong episode, or a multi-episode/season-pack file).
  if (contentRuntime != null &&
      contentRuntime < duration &&
      contentRuntime > duration * 0.5 &&
      duration - contentRuntime >= minTail) {
    return contentRuntime;
  }

  // 3) Heuristic tail.
  final tailSec = (duration.inSeconds * tailFraction)
      .round()
      .clamp(minTail.inSeconds, maxTail.inSeconds);
  return Duration(seconds: duration.inSeconds - tailSec);
}

bool _looksLikeCredits(String title) => title.toLowerCase().contains('credit');

/// Parse `ffprobe -show_chapters -print_format json` output into chapters,
/// skipping entries without a numeric start. Pure + tested.
List<VideoChapter> parseFfprobeChapters(String jsonStr) {
  try {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = (json['chapters'] as List?) ?? const [];
    final out = <VideoChapter>[];
    for (final entry in list.whereType<Map<String, dynamic>>()) {
      final seconds = double.tryParse(entry['start_time'] as String? ?? '');
      if (seconds == null) continue;
      final title = (entry['tags'] as Map?)?['title'] as String? ?? '';
      out.add(VideoChapter(
        start: Duration(milliseconds: (seconds * 1000).round()),
        title: title,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Read a file's chapters via the bundled ffprobe. Returns [] on any failure
/// (ffprobe not bundled, no chapters, or a bad file) — the caller falls back to
/// the runtime heuristic.
Future<List<VideoChapter>> readVideoChapters(String filePath) async {
  final name = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
  final ffprobe = bundledExecutable([name]) ?? name;
  try {
    final res = await Process.run(ffprobe, [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_chapters',
      filePath,
    ]);
    if (res.exitCode != 0) return const [];
    return parseFfprobeChapters(res.stdout as String);
  } on ProcessException {
    return const []; // ffprobe not installed / bundled
  } catch (_) {
    return const [];
  }
}
