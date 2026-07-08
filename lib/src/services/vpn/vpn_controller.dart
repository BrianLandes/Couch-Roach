// The VPN control seam (see docs/VPN.md). Mirrors the AcquisitionResolver
// pattern: one small interface, a swappable implementation per platform. The app
// ensures the tunnel is up before/while acquiring or streaming.

/// The VPN's state as the app cares about it. `notInstalled` / `tooOld` /
/// `notSignedIn` are the "surface it, the user fixes it manually" states — the
/// app never tries to install, update, or sign in on the user's behalf.
enum VpnState {
  connected,
  disconnected,
  connecting,
  notInstalled,
  tooOld,
  notSignedIn,
  error,
  unknown;

  /// A state the user must resolve manually (install / update / sign in).
  bool get isManualFix =>
      this == notInstalled || this == tooOld || this == notSignedIn;

  /// The tunnel is up.
  bool get isConnected => this == connected;
}

/// Drives the platform VPN CLI (ExpressVPN's `expressvpnctl` on Windows /
/// `expressvpn` on Linux). Implementations never throw — failures map to
/// [VpnState.error] and are logged.
abstract class VpnController {
  /// Current tunnel state (a `status` poll).
  Future<VpnState> status();

  /// Turn the tunnel on (Smart Location / last server). Needs elevation on
  /// Windows — routed through the Scheduled-Task helper.
  Future<void> connect();

  /// Turn the tunnel off.
  Future<void> disconnect();
}

/// Map raw `expressvpnctl status` output to a [VpnState]. Keyword-based and
/// case-insensitive, checked most-specific first (note "disconnected" *contains*
/// "connected", so the negative cases must win).
///
/// ⚠️ The exact strings ExpressVPN prints per state are undocumented — these are
/// best-effort until the on-machine spike (docs/VPN.md) confirms them. The tests
/// encode the contract; adjust both together when the real output is captured.
VpnState parseVpnStatus(String raw) {
  final s = raw.toLowerCase().trim();
  if (s.isEmpty) return VpnState.unknown;

  // Not activated / signed out — must be checked before the connect/disconnect
  // keywords in case the message mentions connecting to sign in.
  if (s.contains('not signed in') ||
      s.contains('not activated') ||
      s.contains('please sign in') ||
      s.contains('please activate') ||
      s.contains('sign in to') ||
      s.contains('log in to') ||
      s.contains('activate your')) {
    return VpnState.notSignedIn;
  }
  if (s.contains('connecting') || s.contains('reconnecting')) {
    return VpnState.connecting;
  }
  // "disconnected" / "not connected" — before the bare "connected" match.
  if (s.contains('disconnect') || s.contains('not connected')) {
    return VpnState.disconnected;
  }
  if (s.contains('connected')) return VpnState.connected;
  return VpnState.unknown;
}
