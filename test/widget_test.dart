import 'package:flutter_test/flutter_test.dart';

import 'package:couch_roach/src/app.dart';

void main() {
  // Present so `flutter create .` won't drop its default widget_test.dart
  // (which references a non-existent MyApp and breaks the build).
  testWidgets('app shell renders the title', (tester) async {
    await tester.pumpWidget(const CouchRoachApp());
    expect(find.text('Couch Roach'), findsOneWidget);
  });
}
