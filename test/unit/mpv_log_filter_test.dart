import 'package:couch_roach/src/features/player/mpv_log_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool keep(String level, String prefix, String text) =>
      isRenderPipelineLogLine(level: level, prefix: prefix, text: text);

  test('keeps the decode/render handshake lines we are diagnosing', () {
    expect(keep('v', 'vd', 'Using hardware decoding (d3d11va-copy).'), isTrue);
    expect(keep('v', 'vo/gpu', 'Loading hwdec interop d3d11egl'), isTrue);
    expect(keep('v', 'vo/gpu/opengl', 'EGL_ANGLE_d3d_share_handle'), isTrue);
    expect(keep('v', 'cplayer', 'DXVA2 not available'), isTrue);
  });

  test('keeps warnings and errors whatever their subject', () {
    expect(keep('error', 'ffmpeg', 'anything at all'), isTrue);
    expect(keep('fatal', 'cplayer', 'anything at all'), isTrue);
    expect(keep('warn', 'demux', 'unrelated subject'), isTrue);
  });

  test('drops unrelated verbose chatter', () {
    expect(keep('v', 'demux', 'Estimating number of bytes'), isFalse);
    expect(keep('v', 'cplayer', 'Set property: pause=no'), isFalse);
    expect(keep('info', 'ffmpeg/audio', 'AAC stream'), isFalse);
  });

  test('matches case-insensitively across prefix and text', () {
    expect(keep('v', 'VO/GPU', 'whatever'), isTrue);
    expect(keep('v', 'x', 'HWDEC probing'), isTrue);
  });

  test('a bare "gl" is not a keyword — it would sweep in unrelated words', () {
    expect(keep('v', 'demux', 'single glyph run'), isFalse);
  });
}
