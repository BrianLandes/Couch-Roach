import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/vpn/vpn_service.dart';
import '../../services/vpn/vpn_controller.dart';

/// Live VPN state for the status indicator. Backed by [VpnService], which polls
/// the VPN CLI only while this is being watched.
final vpnStateProvider = StreamProvider<VpnState>(
  (ref) => getIt<VpnService>().states,
);
