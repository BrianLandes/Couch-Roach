import 'package:couch_roach/src/features/player/player_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

    void wait(int ms) => now = now.add(Duration(milliseconds: ms));

    test('the first route of a press acts; its quick echoes are dropped', () {
      expect(debouncer.accept(fromKey: true), isTrue); // raw key
      wait(30);
      expect(debouncer.accept(fromKey: false), isFalse); // SMTC echo
      wait(30);
      expect(debouncer.accept(fromKey: false), isFalse); // WM_APPCOMMAND echo
    });

    test('a slow OS echo after a raw key is still dropped', () {
      // SMTC delivering 700ms late would arrive as the opposite command and
      // undo the press — the "works less often" bug.
      expect(debouncer.accept(fromKey: true), isTrue);
      wait(700);
      expect(debouncer.accept(fromKey: false), isFalse);
    });

    test('an OS-only press (window not focused) uses the short window', () {
      expect(debouncer.accept(fromKey: false), isTrue);
      wait(30);
      expect(debouncer.accept(fromKey: true), isFalse); // raw echo
      wait(MediaKeyDebouncer.window.inMilliseconds);
      expect(debouncer.accept(fromKey: false), isTrue); // next real press
    });

    test('a deliberate second key press after the short window acts', () {
      expect(debouncer.accept(fromKey: true), isTrue);
      wait(MediaKeyDebouncer.window.inMilliseconds);
      expect(debouncer.accept(fromKey: true), isTrue);
    });

    test('OS presses work again once the echo window has passed', () {
      expect(debouncer.accept(fromKey: true), isTrue);
      wait(MediaKeyDebouncer.osEchoWindow.inMilliseconds);
      expect(debouncer.accept(fromKey: false), isTrue);
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

  group('playerKeyboardShortcuts', () {
    late List<String> calls;
    late Map<ShortcutActivator, VoidCallback> map;

    setUp(() {
      calls = [];
      map = playerKeyboardShortcuts(
        playOrPause: () => calls.add('toggle'),
        seekBy: (d) => calls.add('seek ${d.inSeconds}'),
        nudgeVolume: (v) => calls.add('volume $v'),
        toggleFullscreen: () => calls.add('fullscreen'),
        leaveFullscreen: () => calls.add('leave'),
      );
    });

    // SingleActivator has no value equality, so match on its trigger key.
    VoidCallback? on(LogicalKeyboardKey key) {
      for (final e in map.entries) {
        final a = e.key;
        if (a is SingleActivator && a.trigger == key) return e.value;
      }
      return null;
    }

    test('leaves the media Play/Pause keys to the debounced handler', () {
      // A binding here toggled a second time per press, undoing it.
      for (final key in [
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPause,
      ]) {
        expect(
            map.keys.whereType<SingleActivator>().any((a) => a.trigger == key),
            isFalse,
            reason: '$key must not be bound');
      }
    });

    test('keeps the usual YouTube-style keys', () {
      on(LogicalKeyboardKey.space)!();
      on(LogicalKeyboardKey.keyJ)!();
      on(LogicalKeyboardKey.keyI)!();
      on(LogicalKeyboardKey.arrowLeft)!();
      on(LogicalKeyboardKey.arrowRight)!();
      on(LogicalKeyboardKey.arrowUp)!();
      on(LogicalKeyboardKey.arrowDown)!();
      on(LogicalKeyboardKey.keyF)!();
      on(LogicalKeyboardKey.escape)!();
      expect(calls, [
        'toggle',
        'seek -10',
        'seek 10',
        'seek -2',
        'seek 2',
        'volume 5.0',
        'volume -5.0',
        'fullscreen',
        'leave',
      ]);
    });
  });
}
