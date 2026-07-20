import 'dart:io';

import 'package:path/path.dart' as p;

/// English subtitle sidecars the app itself may have written next to a video. A
/// bare `.srt` is deliberately left alone — it may be the user's own subtitle.
const mediaSidecarSuffixes = ['.en.srt', '.eng.srt', '.english.srt'];

/// Delete [videoPath] and any English `.srt` sidecars sitting next to it.
/// Best-effort: a missing file is a silent no-op (so deleting an item whose
/// drive is disconnected still succeeds at the row level); the caller handles
/// and logs I/O errors. Shared by the watched-reaper (auto-cleanup) and manual
/// delete so both remove exactly the same set of files.
void deleteMediaFileAndSidecars(String videoPath) {
  final video = File(videoPath);
  if (video.existsSync()) video.deleteSync();

  final dir = p.dirname(videoPath);
  final base = p.basenameWithoutExtension(videoPath);
  for (final suffix in mediaSidecarSuffixes) {
    final sidecar = File(p.join(dir, '$base$suffix'));
    if (sidecar.existsSync()) sidecar.deleteSync();
  }
}
