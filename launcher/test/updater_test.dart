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

    test('extracts the build, app zip, and sidecars zip (with its tag)', () {
      final info = parseLatestRelease(release(
        tag: 'build-42',
        assets: [
          {'name': 'manifest.json', 'url': 'https://api/x/1'},
          {
            'name': 'couch-roach-windows-release-build42.zip',
            'url': 'https://api/x/2',
          },
          {'name': 'sidecars-a1b2c3d4.zip', 'url': 'https://api/x/3'},
        ],
      ));
      expect(info, isNotNull);
      expect(info!.build, 42);
      expect(info.appZip!.url, 'https://api/x/2');
      expect(info.appZip!.name, endsWith('.zip'));
      expect(info.sidecars!.url, 'https://api/x/3');
      expect(info.sidecarsTag, 'a1b2c3d4');
    });

    test('sidecars null when the release has no sidecars asset', () {
      final info = parseLatestRelease(release(
        tag: 'build-42',
        assets: [
          {'name': 'app.zip', 'url': 'https://api/x/2'},
        ],
      ));
      expect(info!.appZip, isNotNull);
      expect(info.sidecars, isNull);
      expect(info.sidecarsTag, isNull);
    });

    test('the sidecars zip is not mistaken for the app zip', () {
      final info = parseLatestRelease(release(
        tag: 'build-42',
        assets: [
          {'name': 'sidecars-deadbeef.zip', 'url': 'https://api/x/3'},
        ],
      ));
      expect(info!.appZip, isNull);
      expect(info.sidecars, isNotNull);
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

  group('installedSidecarsTag', () {
    test('reads the tag', () {
      expect(installedSidecarsTag(jsonEncode({'tag': 'a1b2c3d4'})), 'a1b2c3d4');
    });
    test('null for missing / garbled input', () {
      expect(installedSidecarsTag(null), isNull);
      expect(installedSidecarsTag('nope'), isNull);
      expect(installedSidecarsTag(jsonEncode({'other': 1})), isNull);
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
      expect(paths.binDir, endsWith('bin'));
      expect(paths.sidecarsFile, contains('sidecars.json'));
    });
  });
}
