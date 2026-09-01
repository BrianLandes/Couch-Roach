import 'package:couch_roach/src/services/transcode/downscale_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickHardwareEncoder', () {
    // Shaped like real `ffmpeg -encoders` output.
    const output = '''
Encoders:
 V..... = Video
 ------
 V....D h264_qsv             H.264 / AVC (Intel Quick Sync Video acceleration)
 V....D hevc_qsv             HEVC (Intel Quick Sync Video acceleration)
 V..... libsvtav1            SVT-AV1 encoder
''';

    test('picks the preferred hardware encoder that is present', () {
      expect(pickHardwareEncoder(output), 'hevc_qsv');
    });

    test('honours the preference order', () {
      const amfOnly = ' V....D hevc_amf   HEVC AMF encoder';
      expect(pickHardwareEncoder(amfOnly), 'hevc_amf');
      // qsv outranks amf when both exist.
      expect(pickHardwareEncoder('$amfOnly\n V....D hevc_qsv  HEVC QSV'),
          'hevc_qsv');
    });

    test('is null when the build has no hardware HEVC encoder', () {
      // An LGPL build with no hardware support: software encoding 4K is not a
      // fallback we want, so the feature must stay off.
      const swOnly = '''
Encoders:
 V..... mpeg4                MPEG-4 part 2
 V..... libsvtav1            SVT-AV1 encoder
''';
      expect(pickHardwareEncoder(swOnly), isNull);
      expect(pickHardwareEncoder(''), isNull);
    });

    test('does not match an encoder name that merely appears as a substring',
        () {
      expect(pickHardwareEncoder(' V..... hevc_qsv_something  Not it'), isNull);
    });
  });

  group('downscaleArgs', () {
    final args = downscaleArgs(
      input: 'in.mkv',
      output: 'out.mkv',
      encoder: 'hevc_qsv',
      maxHeight: 1080,
    );

    test('re-encodes only the video and copies every other stream', () {
      // -map 0 keeps all streams; `-c copy` then `-c:v <enc>` means the Atmos
      // audio and the subtitles are copied bit-for-bit.
      expect(args, containsAllInOrder(['-map', '0', '-c', 'copy']));
      expect(args, containsAllInOrder(['-c:v', 'hevc_qsv']));
    });

    test('scales by height with an even width, preserving aspect', () {
      expect(args, containsAllInOrder(['-vf', 'scale=-2:1080']));
    });

    test('stays 10-bit rather than tone-mapping HDR', () {
      expect(args, containsAllInOrder(['-pix_fmt', 'p010le']));
    });

    test('never blocks on stdin, and overwrites its own temp output', () {
      expect(args, contains('-nostdin'));
      expect(args, contains('-y'));
    });

    test('the output path is last', () {
      expect(args.last, 'out.mkv');
    });
  });

  group('parseFfprobeVideoHeight', () {
    test('reads the first video stream height', () {
      expect(
          parseFfprobeVideoHeight('{"streams":[{"width":3840,"height":1920}]}'),
          1920);
    });

    test('accepts a string-encoded height', () {
      expect(parseFfprobeVideoHeight('{"streams":[{"height":"1080"}]}'), 1080);
    });

    test('is null for anything unusable', () {
      for (final s in [
        '',
        'not json',
        '{}',
        '{"streams":[]}',
        '{"streams":[{}]}',
        '{"streams":[{"height":0}]}',
        '{"streams":"nope"}',
      ]) {
        expect(parseFfprobeVideoHeight(s), isNull, reason: s);
      }
    });
  });

  group('needsDownscale', () {
    test('true only when comfortably above the cap', () {
      expect(needsDownscale(height: 1920, maxHeight: 1080), isTrue);
      expect(needsDownscale(height: 2160, maxHeight: 1080), isTrue);
    });

    test('leaves a file already at or near the cap alone', () {
      // Not worth an hour of GPU time to shave 8 pixels.
      expect(needsDownscale(height: 1080, maxHeight: 1080), isFalse);
      expect(needsDownscale(height: 1088, maxHeight: 1080), isFalse);
      expect(needsDownscale(height: 720, maxHeight: 1080), isFalse);
    });

    test('off when the cap is unset, and when the height is unknown', () {
      expect(needsDownscale(height: 2160, maxHeight: 0), isFalse);
      // Unknown height must mean "leave it alone" — re-encoding something we
      // could not measure is worse than skipping it.
      expect(needsDownscale(height: null, maxHeight: 1080), isFalse);
    });
  });
}
