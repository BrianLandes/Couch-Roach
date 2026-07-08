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

/// Map raw `expressvpnctl status` output to a [VpnState].
///
/// Confirmed on the TV PC (expressvpnctl 12.69+), the first line is the status
/// and the rest are details:
///   `Disconnected` · `Connected to <loc>` · `Not logged in.` (+ `Connecting…`)
///
/// We match **only that first line** — the detail lines include
/// `Network Lock: enabled when connected`, whose "connected" would otherwise
/// make every state read as connected. Checked most-specific first (note
/// "disconnected" *contains* "connected", so the negatives must win).
VpnState parseVpnStatus(String raw) {
  final line = raw
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '')
      .toLowerCase();
  if (line.isEmpty) return VpnState.unknown;

  // Signed out — "Not logged in." (confirmed) and other sign-in phrasings.
  if (line.contains('not logged in') ||
      line.contains('not signed in') ||
      line.contains('not activated') ||
      line.contains('log in') ||
      line.contains('sign in')) {
    return VpnState.notSignedIn;
  }
  if (line.contains('connecting') || line.contains('reconnecting')) {
    return VpnState.connecting;
  }
  // "disconnected" / "not connected" — before the bare "connected" match.
  if (line.contains('disconnect') || line.contains('not connected')) {
    return VpnState.disconnected;
  }
  if (line.contains('connected')) return VpnState.connected;
  return VpnState.unknown;
}
