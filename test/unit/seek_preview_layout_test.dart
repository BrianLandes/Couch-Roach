import 'dart:ui';

import 'package:couch_roach/src/features/player/seek_preview_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(1016, 600); // bar spans x 16..1000 (984 wide)
  final barY = size.height - kPlayerSeekBarTopFromBottom + kPlayerSeekBarHeight / 2;

  group('seekBarFraction', () {
    test('maps x along the bar to 0..1', () {
      expect(seekBarFraction(Offset(16, barY), size), 0.0);
      expect(seekBarFraction(Offset(508, barY), size), 0.5);
      expect(seekBarFraction(Offset(1000, barY), size), 1.0);
    });

    test('null above or below the bar', () {
      expect(seekBarFraction(const Offset(500, 300), size), isNull);
      expect(seekBarFraction(Offset(500, size.height - 2), size), isNull);
    });

    test('a little slop at the edges still counts, clamped', () {
      expect(seekBarFraction(Offset(12, barY), size), 0.0);
      expect(seekBarFraction(Offset(1004, barY), size), 1.0);
      expect(seekBarFraction(Offset(2, barY), size), isNull);
    });

    test('while dragging, vertical drift is ignored', () {
      expect(seekBarFraction(const Offset(508, 100), size, dragging: true),
          0.5);
      expect(seekBarFraction(const Offset(-50, 100), size, dragging: true),
          0.0);
    });
  });

  group('seekPreviewLeft', () {
    test('centres over the pointer', () {
      expect(
          seekPreviewLeft(
              fraction: 0.5, playerWidth: 1016, previewWidth: 240),
          508 - 120);
    });

    test('stays inside the player at both ends', () {
      expect(
          seekPreviewLeft(fraction: 0, playerWidth: 1016, previewWidth: 240),
          8);
      expect(
          seekPreviewLeft(fraction: 1, playerWidth: 1016, previewWidth: 240),
          1016 - 240 - 8);
    });
  });

  test('formatPreviewTime', () {
    expect(formatPreviewTime(Duration.zero), '0:00');
    expect(formatPreviewTime(const Duration(minutes: 4, seconds: 5)), '4:05');
    expect(formatPreviewTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03');
  });
}
