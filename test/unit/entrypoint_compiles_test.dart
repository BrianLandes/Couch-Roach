// Importing main.dart is the entire point of this test.
//
// Nothing else in the suite imports it, so `flutter test` never compiled it —
// which meant a broken entrypoint (a missing import, or a const the compiler
// rejects but the analyzer accepts) sailed through a green test run and only
// blew up 60s into the Windows build. Pulling it into the suite makes the cheap
// Linux gate cover it.
import 'package:couch_roach/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main.dart compiles and exposes an entrypoint', () {
    expect(app.main, isA<Function>());
  });
}
