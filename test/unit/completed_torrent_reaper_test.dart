import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/cleanup/completed_torrent_reaper.dart';
import 'package:flutter_test/flutter_test.dart';

/// A TorrentDaemon that serves a canned torrent list and records removals;
/// everything else throws (unused by the reaper).
class _FakeDaemon implements TorrentDaemon {
  _FakeDaemon(this.torrents, {this.alive = true});

  List<TorrentStatus> torrents;
  bool alive;
  final List<({String hash, bool deleteFiles})> removed = [];

  @override
  Future<bool> isAlive() async => alive;

  @override
  Future<List<TorrentStatus>> listTorrents() async => torrents;

  @override
  Future<void> remove({required String hash, required bool deleteFiles}) async {
    removed.add((hash: hash, deleteFiles: deleteFiles));
    torrents = torrents.where((t) => t.hash != hash).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

TorrentStatus _status({
  required String hash,
  double progress = 1.0,
  List<String> tags = const ['cr-src-cr-tmdb-1'],
}) =>
    TorrentStatus(
      hash: hash,
      name: 'Torrent $hash',
      progress: progress,
      state: 'uploading',
      downloadSpeed: 0,
      sizeBytes: 0,
      downloadedBytes: 0,
      tags: tags,
    );

void main() {
  final log = ErrorLogService();

  test('clears a completed app torrent, keeping its files', () async {
    final daemon = _FakeDaemon([_status(hash: 'A')]);
    final reaper = QbittorrentCompletedTorrentReaper(daemon, log);

    final cleared = await reaper.sweep();

    expect(cleared, ['A']);
    expect(daemon.removed, [(hash: 'A', deleteFiles: false)]);
  });

  test('leaves torrents that are still downloading', () async {
    final daemon = _FakeDaemon([_status(hash: 'A', progress: 0.5)]);
    final reaper = QbittorrentCompletedTorrentReaper(daemon, log);

    expect(await reaper.sweep(), isEmpty);
    expect(daemon.removed, isEmpty);
  });

  test('leaves completed torrents the app did not add (no app tag)', () async {
    final daemon = _FakeDaemon([
      _status(hash: 'user', tags: const ['my-stuff']),
    ]);
    final reaper = QbittorrentCompletedTorrentReaper(daemon, log);

    expect(await reaper.sweep(), isEmpty);
    expect(daemon.removed, isEmpty);
  });

  test('clears a no-dedupe app torrent tagged "couchroach-…"', () async {
    final daemon = _FakeDaemon([
      _status(hash: 'B', tags: const ['couchroach-1699999999']),
    ]);
    final reaper = QbittorrentCompletedTorrentReaper(daemon, log);

    expect(await reaper.sweep(), ['B']);
  });

  test('only the finished app torrents are cleared from a mixed list', () async {
    final daemon = _FakeDaemon([
      _status(hash: 'done'),
      _status(hash: 'downloading', progress: 0.3),
      _status(hash: 'user', tags: const ['manual']),
    ]);
    final reaper = QbittorrentCompletedTorrentReaper(daemon, log);

    expect(await reaper.sweep(), ['done']);
    expect(daemon.removed.map((r) => r.hash), ['done']);
  });

  test('does nothing when the daemon is not reachable', () async {
    final daemon = _FakeDaemon([_status(hash: 'A')], alive: false);
    final reaper = QbittorrentCompletedTorrentReaper(daemon, log);

    expect(await reaper.sweep(), isEmpty);
    expect(daemon.removed, isEmpty);
  });
}
