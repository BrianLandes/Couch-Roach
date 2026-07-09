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
}
