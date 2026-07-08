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

  /// Per-attempt windows to wait for a newly-added torrent to appear; the add is
  /// re-POSTed before each. Two attempts absorb a slow/dropped first add right
  /// after daemon startup. Overridable in tests to keep them fast.
  static List<Duration> addResolveWindows = const [
    Duration(seconds: 25),
    Duration(seconds: 45),
  ];

  String get _api => '${QbittorrentProcess.baseUrl}/api/v2';

  @override
  Future<TorrentTask> add(
    TorrentHandle handle, {
    required String savePath,
    bool sequential = true,
    bool firstLastPiecePriority = true,
    String? dedupeKey,
  }) async {
    // A deterministic tag from the dedupe key both identifies the torrent's hash
    // (the add endpoint doesn't return it) AND lets us detect an existing add.
    // Without a key, a unique tag per add. Tags can't contain commas.
    final tag = dedupeKey != null
        ? 'cr-src-${dedupeKey.replaceAll(',', '_')}'
        : 'couchroach-${DateTime.now().microsecondsSinceEpoch}';
    final label = handle.displayName ?? handle.magnetOrUrl;
    _log.info('add "$label" (tag=$tag, savePath=$savePath)',
        source: 'QbittorrentDaemon.add');

    // Reattach to an already-added torrent instead of adding a duplicate.
    if (dedupeKey != null) {
      final existing = await _taskForTag(tag);
      if (existing != null) {
        _log.info('reattached to already-added torrent hash=${existing.hash}',
            source: 'QbittorrentDaemon.add');
        return existing;
      }
    }

    // Fetch the .torrent ourselves for http(s) sources (IA now, Jackett later)
    // so a failed download surfaces as a real HTTP status here instead of
    // qBittorrent silently never creating the torrent after returning Ok. Throws
    // with the reason on a bad fetch; magnets pass through unchanged (null).
    final torrentBytes = await _fetchTorrent(handle);

    // A slow/dropped first add right after daemon startup can leave the torrent
    // missing — retry with a longer window. The tag is stable across attempts, so
    // re-adding is a safe no-op (qBittorrent dedupes by infohash) that catches it
    // once the session is ready.
    String? hash;
    for (var attempt = 0;
        attempt < addResolveWindows.length && hash == null;
        attempt++) {
      final window = addResolveWindows[attempt];
      _log.info(
          'add attempt ${attempt + 1}/${addResolveWindows.length}: POSTing, '
          'waiting up to ${window.inSeconds}s for the torrent to appear',
          source: 'QbittorrentDaemon.add');
      await _postAdd(handle,
          tag: tag,
          savePath: savePath,
          sequential: sequential,
          firstLastPiecePriority: firstLastPiecePriority,
          torrentBytes: torrentBytes);
      hash = await _tryResolveHashByTag(tag, window);
    }
    if (hash == null) {
      final e = TorrentDaemonException(
          'torrent for tag "$tag" never appeared in qBittorrent');
      _log.logError(e, source: 'QbittorrentDaemon.add');
      throw e;
    }
    _log.info('torrent appeared: hash=$hash', source: 'QbittorrentDaemon.add');
    return QbittorrentTask(this, hash: hash, savePath: savePath);
  }

  /// For an http(s) `.torrent` URL, fetch the file ourselves (following
  /// redirects) and return its bytes — so a 404/403/503/HTML-error surfaces here
  /// with a real status instead of qBittorrent silently failing the async
  /// download. Magnet and any non-http handle pass through as `urls` (null).
  Future<List<int>?> _fetchTorrent(TorrentHandle handle) async {
    final uri = Uri.tryParse(handle.magnetOrUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final label = handle.displayName ?? handle.magnetOrUrl;
    _log.info('fetching .torrent for "$label" from $uri',
        source: 'QbittorrentDaemon.add');
    final http.Response res;
    try {
      res = await _http.get(uri); // package:http follows redirects
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentDaemon.fetchTorrent');
      throw TorrentDaemonException('could not fetch .torrent from $uri: $e');
    }
    if (res.statusCode != 200) {
      final e = TorrentDaemonException(
          'fetching .torrent from $uri returned HTTP ${res.statusCode}');
      _log.logError(e, source: 'QbittorrentDaemon.fetchTorrent');
      throw e;
    }
    // A .torrent is a bencoded dictionary — it starts with 'd' (0x64). Guards
    // against an HTML/JSON error page served with a 200.
    final bytes = res.bodyBytes;
    if (bytes.isEmpty || bytes.first != 0x64) {
      final e = TorrentDaemonException(
          'data from $uri is not a .torrent (${bytes.length} bytes)');
      _log.logError(e, source: 'QbittorrentDaemon.fetchTorrent');
      throw e;
    }
    _log.info('.torrent fetched (${bytes.length} bytes)',
        source: 'QbittorrentDaemon.add');
    return bytes;
  }

  Future<void> _postAdd(
    TorrentHandle handle, {
    required String tag,
    required String savePath,
    required bool sequential,
    required bool firstLastPiecePriority,
    required List<int>? torrentBytes,
  }) async {
    final fields = {
      'savepath': savePath,
      'sequentialDownload': '$sequential',
      'firstLastPiecePrio': '$firstLastPiecePriority',
      'tags': tag,
    };
    try {
      final http.Response res;
      if (torrentBytes != null) {
        // Upload the fetched bytes as the multipart `torrents` file.
        final req =
            http.MultipartRequest('POST', Uri.parse('$_api/torrents/add'))
              ..fields.addAll(fields)
              ..files.add(http.MultipartFile.fromBytes('torrents', torrentBytes,
                  filename: 'source.torrent'));
        res = await http.Response.fromStream(await _http.send(req));
      } else {
        res = await _http.post(Uri.parse('$_api/torrents/add'),
            body: {'urls': handle.magnetOrUrl, ...fields});
      }
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
  }

  /// A task for an already-added torrent bearing [tag], or null if none exists.
  /// Reads the hash + save path from the daemon so streaming can resume.
  Future<QbittorrentTask?> _taskForTag(String tag) async {
    final list = await torrentsInfo(tag: tag);
    if (list.isEmpty) return null;
    final t = list.first;
    final hash = t['hash'] as String?;
    final savePath = t['save_path'] as String?;
    if (hash == null || hash.isEmpty || savePath == null) return null;
    return QbittorrentTask(this, hash: hash, savePath: savePath);
  }

  @override
  Future<List<TorrentStatus>> listTorrents() async {
    final list = await torrentsInfo();
    return list.map(parseTorrentStatus).toList(growable: false);
  }

  @override
  Future<void> remove({required String hash, required bool deleteFiles}) =>
      _command('/torrents/delete',
          {'hashes': hash, 'deleteFiles': '$deleteFiles'}, 'remove');

  @override
  Future<void> setPaused({required String hash, required bool paused}) =>
      // qBittorrent 5.x renamed pause/resume → stop/start.
      _command(paused ? '/torrents/stop' : '/torrents/start', {'hashes': hash},
          'setPaused');

  /// POST a control command; throw + log on a non-2xx so callers can surface it.
  Future<void> _command(
      String path, Map<String, String> body, String source) async {
    try {
      final res = await _http.post(Uri.parse('$_api$path'), body: body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw TorrentDaemonException('$path failed (${res.statusCode})');
      }
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentDaemon.$source');
      rethrow;
    }
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

  /// Poll up to [window] for the tagged torrent to appear (a URL/magnet add lags
  /// while the .torrent is fetched / metadata resolves), returning its hash or
  /// null if it never shows.
  Future<String?> _tryResolveHashByTag(String tag, Duration window) async {
    final deadline = DateTime.now().add(window);
    while (DateTime.now().isBefore(deadline)) {
      final list = await torrentsInfo(tag: tag);
      if (list.isNotEmpty) {
        final hash = list.first['hash'] as String?;
        if (hash != null && hash.isNotEmpty) return hash;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
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
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    } catch (e, st) {
      _log.logError(e,
          stackTrace: st, source: 'QbittorrentDaemon.torrentsInfo');
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
      _log.logError(e,
          stackTrace: st, source: 'QbittorrentDaemon.torrentFiles');
      return const [];
    }
  }

  /// `GET /torrents/pieceStates?hash=` — one state per piece: 0 not downloaded,
  /// 1 downloading, 2 downloaded. Returns [] on error.
  Future<List<int>> pieceStates(String hash) async {
    final uri = Uri.parse('$_api/torrents/pieceStates')
        .replace(queryParameters: {'hash': hash});
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return const [];
      return (jsonDecode(res.body) as List)
          .map((e) => (e as num).toInt())
          .toList(growable: false);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentDaemon.pieceStates');
      return const [];
    }
  }

  /// `GET /torrents/properties?hash=` — torrent properties (incl. `piece_size`).
  /// Returns {} on error.
  Future<Map<String, dynamic>> torrentProperties(String hash) async {
    final uri = Uri.parse('$_api/torrents/properties')
        .replace(queryParameters: {'hash': hash});
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) return const {};
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e, st) {
      _log.logError(e,
          stackTrace: st, source: 'QbittorrentDaemon.torrentProperties');
      return const {};
    }
  }

  /// `POST /torrents/filePrio` — set download [priority] (0 skip, 1 normal,
  /// 6 high, 7 maximal) for the given file [indices].
  Future<void> setFilePriority(String hash, List<int> indices, int priority) =>
      _command(
          '/torrents/filePrio',
          {
            'hash': hash,
            'id': indices.join('|'),
            'priority': '$priority',
          },
          'setFilePriority');

  /// Set sequential download on/off. The Web API only offers a *toggle*, so read
  /// the current `seq_dl` state and flip only when it differs.
  Future<void> setSequentialDownload(String hash, bool enabled) =>
      _setToggle(hash, 'seq_dl', enabled, '/torrents/toggleSequentialDownload');

  /// Set first/last-piece priority on/off (toggle-only API, see above).
  Future<void> setFirstLastPiecePrio(String hash, bool enabled) => _setToggle(
      hash, 'f_l_piece_prio', enabled, '/torrents/toggleFirstLastPiecePrio');

  Future<void> _setToggle(
      String hash, String field, bool enabled, String togglePath) async {
    final info = await torrentsInfo(hashes: hash);
    final current =
        info.isNotEmpty ? (info.first[field] as bool? ?? false) : false;
    if (current == enabled) return;
    await _command(togglePath, {'hashes': hash}, 'setToggle');
  }
}

