import 'package:couch_roach/src/core/media/ytdlp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bundledYtDlpPath', () {
    test('is null when yt-dlp is not vendored next to the test runner', () {
      // No yt-dlp is bundled beside flutter_tester, so nothing resolves and the
      // player leaves libmpv's default PATH lookup in place.
      expect(bundledYtDlpPath(), isNull);
    });
  });

  group('ytdlHookScriptOpt', () {
    test('is null when there is no bundled yt-dlp to point mpv at', () {
      expect(ytdlHookScriptOpt(), isNull);
    });
  });
}
