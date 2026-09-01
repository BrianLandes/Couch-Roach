import 'package:path/path.dart' as p;

import '../../core/media/video_extensions.dart';
import '../subtitles/filename_media_info.dart';

/// Per-episode download progress read off a torrent's **file** list, keyed by
/// `(season, episode)`.
///
/// A season pack is a single torrent whose files are the episodes, so the
/// torrent-level progress can't answer "how far along is episode 4" — every
/// episode would show the same number. This maps each playable video file to
/// the episode its name declares, so each row can show its own meter.
///
/// The filename is authoritative (same rule the registrar uses): a pack's key
/// names one season, but its files are what actually got downloaded. Non-video
/// files and anything without an `SxxExx` marker are ignored. When two files
/// claim the same episode the furthest-along one wins, so a duplicate or sample
/// can't drag the displayed progress backwards. Pure + tested.
Map<(int, int), double> episodeFileProgress(List<Map<String, dynamic>> files) {
  final out = <(int, int), double>{};
  for (final f in files) {
    final name = f['name'] as String?;
    if (name == null || name.isEmpty) continue;
    if (!kVideoExtensions.contains(p.extension(name).toLowerCase())) continue;

    final info = FilenameMediaInfo.parse(p.basename(name));
    if (!info.hasEpisode) continue;

    final progress = ((f['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    final key = (info.season!, info.episode!);
    final existing = out[key];
    if (existing == null || progress > existing) out[key] = progress;
  }
  return out;
}
