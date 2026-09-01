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
  String errorLogContents() =>
      File(service.errorLogFilePath!).readAsStringSync();

  Directory logsDir(Directory base) => Directory('${base.path}/logs');

  test('creates a per-session pair of log files under logs/', () {
    expect(service.logFilePath, contains('logs'));
    expect(service.errorLogFilePath, contains('logs'));
    expect(service.logFilePath, isNot(service.errorLogFilePath));
    // Both carry the same launch stamp.
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

  group('verbose gating', () {
    test('info is dropped by default; warnings and errors still log', () async {
      expect(service.verbose, isFalse);
      service.info('routine chatter');
      service.warn('low disk', source: 'StorageManager');
      service.logError(StateError('boom'));
      await service.flush();

      final text = logContents();
      expect(text, isNot(contains('routine chatter')));
      expect(text, contains('low disk'));
      expect(text, contains('boom'));
    });

    test('info is recorded once verbose is on', () async {
      service.verbose = true;
      service.info('scan complete');
      await service.flush();

      expect(logContents(), contains('scan complete'));
      expect(logContents(), contains('INFO'));
    });
  });

  group('errors-only log', () {
    test('carries warnings and errors but never info', () async {
      service.verbose = true; // even with info flowing to the combined log
      service.info('scan complete');
      service.warn('low disk');
      service.logError(StateError('boom'));
      await service.flush();

      final errors = errorLogContents();
      expect(errors, contains('low disk'));
      expect(errors, contains('boom'));
      expect(errors, isNot(contains('scan complete')));

      // The combined log still has everything.
      expect(logContents(), contains('scan complete'));
      expect(logContents(), contains('boom'));
    });
  });

  test('buffers entries written before init and flushes them to both files',
      () async {
    final s = ErrorLogService()..verbose = true;
    s.info('early trace');
    s.logError(StateError('early boom'));
    final dir = await Directory.systemTemp.createTemp('cr_log_pre');
    await s.init(directory: dir);
    await s.flush();

    expect(File(s.logFilePath!).readAsStringSync(), contains('early trace'));
    // A buffered error is still routed to the errors-only file.
    final errors = File(s.errorLogFilePath!).readAsStringSync();
    expect(errors, contains('early boom'));
    expect(errors, isNot(contains('early trace')));
    dir.deleteSync(recursive: true);
  });

  group('session pruning', () {
    test('keeps the newest 10 past sessions and deletes older ones', () async {
      final base = await Directory.systemTemp.createTemp('cr_log_prune');
      final logs = logsDir(base)..createSync(recursive: true);

      // 15 past launches, each with its combined + errors file.
      for (var i = 0; i < 15; i++) {
        final stamp = '2026-01-${(i + 1).toString().padLeft(2, '0')}_00-00-00';
        File('${logs.path}/couch_roach-$stamp.log').writeAsStringSync('x');
        File('${logs.path}/couch_roach-$stamp.errors.log').writeAsStringSync('x');
      }
      // An unrelated file must be left alone.
      File('${logs.path}/notes.txt').writeAsStringSync('keep me');

      final s = ErrorLogService();
      await s.init(directory: base);
      await s.flush();

      final names = logs.listSync().map((e) => e.path.split('/').last).toList();
      // Oldest five sessions (Jan 1–5) are gone, both files each.
      expect(names.where((n) => n.contains('2026-01-01')), isEmpty);
      expect(names.where((n) => n.contains('2026-01-05')), isEmpty);
      // The 10 newest past sessions survive, plus this launch's own pair.
      expect(names.where((n) => n.contains('2026-01-06')), hasLength(2));
      expect(names.where((n) => n.contains('2026-01-15')), hasLength(2));
      expect(names, contains('notes.txt'));

      base.deleteSync(recursive: true);
    });

    test('leaves everything in place when under the retention limit', () async {
      final base = await Directory.systemTemp.createTemp('cr_log_prune2');
      final logs = logsDir(base)..createSync(recursive: true);
      for (var i = 0; i < 3; i++) {
        final stamp = '2026-02-0${i + 1}_00-00-00';
        File('${logs.path}/couch_roach-$stamp.log').writeAsStringSync('x');
      }

      final s = ErrorLogService();
      await s.init(directory: base);
      await s.flush();

      final names = logs.listSync().map((e) => e.path.split('/').last);
      expect(names.where((n) => n.startsWith('couch_roach-2026-02')), hasLength(3));

      base.deleteSync(recursive: true);
    });
  });
}
