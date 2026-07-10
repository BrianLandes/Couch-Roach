import 'dart:convert';

import 'package:couch_roach_launcher/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildNumberFromTag', () {
    test('parses build-N', () {
      expect(buildNumberFromTag('build-123'), 123);
      expect(buildNumberFromTag('  build-7 '), 7);
    });
    test('rejects other tag shapes', () {
      expect(buildNumberFromTag('v1.2.3'), isNull);
      expect(buildNumberFromTag('build-'), isNull);
      expect(buildNumberFromTag('build-1.2'), isNull);
    });
  });

  group('parseLatestRelease', () {
    Map<String, dynamic> release({
      required String tag,
      List<Map<String, dynamic>> assets = const [],
    }) =>
        {'tag_name': tag, 'assets': assets};

    test('extracts the build and the .zip asset api url', () {
      final info = parseLatestRelease(release(
        tag: 'build-42',
        assets: [
          {'name': 'manifest.json', 'url': 'https://api/x/1'},
          {
            'name': 'couch-roach-windows-release-build42.zip',
            'url': 'https://api/x/2',
          },
        ],
      ));
      expect(info, isNotNull);
      expect(info!.build, 42);
      expect(info.zipAssetUrl, 'https://api/x/2');
      expect(info.zipAssetName, endsWith('.zip'));
    });

    test('null when there is no zip asset', () {
      final info = parseLatestRelease(release(
        tag: 'build-42',
        assets: [
          {'name': 'manifest.json', 'url': 'https://api/x/1'},
        ],
      ));
      expect(info, isNull);
    });

    test('null for an unrecognized tag', () {
      final info = parseLatestRelease(release(
        tag: 'nightly',
        assets: [
          {'name': 'a.zip', 'url': 'https://api/x/2'},
        ],
      ));
      expect(info, isNull);
    });
  });

  group('installedBuildFrom', () {
    test('reads the build number', () {
      expect(installedBuildFrom(jsonEncode({'build': 9, 'dir': 'build-9'})), 9);
      expect(installedBuildFrom(jsonEncode({'build': '9'})), 9);
    });
    test('null for missing / garbled input', () {
      expect(installedBuildFrom(null), isNull);
      expect(installedBuildFrom('not json'), isNull);
      expect(installedBuildFrom(jsonEncode({'other': 1})), isNull);
    });
  });

  group('parseConfig', () {
    test('reads the token and defaults the repo', () {
      final c = parseConfig(jsonEncode({'githubToken': 'ghp_x'}));
      expect(c.githubToken, 'ghp_x');
      expect(c.repo, 'brianlandes/couch-roach');
    });
    test('honors a custom repo', () {
      final c = parseConfig(jsonEncode({'githubToken': 't', 'repo': 'a/b'}));
      expect(c.repo, 'a/b');
    });
    test('no token for missing / empty / garbled config', () {
      expect(parseConfig(null).githubToken, isNull);
      expect(parseConfig(jsonEncode({'githubToken': ''})).githubToken, isNull);
      expect(parseConfig('nope').githubToken, isNull);
    });
  });

  group('LauncherPaths', () {
    test('lays out the install tree under the base', () {
      const paths = LauncherPaths('/base');
      expect(paths.configFile, contains('launcher.json'));
      expect(paths.currentFile, contains('current.json'));
      expect(paths.installDir(5), endsWith('build-5'));
      expect(paths.exePath(5), endsWith('couch_roach.exe'));
    });
  });
}
