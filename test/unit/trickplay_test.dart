import 'dart:convert';

import 'package:couch_roach/src/services/transcode/trickplay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trickplayKey', () {
    String key({String path = '/tv/a.mkv', int size = 100, int mtime = 1}) =>
        trickplayKey(path: path, sizeBytes: size, modifiedMs: mtime);

    test('is stable for the same file', () {
      expect(key(), key());
      expect(key(), hasLength(16));
    });

    test('changes when the file does (path, size or mtime)', () {
      expect(key(path: '/tv/b.mkv'), isNot(key()));
      expect(key(size: 101), isNot(key())); // downscaled
      expect(key(mtime: 2), isNot(key())); // still being written
    });
  });

  test('tile and sheet counts', () {
    expect(trickplayTileCount(0), 1);
    expect(trickplayTileCount(9.5), 1);
    expect(trickplayTileCount(10), 1);
    expect(trickplayTileCount(10.1), 2);
    expect(trickplayTileCount(7200), 720); // a 2-hour film
    expect(trickplaySheetCount(720), 8);
    expect(trickplaySheetCount(100), 1);
    expect(trickplaySheetCount(101), 2);
  });

  test('sheet names match the ffmpeg output pattern, 0-based', () {
    expect(trickplaySheetName(0), 'sheet_000.jpg');
    expect(trickplaySheetName(12), 'sheet_012.jpg');
    expect(kTrickplaySheetPattern, 'sheet_%03d.jpg');
  });

  test('ffmpeg args decode keyframes only and tile fixed-size frames', () {
    final args = trickplayArgs(input: '/tv/a.mkv', outputDir: '/cache/k');
    // -skip_frame is an *input* option: it must come before -i.
    expect(args.indexOf('-skip_frame'), lessThan(args.indexOf('-i')));
    expect(args[args.indexOf('-skip_frame') + 1], 'nokey');
    final vf = args[args.indexOf('-vf') + 1];
    expect(vf, contains('fps=1/$kTrickplayIntervalSeconds'));
    expect(vf, contains('pad=$kTrickplayTileWidth:$kTrickplayTileHeight'));
    expect(vf, endsWith('tile=${kTrickplayColumns}x$kTrickplayRows'));
    expect(args[args.indexOf('-start_number') + 1], '0');
    expect(args.last, '/cache/k/$kTrickplaySheetPattern');
    expect(args, containsAll(['-an', '-sn', '-dn']));
  });

  group('TrickplayManifest', () {
    test('round-trips through JSON', () {
      const m = TrickplayManifest(tileCount: 250, sheetCount: 3);
      final back = TrickplayManifest.tryParse(jsonEncode(m.toJson()))!;
      expect(back.tileCount, 250);
      expect(back.sheetCount, 3);
      expect(back.intervalSeconds, kTrickplayIntervalSeconds);
      expect(back.columns, kTrickplayColumns);
    });

    test('rejects malformed manifests', () {
      expect(TrickplayManifest.tryParse('not json'), isNull);
      expect(TrickplayManifest.tryParse('[]'), isNull);
      expect(TrickplayManifest.tryParse('{"tileCount": 3}'), isNull);
    });

    test('tileAt maps a time to sheet, column and row', () {
      const m = TrickplayManifest(tileCount: 250, sheetCount: 3);
      expect(m.tileAt(Duration.zero), (sheet: 0, column: 0, row: 0));
      expect(m.tileAt(const Duration(seconds: 9)), (sheet: 0, column: 0, row: 0));
      expect(m.tileAt(const Duration(seconds: 125)),
          (sheet: 0, column: 2, row: 1)); // tile 12
      expect(m.tileAt(const Duration(seconds: 1005)),
          (sheet: 1, column: 0, row: 0)); // tile 100 starts sheet 2
    });

    test('tileAt clamps past the end and before the start', () {
      const m = TrickplayManifest(tileCount: 250, sheetCount: 3);
      expect(m.tileAt(const Duration(hours: 5)),
          (sheet: 2, column: 9, row: 4)); // tile 249
      expect(m.tileAt(const Duration(seconds: -3)),
          (sheet: 0, column: 0, row: 0));
    });
  });
}
