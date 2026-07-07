import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, warning, error }

/// Central error/diagnostics sink. Every system opts in by sending failures here
/// — `getIt<ErrorLogService>().logError(e, stackTrace: st, source: 'X.op')` — and
/// the app's global handlers route uncaught framework/async errors through it too
/// (wired in main()). Entries are appended to a human-readable text log the user
/// can find locally (there's no remote backend — this is the single-machine
/// equivalent of the Supabase error table in the sibling projects).
///
/// The log lives at `<app-support>/logs/couch_roach.log` (surfaced in the
/// Storage settings screen). Call [init] once at startup; writes before then are
/// buffered and flushed when the file is ready.
@LazySingleton()
class ErrorLogService {
  ErrorLogService();

  static const _fileName = 'couch_roach.log';
  static const _maxBytes = 5 * 1024 * 1024; // rotate past ~5 MB

  File? _file;
  final List<String> _pending = [];
  Future<void> _writes = Future<void>.value();

  /// Absolute path to the active log file, or null before [init].
  String? get logFilePath => _file?.path;

  /// Prepare the log file (rotating an oversized one). [directory] overrides the
  /// default app-support location — used by tests.
  Future<void> init({Directory? directory}) async {
    final base = directory ?? await getApplicationSupportDirectory();
    final logDir = Directory(p.join(base.path, 'logs'));
    if (!logDir.existsSync()) logDir.createSync(recursive: true);

    final file = File(p.join(logDir.path, _fileName));
    if (file.existsSync() && await file.length() > _maxBytes) {
      final rolled = File('${file.path}.1');
      if (rolled.existsSync()) rolled.deleteSync();
      file.renameSync(rolled.path);
    }
    _file = File(p.join(logDir.path, _fileName));

    _write('──────── session started ${_timestamp()} ────────');
    final buffered = List<String>.of(_pending);
    _pending.clear();
    for (final line in buffered) {
      _write(line);
    }
  }

  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? source,
  }) {
    final line = StringBuffer()
      ..write(_timestamp())
      ..write('  ')
      ..write(level.name.toUpperCase().padRight(7))
      ..write(source == null ? '' : '[$source] ')
      ..write(message);
    if (error != null) line.write('  :: $error');
    var entry = line.toString();
    if (stackTrace != null) entry = '$entry\n$stackTrace';
    _emit(entry);
  }

  /// Opt-in entry point for other systems.
  void logError(
    Object error, {
    StackTrace? stackTrace,
    String? source,
    String? message,
  }) {
    log(
      LogLevel.error,
      message ?? error.toString(),
      error: message == null ? null : error,
      stackTrace: stackTrace,
      source: source,
    );
  }

  void warn(String message, {String? source}) =>
      log(LogLevel.warning, message, source: source);

  void info(String message, {String? source}) =>
      log(LogLevel.info, message, source: source);

  /// Handler for `FlutterError.onError`.
  void onFlutterError(FlutterErrorDetails details) {
    log(
      LogLevel.error,
      details.exceptionAsString(),
      stackTrace: details.stack,
      source: 'flutter',
    );
    FlutterError.presentError(details); // keep default console reporting
  }

  /// Handler for `PlatformDispatcher.instance.onError`.
  bool onPlatformError(Object error, StackTrace stack) {
    logError(error, stackTrace: stack, source: 'platform');
    return true;
  }

  /// Awaits all queued writes — call before shutdown or in tests.
  Future<void> flush() => _writes;

  void _emit(String entry) {
    if (kDebugMode) debugPrint(entry);
    if (_file == null) {
      _pending.add(entry);
      return;
    }
    _write(entry);
  }

  void _write(String entry) {
    final file = _file;
    if (file == null) return;
    // Serialize appends so lines never interleave; logging must never throw
    // back into the app.
    _writes = _writes.then((_) async {
      try {
        await file.writeAsString('$entry\n', mode: FileMode.append);
      } catch (_) {
        // swallow — a failed log write can't be allowed to break the app
      }
    });
  }

  String _timestamp() => DateTime.now().toIso8601String();
}
