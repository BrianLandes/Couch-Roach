import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';
import 'vpn_controller.dart';
import 'vpn_elevation.dart';

/// [VpnController] over ExpressVPN's official CLI — `expressvpnctl` on Windows,
/// `expressvpn` on Linux (symmetric commands). Discovers the binary rather than
/// hardcoding a path (docs/VPN.md). Windows `connect`/`disconnect` need admin, so
/// they go through the Scheduled-Task [VpnElevation]; `status` is assumed to run
/// unelevated (confirm in the spike). Never throws — failures → [VpnState.error].
@LazySingleton(as: VpnController)
class ExpressVpnController implements VpnController {
  ExpressVpnController(this._log, this._elevation);

  final ErrorLogService _log;
  final VpnElevation _elevation;

  // Version-dependent install locations to probe (never hardcode a single one).
  // First entry is the confirmed 12.69 location on the TV PC.
  static const _windowsCliCandidates = [
    r'C:\Program Files\ExpressVPN\expressvpnctl.exe',
    r'C:\Program Files (x86)\ExpressVPN\expressvpnctl.exe',
    r'C:\Program Files\ExpressVPN\services\expressvpnctl.exe',
    r'C:\Program Files (x86)\ExpressVPN\services\expressvpnctl.exe',
  ];
  static const _windowsInstallDirs = [
    r'C:\Program Files (x86)\ExpressVPN',
    r'C:\Program Files\ExpressVPN',
  ];

  /// The CLI path, or null if not found. Linux resolves the bare name off PATH.
  String? resolveCliPath() {
    if (Platform.isWindows) {
      for (final c in _windowsCliCandidates) {
        if (File(c).existsSync()) return c;
      }
      return null;
    }
    if (Platform.isLinux) return 'expressvpn';
    return null;
  }

  /// True when ExpressVPN is installed but its CLI wasn't found — i.e. the app is
  /// older than the CLI generation (≥ 12.69.0), a `tooOld` manual-fix state.
  bool _installedWithoutCli() =>
      Platform.isWindows &&
      _windowsInstallDirs.any((d) => Directory(d).existsSync());

  @override
  Future<VpnState> status() async {
    final path = resolveCliPath();
    if (path == null) {
      return _installedWithoutCli() ? VpnState.tooOld : VpnState.notInstalled;
    }
    try {
      final res = await Process.run(path, ['status']);
      return parseVpnStatus('${res.stdout}\n${res.stderr}');
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'VpnController.status');
      return VpnState.error;
    }
  }

  @override
  Future<void> connect() => _act(
      windowsTrigger: _elevation.triggerConnect, verb: 'connect', source: 'connect');

  @override
  Future<void> disconnect() => _act(
      windowsTrigger: _elevation.triggerDisconnect,
      verb: 'disconnect',
      source: 'disconnect');

  /// Run a connect/disconnect action: on Windows via the elevated Scheduled Task
  /// (falling back to a direct call, which will fail unelevated, with guidance);
  /// on Linux directly.
  Future<void> _act({
    required Future<bool> Function() windowsTrigger,
    required String verb,
    required String source,
  }) async {
    final path = resolveCliPath();
    if (path == null) return; // manual-fix state — nothing to act on
    try {
      if (Platform.isWindows) {
        if (await _elevation.isSetUp()) {
          await windowsTrigger();
        } else {
          _log.warn(
              'VPN elevation not set up — $verb needs the one-time admin task',
              source: 'VpnController.$source');
          await Process.run(path, [verb]); // best-effort; fails without admin
        }
      } else {
        await Process.run(path, [verb]);
      }
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'VpnController.$source');
    }
  }
}
