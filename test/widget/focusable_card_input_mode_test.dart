import 'package:couch_roach/src/core/input/input_mode.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:couch_roach/src/widgets/focusable_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The focus ring color is our observable proxy for "this card is selected".
  bool ringShown(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(FocusableCard),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final border = (container.decoration as BoxDecoration).border as Border;
    return border.top.color == AppColors.focus;
  }

  Future<void> pumpCard(WidgetTester tester) async {
    // Mirror main(): the ring always shows when a card is focused, so it's a
    // faithful proxy for selection regardless of the test's input-mode plumbing.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FocusableCard(
              onPressed: () {},
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> hoverCenter(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(FocusableCard)));
    await tester.pumpAndSettle();
    return gesture;
  }

  testWidgets('hover selects the card in pointer mode', (tester) async {
    inputMode.onPointerAction();
    await pumpCard(tester);
    expect(ringShown(tester), isFalse);

    await hoverCenter(tester);
    expect(ringShown(tester), isTrue, reason: 'pointer-mode hover should focus');
  });

  testWidgets('hover does NOT select the card in keyboard mode', (tester) async {
    inputMode.onKeyboardNav();
    await pumpCard(tester);

    await hoverCenter(tester);
    expect(ringShown(tester), isFalse,
        reason: 'keyboard-mode hover must not hijack the selection');

    inputMode.onPointerAction(); // reset the global for other tests
  });
}
