import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ErrorLogService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cr_log_test');
    service = ErrorLogService();
    await service.init(directory: tmp);
  });
  tearDown(() async {
    await service.flush();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String logContents() => File(service.logFilePath!).readAsStringSync();

  test('creates the log file under a logs/ folder', () {
    expect(service.logFilePath, isNotNull);
    expect(service.logFilePath, contains('logs'));
    expect(File(service.logFilePath!).existsSync(), isTrue);
  });

  test('writes an error entry with source, message, and stack', () async {
    service.logError(
      StateError('boom'),
      stackTrace: StackTrace.current,
      source: 'Widget.op',
    );
    await service.flush();

    final text = logContents();
    expect(text, contains('ERROR'));
    expect(text, contains('[Widget.op]'));
    expect(text, contains('boom'));
  });

  test('records level and message for warnings/info', () async {
    service.warn('low disk', source: 'StorageManager');
    service.info('scan complete');
    await service.flush();

    final text = logContents();
    expect(text, contains('WARNING'));
    expect(text, contains('low disk'));
    expect(text, contains('INFO'));
    expect(text, contains('scan complete'));
  });

  test('buffers entries written before init and flushes them', () async {
    final s = ErrorLogService();
    s.info('before init', source: 'early');
    final dir = await Directory.systemTemp.createTemp('cr_log_pre');
    await s.init(directory: dir);
    await s.flush();

    expect(File(s.logFilePath!).readAsStringSync(), contains('before init'));
    dir.deleteSync(recursive: true);
  });
}
