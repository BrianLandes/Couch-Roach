import 'package:couch_roach/src/core/process/bundled_executable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('bundledExecutablePath', () {
    test('returns the absolute path when the candidate is bundled', () {
      final path = bundledExecutablePath(
        ['ffprobe'],
        executableDir: '/app/bundle',
        exists: (candidate) => candidate == p.join('/app/bundle', 'ffprobe'),
      );
      expect(path, p.join('/app/bundle', 'ffprobe'));
    });

    test('returns null when no candidate exists in the bundle dir', () {
      final path = bundledExecutablePath(
        ['ffprobe'],
        executableDir: '/app/bundle',
        exists: (_) => false,
      );
      expect(path, isNull);
    });

    test('prefers the first candidate that exists, in order', () {
      final present = {p.join('/app/bundle', 'qbittorrent.exe')};
      final path = bundledExecutablePath(
        ['qbittorrent-nox.exe', 'qbittorrent.exe'],
        executableDir: '/app/bundle',
        exists: present.contains,
      );
      // The preferred nox build is absent, so it falls to the second candidate.
      expect(path, p.join('/app/bundle', 'qbittorrent.exe'));
    });

    test('joins the candidate onto the given executable dir', () {
      String? seen;
      bundledExecutablePath(
        ['yt-dlp'],
        executableDir: '/some/where',
        exists: (candidate) {
          seen = candidate;
          return false;
        },
      );
      expect(seen, p.join('/some/where', 'yt-dlp'));
    });
  });

  group('firstExecutableIn', () {
    const bin = '/local/CouchRoach/bin';
    const exeDir = '/app/bundle';

    test('prefers the earlier dir (launcher bin over next-to-exe)', () {
      final present = {
        p.join(bin, 'ffprobe.exe'),
        p.join(exeDir, 'ffprobe.exe'),
      };
      final path = firstExecutableIn(['ffprobe.exe'], [bin, exeDir], present.contains);
      expect(path, p.join(bin, 'ffprobe.exe'));
    });

    test('falls back to a later dir when the earlier one lacks it', () {
      final present = {p.join(exeDir, 'ffprobe.exe')};
      final path = firstExecutableIn(['ffprobe.exe'], [bin, exeDir], present.contains);
      expect(path, p.join(exeDir, 'ffprobe.exe'));
    });

    test('null when no dir has any candidate', () {
      final path =
          firstExecutableIn(['ffprobe.exe'], [bin, exeDir], (_) => false);
      expect(path, isNull);
    });
  });
}
