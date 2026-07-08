import 'dart:async';

import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';
import 'vpn_controller.dart';

/// Watches and drives the VPN over a [VpnController] (docs/VPN.md). Polls
/// `status` on a timer while anything is listening, exposes a broadcast
/// [states] stream for the UI, and offers [ensureConnected] to bring the tunnel
/// up before acquiring/streaming.
@LazySingleton()
class VpnService {
  VpnService(this._controller, this._log);

  final VpnController _controller;
  final ErrorLogService _log;

  static const _pollInterval = Duration(seconds: 5);

  Timer? _timer;
  VpnState _last = VpnState.unknown;

  late final StreamController<VpnState> _states = StreamController.broadcast(
    onListen: _startPolling,
    onCancel: _stopPolling,
  );

  /// Live VPN state; polling runs only while this is being listened to.
  Stream<VpnState> get states => _states.stream;

  /// Last observed state (seeds the UI before the first poll lands).
  VpnState get current => _last;

  void _startPolling() {
    unawaited(_poll());
    _timer ??= Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    final state = await _controller.status();
    _last = state;
    if (_states.hasListener) _states.add(state);
  }

  /// Bring the tunnel up if it's merely disconnected. Manual-fix states
  /// (`notInstalled` / `tooOld` / `notSignedIn`) are left for the user to
  /// resolve — never auto-repaired (per the requirement). Returns the state
  /// after the attempt.
  Future<VpnState> ensureConnected() async {
    final state = await _controller.status();
    if (state == VpnState.disconnected) {
      await _controller.connect();
      return _poll().then((_) => _last);
    }
    if (state.isManualFix) {
      _log.warn('VPN needs manual setup: $state',
          source: 'VpnService.ensureConnected');
    }
    return state;
  }

  Future<void> connect() => _controller.connect();
  Future<void> disconnect() => _controller.disconnect();

  @disposeMethod
  void dispose() {
    _stopPolling();
    _states.close();
  }
}
