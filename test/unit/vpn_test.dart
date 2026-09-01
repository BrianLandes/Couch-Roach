import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/features/vpn/vpn_status_chip.dart';
import 'package:couch_roach/src/services/vpn/vpn_controller.dart';
import 'package:couch_roach/src/services/vpn/vpn_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVpnController implements VpnController {
  FakeVpnController(this._status);
  VpnState _status;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<VpnState> status() async => _status;
  @override
  Future<void> connect() async {
    connectCalls++;
    _status = VpnState.connected;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _status = VpnState.disconnected;
  }
}

void main() {
  group('parseVpnStatus — real expressvpnctl 12.69 output', () {
    // Captured verbatim on the TV PC. Every state ends with a
    // "Network Lock: enabled when connected" line, which is why we match the
    // first line only (whole-string matching would read them all as connected).
    const disconnected = 'Disconnected\n'
        '\n'
        'Location: Smart (usa-salt-lake-city)\n'
        'Network Lock: enabled when connected\n'
        'Split Tunnel: disabled\n';
    const connected = 'Connected to Smart (usa-salt-lake-city)\n'
        '\n'
        'Protocol in use: LightwayUdp\n'
        'Network Lock: enabled when connected\n'
        'Split Tunnel: disabled\n';
    const notLoggedIn = 'Not logged in.\n'
        '\n'
        'Network Lock: enabled when connected\n'
        'Split Tunnel: disabled\n';

    test('Disconnected → disconnected (not fooled by "enabled when connected")',
        () {
      expect(parseVpnStatus(disconnected), VpnState.disconnected);
    });
    test('Connected to … → connected', () {
      expect(parseVpnStatus(connected), VpnState.connected);
    });
    test('Not logged in. → notSignedIn (not fooled by the detail line)', () {
      expect(parseVpnStatus(notLoggedIn), VpnState.notSignedIn);
    });
  });

  group('parseVpnStatus — extra shapes', () {
    test('connecting (assumed phrasing)', () {
      expect(parseVpnStatus('Connecting to Smart…'), VpnState.connecting);
      expect(parseVpnStatus('Reconnecting'), VpnState.connecting);
    });
    test('other sign-in phrasings', () {
      expect(parseVpnStatus('Not signed in'), VpnState.notSignedIn);
      expect(parseVpnStatus('Please sign in to continue'), VpnState.notSignedIn);
    });
    test('empty / unrecognized → unknown', () {
      expect(parseVpnStatus(''), VpnState.unknown);
      expect(parseVpnStatus('   '), VpnState.unknown);
      expect(parseVpnStatus('gibberish'), VpnState.unknown);
    });
  });

  group('VpnState', () {
    test('manual-fix states', () {
      expect(VpnState.notInstalled.isManualFix, isTrue);
      expect(VpnState.tooOld.isManualFix, isTrue);
      expect(VpnState.notSignedIn.isManualFix, isTrue);
      expect(VpnState.disconnected.isManualFix, isFalse);
      expect(VpnState.connected.isConnected, isTrue);
    });
  });

  group('VpnService.ensureConnected', () {
    test('connects when disconnected', () async {
      final c = FakeVpnController(VpnState.disconnected);
      final result = await VpnService(c, ErrorLogService()).ensureConnected();
      expect(c.connectCalls, 1);
      expect(result, VpnState.connected);
    });

    test('does nothing when already connected', () async {
      final c = FakeVpnController(VpnState.connected);
      await VpnService(c, ErrorLogService()).ensureConnected();
      expect(c.connectCalls, 0);
    });

    test('never auto-repairs a manual-fix state', () async {
      final c = FakeVpnController(VpnState.notSignedIn);
      final result = await VpnService(c, ErrorLogService()).ensureConnected();
      expect(c.connectCalls, 0);
      expect(result, VpnState.notSignedIn);
    });
  });

  test('VpnService emits the polled state to listeners', () async {
    final service = VpnService(FakeVpnController(VpnState.connected), ErrorLogService());
    // `.first` subscribes (starts a poll immediately) then cancels (stops the
    // timer), so no periodic timer leaks past the test.
    expect(await service.states.first, VpnState.connected);
  });

  group('describeVpnState', () {
    test('labels the common states', () {
      expect(describeVpnState(VpnState.connected).label, 'VPN on');
      expect(describeVpnState(VpnState.disconnected).label, 'VPN off');
      expect(describeVpnState(VpnState.notSignedIn).label, 'VPN needs setup');
      expect(describeVpnState(VpnState.connecting).label, 'VPN connecting…');
    });
  });
}
