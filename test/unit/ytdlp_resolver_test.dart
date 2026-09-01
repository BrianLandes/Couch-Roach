import 'dart:convert';

import 'package:couch_roach/src/core/media/ytdlp_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseYtDlpJson', () {
    test('extracts the direct url and http headers', () {
      final json = jsonEncode({
        'id': 'abc123',
        'title': 'A Trailer',
        'url': 'https://rr3---sn-x.googlevideo.com/videoplayback?foo=bar',
        'http_headers': {
          'User-Agent': 'Mozilla/5.0',
          'Accept-Language': 'en-us,en;q=0.5',
        },
      });

      final stream = parseYtDlpJson(json);
      expect(stream, isNotNull);
      expect(stream!.url,
          'https://rr3---sn-x.googlevideo.com/videoplayback?foo=bar');
      expect(stream.headers['User-Agent'], 'Mozilla/5.0');
      expect(stream.headers['Accept-Language'], 'en-us,en;q=0.5');
    });

    test('headers default to empty when absent', () {
      final stream = parseYtDlpJson(jsonEncode({'url': 'https://x/v.mp4'}));
      expect(stream, isNotNull);
      expect(stream!.url, 'https://x/v.mp4');
      expect(stream.headers, isEmpty);
    });

    test('tolerates surrounding whitespace / trailing newline', () {
      final stream = parseYtDlpJson('  ${jsonEncode({'url': 'https://x/v'})}\n');
      expect(stream?.url, 'https://x/v');
    });

    test('returns null when there is no usable url', () {
      expect(parseYtDlpJson(jsonEncode({'id': 'x'})), isNull);
      expect(parseYtDlpJson(jsonEncode({'url': ''})), isNull);
    });

    test('returns null on non-object / malformed JSON', () {
      // A playlist dump is a bare array, not a single info object.
      expect(parseYtDlpJson(jsonEncode([1, 2, 3])), isNull);
      expect(parseYtDlpJson('not json at all'), isNull);
      expect(parseYtDlpJson(''), isNull);
    });

    test('coerces non-string header values to strings', () {
      final stream = parseYtDlpJson(jsonEncode({
        'url': 'https://x/v',
        'http_headers': {'X-Retry': 3},
      }));
      expect(stream!.headers['X-Retry'], '3');
    });
  });

  group('parseYtDlpJson picks the right headers', () {
    // The trailer-403 regression: YouTube ties a playback URL to the client
    // that extracted it (`c=ANDROID_VR`) and rejects a fetch whose User-Agent
    // doesn't match. yt-dlp's top-level http_headers carried a desktop-Chrome
    // UA while the selected format came from a different client.
    test('prefers the selected format\'s headers over the top-level ones', () {
      const json = '''
      {
        "url": "https://example.googlevideo.com/videoplayback?c=ANDROID_VR",
        "http_headers": {"User-Agent": "Mozilla/5.0 Chrome/148"},
        "formats": [
          {"url": "https://other", "http_headers": {"User-Agent": "wrong"}},
          {
            "url": "https://example.googlevideo.com/videoplayback?c=ANDROID_VR",
            "http_headers": {"User-Agent": "com.google.android.apps.youtube.vr"}
          }
        ]
      }''';
      final r = parseYtDlpJson(json);
      expect(r!.headers['User-Agent'], 'com.google.android.apps.youtube.vr');
    });

    test('falls back to top-level headers when no format matches', () {
      const json = '''
      {
        "url": "https://a",
        "http_headers": {"User-Agent": "generic"},
        "formats": [{"url": "https://b", "http_headers": {"User-Agent": "x"}}]
      }''';
      expect(parseYtDlpJson(json)!.headers['User-Agent'], 'generic');
    });

    test('falls back when the matching format carries no headers', () {
      const json = '''
      {
        "url": "https://a",
        "http_headers": {"User-Agent": "generic"},
        "formats": [{"url": "https://a"}]
      }''';
      expect(parseYtDlpJson(json)!.headers['User-Agent'], 'generic');
    });

    test('a missing formats array is fine', () {
      const json = '{"url":"https://a","http_headers":{"User-Agent":"g"}}';
      expect(parseYtDlpJson(json)!.headers['User-Agent'], 'g');
    });
  });

  group('mpvHeaderFields', () {
    test('formats headers as mpv list entries', () {
      expect(mpvHeaderFields({'Accept': 'text/html, */*'}),
          ['Accept: text/html, */*']);
    });

    test('drops the headers mpv must own itself', () {
      // User-Agent goes through mpv's dedicated property; the rest are
      // per-connection and overriding them corrupts the request.
      final out = mpvHeaderFields({
        'User-Agent': 'x',
        'Accept-Encoding': 'gzip',
        'Host': 'example.com',
        'Connection': 'keep-alive',
        'Content-Length': '5',
        'Range': 'bytes=0-',
        'Accept-Language': 'en-US',
      });
      expect(out, ['Accept-Language: en-US']);
    });

    test('is case-insensitive about which names to drop', () {
      expect(mpvHeaderFields({'user-agent': 'x', 'ACCEPT-ENCODING': 'gzip'}),
          isEmpty);
    });

    test('skips empty values and handles an empty map', () {
      expect(mpvHeaderFields({'X-Thing': ''}), isEmpty);
      expect(mpvHeaderFields(const {}), isEmpty);
    });
  });

  group('pickSubtitleFile', () {
    test('returns null when nothing looks like a subtitle', () {
      expect(pickSubtitleFile(const []), isNull);
      expect(
        pickSubtitleFile(const ['/t/trailer.mp4', '/t/trailer.info.json']),
        isNull,
      );
    });

    test('picks a .vtt (and .srt) sidecar', () {
      expect(pickSubtitleFile(const ['/t/trailer.en.vtt']), '/t/trailer.en.vtt');
      expect(pickSubtitleFile(const ['/t/trailer.en.srt']), '/t/trailer.en.srt');
    });

    test('prefers the plain language over a regional variant (shortest name)',
        () {
      final pick = pickSubtitleFile(const [
        '/t/trailer.en-US.vtt',
        '/t/trailer.en.vtt',
        '/t/trailer.en-GB.vtt',
      ]);
      expect(pick, '/t/trailer.en.vtt');
    });

    test('ignores non-subtitle files mixed in', () {
      final pick = pickSubtitleFile(const [
        '/t/trailer.mp4',
        '/t/trailer.en.vtt',
        '/t/trailer.jpg',
      ]);
      expect(pick, '/t/trailer.en.vtt');
    });
  });
}
