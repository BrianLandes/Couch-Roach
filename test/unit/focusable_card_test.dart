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
  });
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
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
}
