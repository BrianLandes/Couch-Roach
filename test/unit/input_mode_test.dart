import 'package:couch_roach/src/core/input/input_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputModeController', () {
    test('starts in pointer mode', () {
      expect(InputModeController().value, InputMode.pointer);
    });

    test('nav switches to keyboard, pointer action switches back', () {
      final c = InputModeController();
      c.onKeyboardNav();
      expect(c.value, InputMode.keyboard);
      expect(c.isKeyboard, isTrue);
      expect(c.isPointer, isFalse);

      c.onPointerAction();
      expect(c.value, InputMode.pointer);
      expect(c.isPointer, isTrue);
    });

    test('notifies listeners only on an actual change', () {
      final c = InputModeController();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.onPointerAction(); // already pointer → no change, no notify
      expect(notifications, 0);

      c.onKeyboardNav(); // pointer → keyboard
      c.onKeyboardNav(); // keyboard → keyboard (no change)
      expect(notifications, 1);
    });
  });

  group('inputModeKeyHandler', () {
    KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
          logicalKey: key,
          physicalKey: PhysicalKeyboardKey.keyA, // irrelevant to the handler
          timeStamp: Duration.zero,
        );
    KeyUpEvent up(LogicalKeyboardKey key) => KeyUpEvent(
          logicalKey: key,
          physicalKey: PhysicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        );

    setUp(() => inputMode.onPointerAction()); // reset the global to pointer

    test('never consumes the event', () {
      expect(inputModeKeyHandler(down(LogicalKeyboardKey.arrowDown)), isFalse);
      expect(inputModeKeyHandler(down(LogicalKeyboardKey.enter)), isFalse);
    });

    test('a nav key-down switches to keyboard mode', () {
      for (final k in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.tab,
      ]) {
        inputMode.onPointerAction();
        inputModeKeyHandler(down(k));
        expect(inputMode.isKeyboard, isTrue, reason: '$k should switch mode');
      }
    });

    test('a non-nav key (Enter/Space) leaves the mode alone', () {
      inputMode.onPointerAction();
      inputModeKeyHandler(down(LogicalKeyboardKey.enter));
      inputModeKeyHandler(down(LogicalKeyboardKey.space));
      expect(inputMode.isPointer, isTrue);
    });

    test('a nav key-*up* does not switch (only key-down does)', () {
      inputMode.onPointerAction();
      inputModeKeyHandler(up(LogicalKeyboardKey.arrowDown));
      expect(inputMode.isPointer, isTrue);
    });
  });
}
