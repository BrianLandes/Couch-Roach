import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/acquisition/jackett_process.dart';
import 'package:couch_roach/src/services/acquisition/jackett_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Client okClient() => MockClient((_) async => http.Response('', 200));

  test('start() is a safe no-op when Jackett is not bundled', () async {
    // The test runner has no jackett/ tree vendored next to it, so the sidecar
    // never spawns — start() logs and returns without throwing, and the resolver
    // is left unconfigured (acquisition's indexer path stays off).
    final resolver = JackettResolver(okClient(), ErrorLogService());
    final process = JackettProcess(okClient(), ErrorLogService(), resolver);

    await process.start();

    expect(process.isRunning, isFalse);
    expect(resolver.isConfigured, isFalse);
  });

  test('baseUrl points at the localhost Torznab port', () {
    expect(JackettProcess.baseUrl, 'http://127.0.0.1:9117');
  });
}
