import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';
import '../acquisition/acquisition.dart';

/// Housekeeping for the torrent client: once a torrent has finished downloading,
/// remove it from qBittorrent **keeping the files on disk**, so the client's list
/// doesn't fill up with completed torrents seeding forever.
///
/// Only the app's own torrents are cleared (those carrying an acquisition tag) —
/// a torrent a user added by hand in the qBittorrent web UI is left alone. This
/// never deletes media: `deleteFiles: false`, so the downloaded video stays put
/// for playback and the library scan.
///
/// Trade-off: clearing a finished torrent means a later re-selection (e.g. a
/// different episode from a season pack) re-adds it rather than reattaching — a
/// cheap recheck of the already-downloaded files, not a fresh download.
abstract class CompletedTorrentReaper {
  /// Clear finished app torrents from the client (keeping files). Returns the
  /// hashes removed.
  Future<List<String>> sweep();
}

@LazySingleton(as: CompletedTorrentReaper)
class QbittorrentCompletedTorrentReaper implements CompletedTorrentReaper {
  QbittorrentCompletedTorrentReaper(this._daemon, this._log);

  final TorrentDaemon _daemon;
  final ErrorLogService _log;

  @override
  Future<List<String>> sweep() async {
    // Nothing to do (and nothing to talk to) until the client is up.
    if (!await _daemon.isAlive()) return const [];

    final torrents = await _daemon.listTorrents();
    final done = torrents
        .where((t) => t.hash.isNotEmpty && t.isComplete && _isAppTorrent(t))
        .toList(growable: false);
    if (done.isEmpty) return const [];

    final cleared = <String>[];
    for (final t in done) {
      try {
        await _daemon.remove(hash: t.hash, deleteFiles: false);
        cleared.add(t.hash);
        _log.info(
            'cleared completed torrent "${t.name}" from the client (kept files)',
            source: 'CompletedTorrentReaper.sweep');
      } catch (e, st) {
        _log.logError(e,
            stackTrace: st, source: 'CompletedTorrentReaper.sweep');
      }
    }
    if (cleared.isNotEmpty) {
      _log.info('cleared ${cleared.length} completed torrent(s) from qBittorrent',
          source: 'CompletedTorrentReaper.sweep');
    }
    return cleared;
  }

  /// True when this torrent was added by the app — it carries either an
  /// acquisition tag (`cr-src-…`, dedupe-keyed adds) or the fallback
  /// `couchroach-…` tag (adds with no dedupe key). Torrents added by hand in the
  /// web UI have neither and are left untouched.
  bool _isAppTorrent(TorrentStatus t) => t.tags.any(
        (tag) => dedupeKeyFromTag(tag) != null || tag.startsWith('couchroach-'),
      );
}
