import 'package:couch_roach/src/core/input/input_mode.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:couch_roach/src/widgets/focusable_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Match the app (main.dart): always show the focus ring, so a mouse-driven
  // focus change rings the card in the test's default (touch) highlight mode.
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    // Hover only drives selection in pointer mode; start every test there.
    inputMode.onPointerAction();
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    inputMode.onPointerAction(); // don't leak keyboard mode across tests
  });

  // The border colour of the card wrapping [label]'s text tells us whether it's
  // the selected (focus-ringed) card.
  Color ringColor(WidgetTester tester, String label) {
    final container = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return ((container.decoration as BoxDecoration).border as Border).top.color;
  }

  bool isSelected(WidgetTester tester, String label) =>
      ringColor(tester, label) == AppColors.focus;

  Future<void> pumpTwoCards(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Row(
            children: [
              FocusableCard(
                  child: SizedBox(width: 100, height: 100, child: Text('A'))),
              FocusableCard(
                  child: SizedBox(width: 100, height: 100, child: Text('B'))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hovering a card selects it and unselects the other',
      (tester) async {
    await pumpTwoCards(tester);

    // Nothing selected initially.
    expect(isSelected(tester, 'A'), isFalse);
    expect(isSelected(tester, 'B'), isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    // Hover A → A becomes the single selection.
    await mouse.moveTo(tester.getCenter(find.text('A')));
    await tester.pumpAndSettle();
    expect(isSelected(tester, 'A'), isTrue);
    expect(isSelected(tester, 'B'), isFalse);

    // Hover B → selection moves to B; only one card is ever ringed.
    await mouse.moveTo(tester.getCenter(find.text('B')));
    await tester.pumpAndSettle();
    expect(isSelected(tester, 'A'), isFalse);
    expect(isSelected(tester, 'B'), isTrue);
  });

  testWidgets('selection stays put when the pointer leaves the card',
      (tester) async {
    await pumpTwoCards(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('A')));
    await tester.pumpAndSettle();
    expect(isSelected(tester, 'A'), isTrue);

    // Move the mouse off both cards — A stays selected (so the arrow keys can
    // pick up from where the mouse was), rather than clearing.
    await mouse.moveTo(const Offset(500, 500));
    await tester.pumpAndSettle();
    expect(isSelected(tester, 'A'), isTrue);
    expect(isSelected(tester, 'B'), isFalse);
  });

  group('input mode gates hover-to-select', () {
    testWidgets('in keyboard mode, hovering does NOT move the selection',
        (tester) async {
      await pumpTwoCards(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // Select A by hover while still in pointer mode.
      await mouse.moveTo(tester.getCenter(find.text('A')));
      await tester.pumpAndSettle();
      expect(isSelected(tester, 'A'), isTrue);

      // The user picks up the remote and arrow-navigates.
      inputMode.onKeyboardNav();

      // Cursor drift across B (an air-mouse jitters) must not steal the
      // selection — this is the bug the input mode exists to fix.
      await mouse.moveTo(tester.getCenter(find.text('B')));
      await tester.pumpAndSettle();
      expect(isSelected(tester, 'B'), isFalse);
      expect(isSelected(tester, 'A'), isTrue);
    });

    // A click always selects + activates, whatever the mode — the card is
    // never "locked out" by keyboard mode. (Flipping the mode back to pointer
    // is the app-level Listener's job in app.dart, not the card's.)
    testWidgets('a click selects and activates the card even in keyboard mode',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Row(
              children: [
                FocusableCard(
                  onPressed: () => pressed++,
                  child: const SizedBox(width: 100, height: 100, child: Text('A')),
                ),
                FocusableCard(
                  onPressed: () {},
                  child: const SizedBox(width: 100, height: 100, child: Text('B')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      inputMode.onKeyboardNav();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      // The tap fired and moved the highlight onto the clicked card.
      expect(pressed, 1);
      expect(isSelected(tester, 'A'), isTrue);
    });
  });
}
