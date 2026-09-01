import 'dart:io';

import '../process/bundled_executable.dart';

/// The `ffmpeg` command to run: the copy the sidecar bundle provisions (resolved
/// by absolute path — a clean release doesn't put it on PATH, and `Process.run`
/// doesn't search the executable's own directory), else the bare name so a dev
/// machine with ffmpeg installed still works.
///
/// It rides along in the same BtbN archive `ffprobe` already comes from, so
/// bundling it costs only size — no extra download or pin to maintain.
String ffmpegCommand() {
  final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
  return bundledExecutable([name]) ?? name;
}

/// Whether an `ffmpeg` we can actually invoke is present. False means the
/// sidecar bundle predates ffmpeg (or a dev machine lacks it), and callers
/// should skip the feature rather than fail — same posture as `ffprobe`.
Future<bool> ffmpegAvailable() async {
  try {
    final res = await Process.run(ffmpegCommand(), ['-version']);
    return res.exitCode == 0;
  } catch (_) {
    return false;
  }
}