/// A single added torrent, tracked by its info hash.
///
/// Streaming readiness is piece-level, not a progress fraction: once the primary
/// file is known we download **only** it (others → priority 0) with first/last
/// piece priority, then wait until that file's leading pieces (header + a buffer)
/// **and** its last piece (mp4 `moov` / container index often live at the tail)
/// are actually present — otherwise mpv opens a file whose start isn't there yet
/// and fails with "couldn't recognize the file format".
class QbittorrentTask implements TorrentTask {
  QbittorrentTask(this._daemon, {required this.hash, required this.savePath});

  final QbittorrentDaemon _daemon;
  final String hash;
  final String savePath;

  // Step logging goes to the same sink the daemon uses (same library, so the
  // private field is reachable).
  ErrorLogService get _log => _daemon._log;

  /// Head buffer downloaded before we start playing (~seconds of video).
  static const int _headBufferBytes = 16 * 1024 * 1024;

  /// Files at or below this size are downloaded **fully** before playing rather
  /// than streamed: they finish quickly, and streaming's benefit (start before
  /// it's done) doesn't outweigh the tail-stall risk on a single-web-seed IA
  /// torrent. Larger files still stream. Pure predicate exposed for testing.
  static const int smallFileThresholdBytes = 100 * 1024 * 1024;
  static bool downloadFully(int sizeBytes) =>
      sizeBytes > 0 && sizeBytes <= smallFileThresholdBytes;

