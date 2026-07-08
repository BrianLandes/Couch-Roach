import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';

/// Windows elevation for `expressvpnctl connect/disconnect`, which require
/// Administrator. Strategy (docs/VPN.md "The admin problem"): register two
/// elevated Scheduled Tasks **once**, then the unelevated app triggers them with
/// `schtasks /run` — no per-call UAC on a 10-foot/remote box.
///
/// [setUp] (the one-time `schtasks /create`) itself needs an elevated context —
/// run it from the installer / a one-time admin step. The runtime triggers
/// ([triggerConnect]/[triggerDisconnect]) and [isSetUp] work unelevated.
@lazySingleton
class VpnElevation {
  VpnElevation(this._log);
  final ErrorLogService _log;

  static const connectTask = 'CouchRoach_VpnConnect';
  static const disconnectTask = 'CouchRoach_VpnDisconnect';

  /// Whether both scheduled tasks already exist.
  Future<bool> isSetUp() async {
    if (!Platform.isWindows) return false;
    return await _taskExists(connectTask) && await _taskExists(disconnectTask);
  }

  /// Register the elevated connect/disconnect tasks that run [cliPath]. Requires
  /// the calling process to be elevated (installer / one-time admin). Returns
  /// true only if both tasks were created.
  Future<bool> setUp(String cliPath) async {
    if (!Platform.isWindows) return false;
    final ok1 = await _createTask(connectTask, cliPath, 'connect');
    final ok2 = await _createTask(disconnectTask, cliPath, 'disconnect');
    return ok1 && ok2;
  }

  Future<bool> triggerConnect() => _run(connectTask);
  Future<bool> triggerDisconnect() => _run(disconnectTask);

  // ── schtasks wrappers ──────────────────────────────────────────────────────

  Future<bool> _createTask(String name, String cliPath, String verb) =>
      _schtasks([
        '/create', '/tn', name,
        // The task action: the elevated CLI with its verb.
        '/tr', '"$cliPath" $verb',
        '/sc', 'ONCE', '/st', '00:00',
        '/rl', 'HIGHEST', // run with highest privileges (elevated)
        '/f', // overwrite if it exists
      ], 'setUp');

  Future<bool> _run(String name) async {
    if (!Platform.isWindows) return false;
    return _schtasks(['/run', '/tn', name], 'trigger');
  }

  Future<bool> _taskExists(String name) =>
      _schtasks(['/query', '/tn', name], 'isSetUp', quiet: true);

  Future<bool> _schtasks(List<String> args, String source,
      {bool quiet = false}) async {
    try {
      final res = await Process.run('schtasks', args);
      if (res.exitCode != 0) {
        if (!quiet) {
          _log.warn('schtasks ${args.first} failed (${res.exitCode}): '
              '${res.stderr}', source: 'VpnElevation.$source');
        }
        return false;
      }
      return true;
    } catch (e, st) {
      if (!quiet) {
        _log.logError(e, stackTrace: st, source: 'VpnElevation.$source');
      }
      return false;
    }
  }
}
