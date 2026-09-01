import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/media/video_extensions.dart';
import '../../data/repositories/library_repository.dart';
import '../subtitles/filename_media_info.dart';
import 'acquisition.dart';

/// Registers a library row for every **episode file that has finished
/// downloading inside one of our torrents**, so the show detail page flips that
/// episode to "Play" as its file lands.
///
/// Why this exists: a season pack is queued fire-and-forget (`_tryPack`), and
/// the acquire flow only writes a library row for the *one* episode it was
/// asked to prepare. So every other episode in the pack stayed invisible to the
/// library — and therefore to the detail page's live query — until someone
/// played it or a disk rescan happened at the next launch. This closes that gap
/// by reading finished files straight off the daemon.
///
/// Deliberately conservative:
/// * Only torrents tagged by us, and only keys carrying a numeric TMDB id.
/// * Only files that are **fully downloaded**, playable video, and whose name
///   parses to a season+episode. The filename is authoritative — a pack's key
///   names one season, but its files are what actually got downloaded.
/// * A path already in the library is left completely alone (no re-upsert, no
///   re-match), so repeated sweeps are cheap and can't clobber existing rows.
///
@LazySingleton()
class DownloadedEpisodeRegistrar {
  DownloadedEpisodeRegistrar(this._daemon, this._library, this._log);

  final TorrentDaemon _daemon;
  final LibraryRepository _library;
  final ErrorLogService _log;

  /// Guards against overlapping sweeps when one runs long.
  bool _busy = false;

  /// Scan every one of our torrents and register any newly-complete episode
  /// file. Best-effort: a daemon that's down or mid-restart just means nothing
  /// is registered this pass.
  Future<int> sweep() async {
    if (_busy) return 0;
    _busy = true;
    var registered = 0;
    try {
      for (final t in await _daemon.listTorrents()) {
        registered += await _sweepTorrent(t);
      }
      if (registered > 0) {
        _log.info('registered $registered newly-downloaded episode file(s)',
            source: 'DownloadedEpisodeRegistrar.sweep');
      }
    } catch (e, st) {
      _log.logError(e,
          stackTrace: st, source: 'DownloadedEpisodeRegistrar.sweep');
    } finally {
      _busy = false;
    }
    return registered;
  }

  Future<int> _sweepTorrent(TorrentStatus t) async {
    if (t.savePath.isEmpty) return 0;
    final tmdbId = _tmdbIdOf(t);
    if (tmdbId == null) return 0;

    final files = await _daemon.torrentFiles(t.hash);
    if (files.isEmpty) return 0;

    // Reuse the canonical name an existing row for this show already carries,
    // so a registered episode isn't nameless until the TMDB match lands.
    String? tmdbName;
    var registered = 0;
    for (final f in files) {
      final name = f['name'] as String?;
      if (name == null || name.isEmpty) continue;
      final progress = (f['progress'] as num?)?.toDouble() ?? 0;
      if (progress < 1.0) continue; // still downloading
      if (!kVideoExtensions.contains(p.extension(name).toLowerCase())) continue;

      final info = FilenameMediaInfo.parse(p.basename(name));
      if (!info.hasEpisode) continue;

      // File names are listed relative to the torrent's save path.
      final path = p.join(t.savePath, name);
      if (await _library.findByPath(path) != null) continue; // already known

      tmdbName ??= await _showNameFor(tmdbId);
      await _library.upsert(ScannedFile(
        filePath: path,
        title: p.basenameWithoutExtension(name),
        mediaType: 'tv',
        season: info.season,
        episode: info.episode,
        tmdbId: tmdbId,
        tmdbName: tmdbName,
        managed: true, // app-acquired → belongs to the cleanup lifecycle
      ));
      registered++;
    }
    return registered;
  }

  /// The TMDB id this torrent was queued for, from the acquisition tag we
  /// stamped at add time. Null for anything not ours or title-keyed.
  int? _tmdbIdOf(TorrentStatus t) {
    for (final tag in t.tags) {
      final id = parseAcquisitionKey(tag).tmdbId;
      if (id != null) return id;
    }
    return null;
  }

  /// The canonical show name already recorded for [tmdbId], if any row has one.
  Future<String?> _showNameFor(int tmdbId) async {
    try {
      for (final row in await _library.localEpisodes(tmdbId)) {
        if (row.tmdbName != null) return row.tmdbName;
      }
    } catch (_) {
      // Best-effort: a nameless row is fine, the TMDB match fills it in later.
    }
    return null;
  }
}
