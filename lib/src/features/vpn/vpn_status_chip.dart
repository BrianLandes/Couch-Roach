import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/vpn/vpn_controller.dart';
import '../../services/vpn/vpn_service.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import 'vpn_providers.dart';

/// Presentation for a [VpnState]: a short label, an accent color, and an icon.
/// Pure — exposed for testing.
({String label, Color color, IconData icon}) describeVpnState(VpnState state) {
  return switch (state) {
    VpnState.connected =>
      (label: 'VPN on', color: AppColors.success, icon: Icons.lock_rounded),
    VpnState.connecting => (
        label: 'VPN connecting…',
        color: AppColors.secondary,
        icon: Icons.sync_rounded
      ),
    VpnState.disconnected => (
        label: 'VPN off',
        color: AppColors.warning,
        icon: Icons.lock_open_rounded
      ),
    VpnState.notInstalled ||
    VpnState.tooOld ||
    VpnState.notSignedIn =>
      (label: 'VPN needs setup', color: AppColors.danger, icon: Icons.error_outline_rounded),
    VpnState.error || VpnState.unknown => (
        label: 'VPN ?',
        color: AppColors.textTertiary,
        icon: Icons.help_outline_rounded
      ),
  };
}

/// A 10-foot VPN status chip. Tapping it connects when the tunnel is off, or
/// explains the manual fix when the app needs setup (install / update / sign in).
/// Focus- and pointer-reachable per docs/STYLE.md.
class VpnStatusChip extends ConsumerWidget {
  const VpnStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Default to `unknown` until the first poll lands (and if the VPN service
    // isn't wired, e.g. in a widget test, the provider just stays unknown).
    final state = ref.watch(vpnStateProvider).asData?.value ?? VpnState.unknown;
    final d = describeVpnState(state);

    return FocusableCard(
      borderRadius: AppRadii.rPill,
      onPressed: () => _onTap(context, state),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: d.color.withValues(alpha: 0.12),
          borderRadius: AppRadii.rPill,
          border: Border.all(color: d.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(d.icon, size: 16, color: d.color),
            const SizedBox(width: AppSpacing.sm),
            Text(d.label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: d.color)),
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context, VpnState state) {
    if (state == VpnState.disconnected) {
      getIt<VpnService>().connect();
    } else if (state.isManualFix) {
      showDialog<void>(
        context: context,
        builder: (_) => _ManualFixDialog(state: state),
      );
    }
  }
}

class _ManualFixDialog extends StatelessWidget {
  const _ManualFixDialog({required this.state});
  final VpnState state;

  String get _message => switch (state) {
        VpnState.notInstalled =>
          'ExpressVPN isn\'t installed. Install it and sign in, then this will '
              'connect automatically.',
        VpnState.tooOld =>
          'Your ExpressVPN is too old for the command-line control this app '
              'uses. Update ExpressVPN to 12.69 or newer.',
        VpnState.notSignedIn =>
          'ExpressVPN is installed but not signed in. Open ExpressVPN and sign '
              'in, then this will connect automatically.',
        _ => 'ExpressVPN needs attention.',
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VPN needs setup', style: text.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(_message,
                style:
                    text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
