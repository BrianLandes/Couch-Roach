import 'dart:convert';
import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/transcode/trickplay.dart';
import 'package:couch_roach/src/services/transcode/trickplay_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Unused implements LibraryRepository, TorrentDaemon {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  late Directory tmp;
  late TrickplayService service;
  late File video;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('trickplay_test');
    service = TrickplayService(_Unused(), _Unused(), ErrorLogService())
      ..rootOverride = Directory(p.join(tmp.path, 'cache'));
    video = File(p.join(tmp.path, 'Show.S01E01.mkv'))..writeAsStringSync('x');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<Directory> cacheDirFor(File f) async {
    final stat = await f.stat();
    final key = trickplayKey(
        path: f.path,
        sizeBytes: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch);
    return Directory(p.join(tmp.path, 'cache', key))..createSync(recursive: true);
  }

  test('no sheets until the manifest exists', () async {
    final dir = await cacheDirFor(video);
    File(p.join(dir.path, trickplaySheetName(0))).writeAsStringSync('jpg');
    expect(await service.sheetsFor(video.path), isNull,
        reason: 'a directory without a manifest is an unfinished run');
  });

  test('a finished cache directory is served with its sheet paths', () async {
    final dir = await cacheDirFor(video);
    File(p.join(dir.path, kTrickplayManifestName)).writeAsStringSync(
        jsonEncode(
            const TrickplayManifest(tileCount: 120, sheetCount: 2).toJson()));

    final sheets = await service.sheetsFor(video.path);

    expect(sheets, isNotNull);
    expect(sheets!.manifest.tileCount, 120);
    expect(sheets.sheetPath(1), p.join(dir.path, 'sheet_001.jpg'));
  });

  test('a changed file no longer matches its old previews', () async {
    final dir = await cacheDirFor(video);
    File(p.join(dir.path, kTrickplayManifestName)).writeAsStringSync(
        jsonEncode(
            const TrickplayManifest(tileCount: 1, sheetCount: 1).toJson()));
    video.writeAsStringSync('a different, longer file'); // e.g. downscaled

    expect(await service.sheetsFor(video.path), isNull);
  });

  test('a missing file has no previews', () async {
    expect(await service.sheetsFor(p.join(tmp.path, 'gone.mkv')), isNull);
  });
}
