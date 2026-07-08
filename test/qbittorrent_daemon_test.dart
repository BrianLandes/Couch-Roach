import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/qbittorrent_daemon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Shape mirrors qBittorrent's GET /torrents/files entries (name, size, progress).
Map<String, dynamic> file(String name, int size, {double progress = 0}) =>
    {'name': name, 'size': size, 'progress': progress};

void main() {
  group('addResponseIsFailure', () {
    test('accepts the newer 202 + pending JSON (the IA case)', () {
      // Exact body qBittorrent 5.1+ returns while it resolves a URL/magnet.
      const body =
          '{"added_torrent_ids":[],"failure_count":0,"pending_count":1,"success_count":0}';
      expect(addResponseIsFailure(202, body), isFalse);
    });

    test('accepts the older "Ok." 200 reply', () {
      expect(addResponseIsFailure(200, 'Ok.'), isFalse);
    });

    test('treats a literal "Fails." as failure', () {
      expect(addResponseIsFailure(200, 'Fails.'), isTrue);
    });

    test('treats JSON with a real failure and nothing accepted as failure', () {
      const body =
          '{"added_torrent_ids":[],"failure_count":1,"pending_count":0,"success_count":0}';
      expect(addResponseIsFailure(200, body), isTrue);
    });

    test('accepts JSON that both failed one and accepted another', () {
      const body =
          '{"added_torrent_ids":["abc"],"failure_count":1,"pending_count":0,"success_count":1}';
      expect(addResponseIsFailure(200, body), isFalse);
    });

    test('treats a non-2xx status as failure', () {
      expect(addResponseIsFailure(403, 'Forbidden'), isTrue);
    });
  });

  group('add retry', () {
    setUp(() => QbittorrentDaemon.addResolveWindows = const [
          Duration(milliseconds: 150),
          Duration(milliseconds: 400),
        ]);
    tearDown(() => QbittorrentDaemon.addResolveWindows = const [
          Duration(seconds: 25),
          Duration(seconds: 45),
        ]);

    test('re-adds when the torrent misses the first window, then resolves',
        () async {
      var posts = 0;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          posts++;
          return http.Response('Ok.', 200);
        }
        // The torrent only shows up after the second POST (session warmed up).
        return http.Response(
            posts >= 2 ? jsonEncode([{'hash': 'H2', 'save_path': '/x'}]) : '[]',
            200);
      });
      final task = await QbittorrentDaemon(client, ErrorLogService()).add(
        const TorrentHandle(magnetOrUrl: 'u'),
        savePath: '/x',
        dedupeKey: 'k',
      ) as QbittorrentTask;

      expect(posts, 2, reason: 'first window misses → one retry');
      expect(task.hash, 'H2');
    });

    test('throws when the torrent never appears across all attempts', () async {
      final client = MockClient((req) async =>
          http.Response(req.method == 'POST' ? 'Ok.' : '[]', 200));
      expect(
        () => QbittorrentDaemon(client, ErrorLogService()).add(
          const TorrentHandle(magnetOrUrl: 'u'),
          savePath: '/x',
        ),
        throwsA(isA<TorrentDaemonException>()),
      );
    });
  });

  group('add dedupe', () {
    test('reattaches when a torrent for the dedupe key already exists', () async {
      http.Request? post;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          post = req;
          return http.Response('Ok.', 200);
        }
        // GET /torrents/info?tag=... → the already-added torrent.
        return http.Response(
            jsonEncode([
              {'hash': 'H', 'save_path': '/data'}
            ]),
            200);
      });
      final task = await QbittorrentDaemon(client, ErrorLogService()).add(
        const TorrentHandle(magnetOrUrl: 'u'),
        savePath: '/ignored',
        dedupeKey: 'popeye_x',
      ) as QbittorrentTask;

      expect(post, isNull, reason: 'must not re-add an existing torrent');
      expect(task.hash, 'H');
      expect(task.savePath, '/data'); // reuses the existing save path
    });

    test('adds with a deterministic tag when none exists yet', () async {
      var added = false;
      http.Request? post;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          added = true;
          post = req;
          return http.Response('Ok.', 200);
        }
        // Empty until the add lands, then the new torrent (for hash resolution).
        return http.Response(
            added ? jsonEncode([{'hash': 'NEW', 'save_path': '/x'}]) : '[]',
            200);
      });
      final task = await QbittorrentDaemon(client, ErrorLogService()).add(
        const TorrentHandle(magnetOrUrl: 'u'),
        savePath: '/x',
        dedupeKey: 'popeye_x',
      ) as QbittorrentTask;

      expect(post!.bodyFields['tags'], 'cr-src-popeye_x');
      expect(task.hash, 'NEW');
    });
  });

  group('control commands', () {
    // Capture the request the daemon sends, return 200.
    late http.Request captured;
    QbittorrentDaemon daemon() => QbittorrentDaemon(
          MockClient((req) async {
            captured = req;
            return http.Response('', 200);
          }),
          ErrorLogService(),
        );

    test('remove posts to /torrents/delete with deleteFiles', () async {
      await daemon().remove(hash: 'abc', deleteFiles: true);
      expect(captured.url.path, '/api/v2/torrents/delete');
      expect(captured.bodyFields, {'hashes': 'abc', 'deleteFiles': 'true'});
    });

    test('setPaused(true) stops, setPaused(false) starts', () async {
      final d = daemon();
      await d.setPaused(hash: 'h', paused: true);
      expect(captured.url.path, '/api/v2/torrents/stop');
      await d.setPaused(hash: 'h', paused: false);
      expect(captured.url.path, '/api/v2/torrents/start');
      expect(captured.bodyFields, {'hashes': 'h'});
    });

    test('setFilePriority posts joined indices + priority to filePrio', () async {
      await daemon().setFilePriority('h', [1, 3, 4], 0);
      expect(captured.url.path, '/api/v2/torrents/filePrio');
      expect(captured.bodyFields, {'hash': 'h', 'id': '1|3|4', 'priority': '0'});
    });

    test('a non-2xx control response throws', () async {
      final d = QbittorrentDaemon(
        MockClient((_) async => http.Response('no', 403)),
        ErrorLogService(),
      );
      expect(() => d.remove(hash: 'h', deleteFiles: false), throwsA(anything));
    });
  });

  group('downloadFully', () {
    test('true for small files, false for large or unknown', () {
      const threshold = QbittorrentTask.smallFileThresholdBytes;
      expect(QbittorrentTask.downloadFully(1), isTrue); // tiny
      expect(QbittorrentTask.downloadFully(threshold), isTrue); // boundary
      expect(QbittorrentTask.downloadFully(threshold + 1), isFalse);
      expect(QbittorrentTask.downloadFully(0), isFalse); // unknown size
    });
  });

  group('setSequentialDownload / setFirstLastPiecePrio', () {
    test('toggles only when the current state differs from desired', () async {
      final posts = <String>[];
      // Torrent currently has seq_dl=true, f_l_piece_prio=true.
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          posts.add(req.url.path);
          return http.Response('', 200);
        }
        return http.Response(
            jsonEncode([{'seq_dl': true, 'f_l_piece_prio': true}]), 200);
      });
      final d = QbittorrentDaemon(client, ErrorLogService());

      await d.setSequentialDownload('h', true); // already on → no toggle
      await d.setFirstLastPiecePrio('h', false); // on → off → toggle once
      await d.setSequentialDownload('h', false); // on → off → toggle once

      expect(posts, [
        '/api/v2/torrents/toggleFirstLastPiecePrio',
        '/api/v2/torrents/toggleSequentialDownload',
      ]);
    });
  });

  group('pieceRangeOf', () {
    test('parses a [first, last] pair', () {
      expect(pieceRangeOf([3, 9]), (3, 9));
    });
    test('rejects malformed/absent ranges', () {
      expect(pieceRangeOf(null), isNull);
      expect(pieceRangeOf([1]), isNull);
      expect(pieceRangeOf('nope'), isNull);
    });
  });

  group('headPieceCount', () {
    test('covers the head buffer, clamped to [2, filePieces]', () {
      // 16 MiB buffer / 1 MiB pieces = 16.
      expect(QbittorrentTask.headPieceCount(1 << 20, 100), 16);
      // Big pieces → floor of 2.
      expect(QbittorrentTask.headPieceCount(32 << 20, 100), 2);
      // Never more than the file has.
      expect(QbittorrentTask.headPieceCount(1 << 20, 5), 5);
    });
  });

  group('headAndTailReady', () {
    // file pieces 2..6; head=2 means pieces 2,3 + last(6) must be downloaded.
    List<int> states(Set<int> have, {int len = 8}) =>
        [for (var i = 0; i < len; i++) have.contains(i) ? 2 : 0];

    test('ready when head pieces and the last piece are present', () {
      expect(headAndTailReady(states({2, 3, 6}), 2, 6, 2), isTrue);
    });
    test('not ready while the last (moov/index) piece is missing', () {
      expect(headAndTailReady(states({2, 3}), 2, 6, 2), isFalse);
    });
    test('not ready while a head piece is missing', () {
      expect(headAndTailReady(states({2, 6}), 2, 6, 2), isFalse);
    });
    test('guards against an out-of-range last piece', () {
      expect(headAndTailReady(states({2, 3}, len: 4), 2, 6, 2), isFalse);
    });
  });

  group('pickPrimaryFile', () {
    test('returns null for an empty list', () {
      expect(pickPrimaryFile(const []), isNull);
    });

    test('picks the largest video file over a bigger non-video', () {
      final files = [
        file('Show/extras.zip', 5000000000), // biggest, but not video
        file('Show/S01E01.mkv', 900000000),
        file('Show/S01E02.mkv', 1200000000), // largest video → winner
        file('Show/readme.txt', 1000),
      ];
      expect(pickPrimaryFile(files)!['name'], 'Show/S01E02.mkv');
    });

    test('falls back to the largest file when none are video', () {
      final files = [
        file('disc.iso', 4000000000),
        file('cover.jpg', 200000),
      ];
      expect(pickPrimaryFile(files)!['name'], 'disc.iso');
    });

    test('matches video extensions case-insensitively', () {
      final files = [file('Movie.MP4', 700000000), file('info.nfo', 500)];
      expect(pickPrimaryFile(files)!['name'], 'Movie.MP4');
    });

    test('does not mutate the passed-in list order-dependently', () {
      // Empty size fields default to 0 and must not throw.
      final files = [
        {'name': 'a.mkv'},
        {'name': 'b.mkv', 'size': 10},
      ];
      expect(pickPrimaryFile(files)!['name'], 'b.mkv');
    });
  });

  group('findFileByName', () {
    final files = [
      file('Show/S01E01.mkv', 900000000),
      file('Show/S01E02.mkv', 1200000000),
      file('Show/readme.txt', 1000),
    ];

    test('matches by basename even when the torrent name has a root folder', () {
      // The IA metadata name is just the basename; the torrent prefixes a folder.
      expect(findFileByName(files, 'S01E02.mkv')!['name'], 'Show/S01E02.mkv');
    });

    test('matches case-insensitively', () {
      expect(findFileByName(files, 's01e01.MKV')!['name'], 'Show/S01E01.mkv');
    });

    test('returns null when nothing matches', () {
      expect(findFileByName(files, 'S03E09.mkv'), isNull);
    });

    test('returns null for an empty list', () {
      expect(findFileByName(const [], 'x.mkv'), isNull);
    });
  });
}
