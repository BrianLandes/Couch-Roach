import 'package:couch_roach/src/services/acquisition/qbittorrent_daemon.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
