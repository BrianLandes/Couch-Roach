import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/acquisition/jackett_process.dart';
import 'package:couch_roach/src/services/acquisition/jackett_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // Nothing answering on the port (connection refused) → skips the "adopt an
  // existing Jackett" path and falls through to the spawn/bundle check.
  http.Client noServer() =>
      MockClient((_) async => throw Exception('connection refused'));

  test('start() is a safe no-op when Jackett is not bundled', () async {
    // The test runner has no jackett/ tree vendored next to it, so the sidecar
    // never spawns — start() logs and returns without throwing, and the resolver
    // is left unconfigured (acquisition's indexer path stays off).
    final resolver = JackettResolver(noServer(), ErrorLogService());
    final process = JackettProcess(noServer(), ErrorLogService(), resolver);

    await process.start();

    expect(process.isRunning, isFalse);
    expect(resolver.isConfigured, isFalse);
  });

  test('baseUrl points at the localhost Torznab port', () {
    expect(JackettProcess.baseUrl, 'http://127.0.0.1:9117');
  });

  group('isAlive', () {
    JackettProcess make(http.Client c) =>
        JackettProcess(c, ErrorLogService(), JackettResolver(c, ErrorLogService()));

    test('true when the endpoint answers (any status)', () async {
      expect(await make(okClient()).isAlive(), isTrue);
    });

    test('false when nothing is listening', () async {
      expect(await make(noServer()).isAlive(), isFalse);
    });
  });
}

http.Client okClient() => MockClient((_) async => http.Response('', 200));
