import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/media/video_extensions.dart';
import 'acquisition.dart';
import 'qbittorrent_process.dart';

/// [TorrentDaemon] over the qBittorrent Web API (v2). Talks to the invisible
/// localhost child managed by [QbittorrentProcess] — localhost auth is disabled
/// there, so no login is needed. This client's job (per its task): add a
/// torrent, expose download progress, and resolve the primary/largest video
/// file's absolute path.
///
/// Sequential + first/last-piece are requested at add time (the interface passes
/// the flags); the *readyToStream buffer detection* is intentionally basic here
/// and refined in the dedicated sequential/first-last task.
@LazySingleton(as: TorrentDaemon)
class QbittorrentDaemon implements TorrentDaemon {
  QbittorrentDaemon(this._http, this._log);

  final http.Client _http;
  final ErrorLogService _log;

  String get _api => '${QbittorrentProcess.baseUrl}/api/v2';

  @override
  Future<TorrentTask> add(
    TorrentHandle handle, {
    required String savePath,
    bool sequential = true,
    bool firstLastPiecePriority = true,
  }) async {
    // Tag each add so we can find the resulting torrent's hash — the add
    // endpoint doesn't return it, and a tag works for both magnets and .torrent
    // URLs (unlike parsing the btih out of a magnet).
    final tag = 'couchroach-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final res = await _http.post(
        Uri.parse('$_api/torrents/add'),
        body: {
          'urls': handle.magnetOrUrl,
          'savepath': savePath,
          'sequentialDownload': '$sequential',
          'firstLastPiecePrio': '$firstLastPiecePriority',
          'tags': tag,
        },
      );
      if (addResponseIsFailure(res.statusCode, res.body)) {
        throw TorrentDaemonException(
          'add failed (${res.statusCode}: ${res.body.trim()}) for '
          '${handle.displayName ?? handle.magnetOrUrl}',
        );
      }
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentDaemon.add');
      rethrow;
    }

    final hash = await _resolveHashByTag(tag);
    return QbittorrentTask(this, hash: hash, savePath: savePath);
  }

  @override
  Future<List<TorrentStatus>> listTorrents() async {
    final list = await torrentsInfo();
    return list.map(parseTorrentStatus).toList(growable: false);
  }

  @override
  Future<bool> isAlive() async {
    try {
      final res = await _http
          .get(Uri.parse('$_api/app/version'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Poll until the tagged torrent appears (magnet metadata resolution can lag
  /// the add call), then return its hash.
  Future<String> _resolveHashByTag(String tag) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final list = await torrentsInfo(tag: tag);
      if (list.isNotEmpty) {
        final hash = list.first['hash'] as String?;
        if (hash != null && hash.isNotEmpty) return hash;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final e = TorrentDaemonException(
      'torrent for tag "$tag" never appeared in qBittorrent',
    );
    _log.logError(e, source: 'QbittorrentDaemon._resolveHashByTag');
    throw e;
  }

  /// `GET /torrents/info` — filter by [tag] or [hashes]. Returns [] on error.
  Future<List<Map<String, dynamic>>> torrentsInfo({
    String? tag,
    String? hashes,
  }) async {
    final uri = Uri.parse('$_api/torrents/info').replace(queryParameters: {
      if (tag != null) 'tag': tag,
      if (hashes != null) 'hashes': hashes,
    });
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return const [];
      return (jsonDecode(res.body) as List)
          .cast<Map<String, dynamic>>();
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentDaemon.torrentsInfo');
      return const [];
    }
  }

  /// `GET /torrents/files?hash=` — the file list for a torrent. Returns [] on
  /// error or before metadata is available.
  Future<List<Map<String, dynamic>>> torrentFiles(String hash) async {
    final uri = Uri.parse('$_api/torrents/files')
        .replace(queryParameters: {'hash': hash});
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return const [];
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentDaemon.torrentFiles');
      return const [];
    }
  }
}

/// A single added torrent, tracked by its info hash.
class QbittorrentTask implements TorrentTask {
  QbittorrentTask(this._daemon, {required this.hash, required this.savePath});

  final QbittorrentDaemon _daemon;
  final String hash;
  final String savePath;

  /// Minimum head buffer (as a fraction of the primary file) before we call it
  /// streamable. Crude on purpose — the sequential/first-last task replaces this
  /// with piece-level (first+last present) detection.
  static const double _minStreamBuffer = 0.01;

  @override
  Future<String> get primaryFile async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final files = await _daemon.torrentFiles(hash);
      final primary = pickPrimaryFile(files);
      if (primary != null) {
        // qBittorrent's file `name` is the path relative to the save path
        // (including any torrent root folder), so join to get the absolute path.
        return p.join(savePath, primary['name'] as String);
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TorrentDaemonException('no files resolved for torrent $hash');
  }

  @override
  Future<void> readyToStream() async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      final files = await _daemon.torrentFiles(hash);
      final primary = pickPrimaryFile(files);
      if (primary != null) {
        final progress = (primary['progress'] as num?)?.toDouble() ?? 0;
        if (progress >= _minStreamBuffer || progress >= 1.0) return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TorrentDaemonException(
      'torrent $hash did not buffer enough to stream in time',
    );
  }

  @override
  Stream<double> get progress async* {
    while (true) {
      final info = await _daemon.torrentsInfo(hashes: hash);
      final value =
          info.isEmpty ? 0.0 : (info.first['progress'] as num?)?.toDouble() ?? 0.0;
      yield value.clamp(0.0, 1.0);
      if (value >= 1.0) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}

/// Pick the file to hand the player: the largest **video** file, or the largest
/// file overall if none match a video extension. Null if [files] is empty.
/// Pure + exposed for testing.
Map<String, dynamic>? pickPrimaryFile(List<Map<String, dynamic>> files) {
  if (files.isEmpty) return null;
  int sizeOf(Map<String, dynamic> f) => (f['size'] as num?)?.toInt() ?? 0;
  bool isVideo(Map<String, dynamic> f) {
    final name = f['name'] as String? ?? '';
    return kVideoExtensions.contains(p.extension(name).toLowerCase());
  }

  final videos = files.where(isVideo).toList();
  final pool = videos.isNotEmpty ? videos : files;
  pool.sort((a, b) => sizeOf(b).compareTo(sizeOf(a)));
  return pool.first;
}

/// Whether a `/torrents/add` response means the add failed. Handles both API
/// shapes: older qBittorrent replies with the text `Ok.`/`Fails.` (200 for
/// both); newer (≥5.1) replies with a 2xx (often **202 Accepted** while a
/// URL/magnet is still resolving) and a JSON body of `*_count` fields. Treat as
/// failure only on a non-2xx status, a literal `Fails.`, or JSON that reports a
/// real failure with nothing accepted or pending. Pure + tested.
bool addResponseIsFailure(int statusCode, String body) {
  if (statusCode < 200 || statusCode >= 300) return true;
  final trimmed = body.trim();
  if (trimmed == 'Fails.') return true;
  if (trimmed.startsWith('{')) {
    try {
      final j = jsonDecode(trimmed) as Map<String, dynamic>;
      int count(String k) => (j[k] as num?)?.toInt() ?? 0;
      final accepted = count('success_count') + count('pending_count') +
          ((j['added_torrent_ids'] as List?)?.length ?? 0);
      return count('failure_count') > 0 && accepted == 0;
    } catch (_) {
      return false; // unparseable but 2xx — let the tag poll decide
    }
  }
  return false;
}

/// qBittorrent's sentinel ETA (100 days, in seconds) meaning "unknown/∞".
const int _qbEtaUnknown = 8640000;

/// Parse one `/torrents/info` entry into a [TorrentStatus]. Pure + tested.
/// The daemon's ETA sentinel (and any complete/non-downloading torrent) maps to
/// a null [TorrentStatus.etaSeconds].
TorrentStatus parseTorrentStatus(Map<String, dynamic> json) {
  int asInt(Object? v) => (v as num?)?.toInt() ?? 0;
  final eta = asInt(json['eta']);
  final progress = (json['progress'] as num?)?.toDouble() ?? 0;
  return TorrentStatus(
    hash: json['hash'] as String? ?? '',
    name: json['name'] as String? ?? '',
    progress: progress.clamp(0.0, 1.0),
    state: json['state'] as String? ?? '',
    downloadSpeed: asInt(json['dlspeed']),
    sizeBytes: asInt(json['size']),
    downloadedBytes: asInt(json['downloaded']),
    etaSeconds: (eta <= 0 || eta >= _qbEtaUnknown || progress >= 1.0) ? null : eta,
  );
}

/// Raised when a qBittorrent Web API operation fails. Surfaced to the caller so
/// the play flow can degrade with a user-facing error.
class TorrentDaemonException implements Exception {
  TorrentDaemonException(this.message);
  final String message;
  @override
  String toString() => 'TorrentDaemonException: $message';
}
