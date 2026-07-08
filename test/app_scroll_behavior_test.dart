import 'package:couch_roach/src/core/app_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _horizontalList(ScrollController controller, {ScrollBehavior? behavior}) {
  final list = SizedBox(
    height: 120,
    child: ListView.builder(
      controller: controller,
      scrollDirection: Axis.horizontal,
      itemCount: 60,
      itemBuilder: (_, i) => SizedBox(width: 120, child: Center(child: Text('$i'))),
    ),
  );
  return MaterialApp(
    scrollBehavior: behavior,
    home: Scaffold(body: list),
  );
}

void main() {
  testWidgets('a mouse drag scrolls a horizontal rail under AppScrollBehavior',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      _horizontalList(controller, behavior: const AppScrollBehavior()),
    );
    expect(controller.offset, 0);

    await tester.drag(find.byType(ListView), const Offset(-300, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0),
        reason: 'the cursor can drag the rail sideways');
  });

  testWidgets('the default behavior ignores a mouse drag (regression guard)',
      (tester) async {
    final controller = ScrollController();
    // No scrollBehavior override → Flutter's default excludes the mouse.
    await tester.pumpWidget(_horizontalList(controller));

    await tester.drag(find.byType(ListView), const Offset(-300, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(controller.offset, 0, reason: 'mouse drag does nothing by default');
  });

  test('AppScrollBehavior adds the mouse to the drag devices', () {
    expect(const AppScrollBehavior().dragDevices,
        contains(PointerDeviceKind.mouse));
  });
}
