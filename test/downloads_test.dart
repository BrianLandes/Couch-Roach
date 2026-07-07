import 'package:couch_roach/src/features/downloads/download_format.dart';
import 'package:couch_roach/src/services/acquisition/qbittorrent_daemon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('scales through units', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1073741824), '1.0 GB');
    });

    test('drops decimals at 100+ in a unit', () {
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
    });
  });

  group('formatSpeed', () {
    test('appends /s and dashes zero', () {
      expect(formatSpeed(0), '—');
      expect(formatSpeed(3 * 1024 * 1024), '3.0 MB/s');
    });
  });

  group('formatEta', () {
    test('null / non-positive is a dash', () {
      expect(formatEta(null), '—');
      expect(formatEta(0), '—');
    });

    test('formats seconds/minutes/hours/days', () {
      expect(formatEta(45), '45s');
      expect(formatEta(252), '4m 12s');
      expect(formatEta(7500), '2h 5m');
      expect(formatEta(273600), '3d 4h');
    });
  });

  group('describeTorrentState', () {
    test('maps common states to friendly labels', () {
      expect(describeTorrentState('downloading').label, 'Downloading');
      expect(describeTorrentState('stalledDL').label, 'Stalled');
      expect(describeTorrentState('pausedDL').label, 'Paused');
      expect(describeTorrentState('uploading').label, 'Complete');
      expect(describeTorrentState('error').label, 'Error');
    });

    test('falls back to the raw state when unknown', () {
      expect(describeTorrentState('weirdState').label, 'weirdState');
    });
  });

  group('parseTorrentStatus', () {
    test('reads the qBittorrent info shape', () {
      final s = parseTorrentStatus({
        'hash': 'abc',
        'name': 'Sintel',
        'progress': 0.42,
        'state': 'downloading',
        'dlspeed': 1048576,
        'size': 2000,
        'downloaded': 840,
        'eta': 300,
      });
      expect(s.name, 'Sintel');
      expect(s.progress, 0.42);
      expect(s.downloadSpeed, 1048576);
      expect(s.etaSeconds, 300);
      expect(s.isComplete, isFalse);
    });

    test('maps the ETA sentinel (8640000) to null', () {
      final s = parseTorrentStatus({'eta': 8640000, 'progress': 0.5});
      expect(s.etaSeconds, isNull);
    });

    test('nulls ETA once complete', () {
      final s = parseTorrentStatus({'eta': 120, 'progress': 1.0});
      expect(s.etaSeconds, isNull);
      expect(s.isComplete, isTrue);
    });

    test('tolerates missing fields', () {
      final s = parseTorrentStatus({});
      expect(s.name, '');
      expect(s.progress, 0);
      expect(s.etaSeconds, isNull);
    });
  });
}