  _PrimaryFile? _primary;

  /// Resolve the primary video file (index, name, piece range) once, and focus
  /// the download on just that file so IA's many derivative encodings don't
  /// starve streaming.
  Future<_PrimaryFile> _resolvePrimary() async {
    if (_primary != null) return _primary!;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final files = await _daemon.torrentFiles(hash);
      final chosen = pickPrimaryFile(files);
      if (chosen != null) {
        final index =
            (chosen['index'] as num?)?.toInt() ?? files.indexOf(chosen);
        final range = pieceRangeOf(chosen['piece_range']);
        final primary = _PrimaryFile(
          index: index,
          name: chosen['name'] as String,
          sizeBytes: (chosen['size'] as num?)?.toInt() ?? 0,
          firstPiece: range?.$1,
          lastPiece: range?.$2,
        );
        _primary = primary;
        _log.info(
            'primary file "${primary.name}" ${_fmtMb(primary.sizeBytes)} '
            'idx=${primary.index} pieces='
            '${primary.firstPiece == null ? "n/a" : "[${primary.firstPiece}..${primary.lastPiece}]"} '
            '(of ${files.length} files in the torrent)',
            source: 'QbittorrentTask.resolvePrimary');
        await _focusDownloadOn(primary.index, files);
        _log.info('focused download on the primary file (other files skipped)',
            source: 'QbittorrentTask.resolvePrimary');
        return primary;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final e = TorrentDaemonException('no files resolved for torrent $hash');
    _log.logError(e, source: 'QbittorrentTask.resolvePrimary');
    throw e;
  }

  /// Download only the primary file: every other file → priority 0, the primary
  /// → maximal. Best-effort (streaming still works if the daemon rejects it).
  Future<void> _focusDownloadOn(
      int primaryIndex, List<Map<String, dynamic>> files) async {
    final others = <int>[];
    for (var i = 0; i < files.length; i++) {
      final idx = (files[i]['index'] as num?)?.toInt() ?? i;
      if (idx != primaryIndex) others.add(idx);
    }
    try {
      if (others.isNotEmpty) await _daemon.setFilePriority(hash, others, 0);
      await _daemon.setFilePriority(hash, [primaryIndex], 7);
    } catch (_) {
      // Non-fatal — fall back to streaming whatever downloads.
    }
  }

  @override
  Future<String> get primaryFile async {
    // qBittorrent's file `name` is the path relative to the save path (including
    // any torrent root folder), so join to get the absolute path.
    return p.join(savePath, (await _resolvePrimary()).name);
  }

  @override
  Future<void> readyToStream() async {
    final primary = await _resolvePrimary();
    final deadline = DateTime.now().add(const Duration(minutes: 8));

    // Small files: download fully first. Streaming's tail-stall risk (a single
    // IA web seed trickling the final pieces, which our first/last-piece wait
    // then blocks on) isn't worth it when the file finishes quickly. Switch to a
    // parallel download so qBittorrent pulls it as fast as the seed allows.
    if (downloadFully(primary.sizeBytes)) {
      _log.info(
          'readyToStream: small file (${_fmtMb(primary.sizeBytes)}) — '
          'downloading fully before play',
          source: 'QbittorrentTask.readyToStream');
      await _daemon.setSequentialDownload(hash, false);
      await _daemon.setFirstLastPiecePrio(hash, false);
      return _awaitFileProgress(deadline, 0.999);
    }

    // Large files: stream. Enforce sequential + first/last-piece explicitly here
    // rather than trusting the add-time flags to have taken effect, so the mode
    // is deterministic regardless of daemon version.
    _log.info(
        'readyToStream: large file (${_fmtMb(primary.sizeBytes)}) — streaming '
        '(sequential + first/last piece)',
        source: 'QbittorrentTask.readyToStream');
    await _daemon.setSequentialDownload(hash, true);
    await _daemon.setFirstLastPiecePrio(hash, true);

    // Fall back to near-complete when the daemon doesn't expose piece ranges.
    if (primary.firstPiece == null || primary.lastPiece == null) {
      _log.info(
          'readyToStream: daemon reported no piece_range — waiting for '
          'near-complete instead',
          source: 'QbittorrentTask.readyToStream');
      return _awaitFileProgress(deadline, 0.99);
    }

    final props = await _daemon.torrentProperties(hash);
    final pieceSize = (props['piece_size'] as num?)?.toInt() ?? (1 << 20);
    final first = primary.firstPiece!;
    final last = primary.lastPiece!;
    final headPieces = headPieceCount(pieceSize, last - first + 1);
    _log.info(
        'streaming: piece_size=${(pieceSize / 1024).toStringAsFixed(0)}KB, '
        'need head=$headPieces pieces + last (file spans pieces $first..$last)',
        source: 'QbittorrentTask.readyToStream');

    var lastLog = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      final states = await _daemon.pieceStates(hash);
      if (headAndTailReady(states, first, last, headPieces)) {
        _log.info('readyToStream: head + tail present — starting playback',
            source: 'QbittorrentTask.readyToStream');
        return;
      }
      final now = DateTime.now();
      if (now.difference(lastLog).inSeconds >= 4) {
        lastLog = now;
        _log.info(_bufferStatus(states, first, last, headPieces, primary.name),
            source: 'QbittorrentTask.readyToStream');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final e = TorrentDaemonException(
        'torrent $hash did not buffer enough to stream in time');
    _log.logError(e, source: 'QbittorrentTask.readyToStream');
    throw e;
  }

  Future<void> _awaitFileProgress(DateTime deadline, double target) async {
    var lastLog = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      final chosen = pickPrimaryFile(await _daemon.torrentFiles(hash));
      final progress = (chosen?['progress'] as num?)?.toDouble() ?? 0;
      if (progress >= target) return;
      final now = DateTime.now();
      if (now.difference(lastLog).inSeconds >= 4) {
        lastLog = now;
        _log.info(
            'downloading: ${(progress * 100).toStringAsFixed(1)}% '
            '(target ${(target * 100).toStringAsFixed(1)}%)',
            source: 'QbittorrentTask.readyToStream');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final e = TorrentDaemonException(
        'torrent $hash did not download enough to play in time');
    _log.logError(e, source: 'QbittorrentTask.readyToStream');
    throw e;
  }

  @override
  Stream<double> get progress async* {
    while (true) {
      final info = await _daemon.torrentsInfo(hashes: hash);
      final value = info.isEmpty
          ? 0.0
          : (info.first['progress'] as num?)?.toDouble() ?? 0.0;
      yield value.clamp(0.0, 1.0);
      if (value >= 1.0) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Head pieces to require before playing: enough to cover [_headBufferBytes],
  /// at least 2, never more than the file has. Pure + tested.
  static int headPieceCount(int pieceSize, int filePieces) {
    if (pieceSize <= 0 || filePieces <= 0) return filePieces.clamp(0, 2);
    return (_headBufferBytes / pieceSize).ceil().clamp(2, filePieces);
  }
}

/// A resolved primary file within a torrent. Piece indices are null when the
/// daemon doesn't report a `piece_range`.
class _PrimaryFile {
  _PrimaryFile({
    required this.index,
    required this.name,
    required this.sizeBytes,
    this.firstPiece,
    this.lastPiece,
  });
  final int index;
  final int sizeBytes;
  final String name;
  final int? firstPiece;
  final int? lastPiece;
}

String _fmtMb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';

/// One-line buffering status for the log: how much of the primary file's pieces
/// are downloaded, and whether the head buffer and tail piece are present — so a
/// stall reads as e.g. "99.8% … head 8/8, tail pending".
String _bufferStatus(
    List<int> states, int first, int last, int headPieces, String name) {
  final total = last - first + 1;
  var done = 0;
  var headDone = 0;
  for (var i = first; i <= last && i >= 0 && i < states.length; i++) {
    if (states[i] == 2) {
      done++;
      if (i < first + headPieces) headDone++;
    }
  }
  final tail =
      (last >= 0 && last < states.length && states[last] == 2) ? 'ready' : 'pending';
  final pct = total > 0 ? (done / total * 100).toStringAsFixed(1) : '0.0';
  return 'buffering "$name": $pct% of file ($done/$total pieces) — '
      'head $headDone/$headPieces, tail $tail';
}

/// A qBittorrent `piece_range` (`[first, last]`) → a record, or null if absent
/// or malformed. Pure + tested.
(int, int)? pieceRangeOf(Object? raw) {
  if (raw is List && raw.length == 2 && raw[0] is num && raw[1] is num) {
    return ((raw[0] as num).toInt(), (raw[1] as num).toInt());
  }
  return null;
}

/// Streaming-ready when the primary file's leading [headPieces] pieces AND its
/// last piece are all downloaded (state 2) — header + buffer up front, container
/// index/`moov` at the tail. Pure + tested.
bool headAndTailReady(
    List<int> states, int firstPiece, int lastPiece, int headPieces) {
  if (firstPiece < 0 || lastPiece < firstPiece || lastPiece >= states.length) {
    return false;
  }
  if (states[lastPiece] != 2) return false;
  final end = firstPiece + headPieces;
  for (var i = firstPiece; i < end && i <= lastPiece; i++) {
    if (states[i] != 2) return false;
  }
  return true;
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
  final pool =
      videos.isNotEmpty ? videos : [...files]; // copy: never mutate input
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
      final accepted = count('success_count') +
          count('pending_count') +
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
    etaSeconds:
        (eta <= 0 || eta >= _qbEtaUnknown || progress >= 1.0) ? null : eta,
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
