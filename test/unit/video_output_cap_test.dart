import 'package:couch_roach/src/features/player/video_output_cap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('0 (and anything below it) means uncapped', () {
    expect(videoOutputCap(0), isNull);
    expect(videoOutputCap(-1), isNull);
  });

  test('caps to a 16:9 box at the requested height', () {
    expect(videoOutputCap(1080), (width: 1920, height: 1080));
    expect(videoOutputCap(720), (width: 1280, height: 720));
  });

  test('the box bounds a wider-than-16:9 source, since mpv letterboxes', () {
    // The 2:1 4K case that motivated this: 3840x1920 rendered into the 1080
    // box becomes 1920x960 — a quarter of the pixels for the output stage.
    final cap = videoOutputCap(1080)!;
    expect(cap.height, 1080);
    expect(cap.width, 1920);
    const sourceW = 3840, sourceH = 1920;
    final scale = cap.width / sourceW; // width is the binding dimension here
    expect((sourceH * scale).round(), 960);
  });

  test('rounds the width rather than truncating', () {
    // 1440 * 16/9 = 2560 exactly; 900 * 16/9 = 1600 exactly. A height that
    // does not divide cleanly still yields a whole number.
    expect(videoOutputCap(1440), (width: 2560, height: 1440));
    expect(videoOutputCap(900), (width: 1600, height: 900));
    expect(videoOutputCap(1001)!.width, (1001 * 16 / 9).round());
  });
}
