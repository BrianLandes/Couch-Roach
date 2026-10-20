import 'package:couch_roach/src/features/player/player_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isMediaPlayPauseKey', () {
    test('recognizes all three media transport keys', () {
      // Keyboards and remotes disagree about which one they emit.
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaPlayPause), isTrue);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaPlay), isTrue);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaPause), isTrue);
    });

    test('other keys — including the ones media_kit binds — are not', () {
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.space), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.arrowLeft), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.arrowRight), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.escape), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaStop), isFalse);
    });
  });

  group('media commands', () {
    test('keys map to toggle / play / pause; others to null', () {
      expect(mediaCommandForKey(LogicalKeyboardKey.mediaPlayPause),
          MediaCommand.toggle);
      expect(mediaCommandForKey(LogicalKeyboardKey.mediaPlay),
          MediaCommand.play);
      expect(mediaCommandForKey(LogicalKeyboardKey.mediaPause),
          MediaCommand.pause);
      expect(mediaCommandForKey(LogicalKeyboardKey.space), isNull);
    });

    test('OS button names map to commands', () {
      expect(mediaCommandForButton('play'), MediaCommand.play);
      expect(mediaCommandForButton('pause'), MediaCommand.pause);
      expect(mediaCommandForButton('toggle'), MediaCommand.toggle);
      expect(mediaCommandForButton('next'), isNull);
    });

    test('only toggle flips; play and pause are idempotent', () {
      expect(playingAfter(MediaCommand.toggle, playing: true), isFalse);
      expect(playingAfter(MediaCommand.toggle, playing: false), isTrue);
      expect(playingAfter(MediaCommand.play, playing: true), isTrue);
      expect(playingAfter(MediaCommand.pause, playing: false), isFalse);
    });
  });

  group('MediaKeyDebouncer', () {
    late DateTime now;
    late MediaKeyDebouncer debouncer;

    setUp(() {
      now = DateTime(2026, 10, 20, 20);
      debouncer = MediaKeyDebouncer(clock: () => now);
    });

    test('the first route of a press acts; its echoes are dropped', () {
      expect(debouncer.accept(), isTrue); // raw key
      now = now.add(const Duration(milliseconds: 30));
      expect(debouncer.accept(), isFalse); // SMTC echo
      now = now.add(const Duration(milliseconds: 30));
      expect(debouncer.accept(), isFalse); // WM_APPCOMMAND echo
    });

    test('a deliberate second press after the window acts', () {
      expect(debouncer.accept(), isTrue);
      now = now.add(MediaKeyDebouncer.window);
      expect(debouncer.accept(), isTrue);
    });
  });

  group('volumeAfterScroll', () {
    test('wheel up is louder, down is quieter, by 5', () {
      expect(volumeAfterScroll(50, -120), 55);
      expect(volumeAfterScroll(50, 120), 45);
    });

    test('clamps to 0..100 and ignores a zero delta', () {
      expect(volumeAfterScroll(98, -120), 100);
      expect(volumeAfterScroll(3, 120), 0);
      expect(volumeAfterScroll(40, 0), 40);
    });
  });
}
