import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/open_url.dart';
import '../../injection.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/transcode/downscale_service.dart';
import '../../services/acquisition/qbittorrent_process.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/status_pill.dart';
import 'download_format.dart';
import 'downloads_providers.dart';
import 'manage_download.dart';

/// Activity screen: everything the background torrent daemon is doing — one card
/// per torrent with progress, speed, and estimated time left. Live-updating via
/// [downloadsProvider]. 10-foot: AmbientBackground + GlassSurface, D-pad/hover
/// focusable rows, back button (not the landing page). See docs/STYLE.md.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(downloadsProvider);
    // null while the first ping is in flight; true/false once known.
    final alive = ref.watch(daemonAliveProvider).asData?.value;

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const AppBackButton(),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Downloads', style: text.headlineMedium),
                    const Spacer(),
                    _daemonPill(context, alive),
                  ],
                ),
              ),
              // A downscale in flight is activity too — and it's the slowest
              // thing the app does, so it needs somewhere visible to report.
              const _DownscaleBanner(),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const _Centered(
                    'Downloads error — see the error log.',
                    color: AppColors.danger,
                  ),
                  data: (torrents) =>
                      _list(context, ref, torrents, alive: alive),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The online/offline pill. When the client is online it's a click target that
  /// opens qBittorrent's own web UI (its localhost dashboard) — a convenience on
  /// Linux where the daemon is headless and has no other window.
  Widget _daemonPill(BuildContext context, bool? alive) {
    final pill = StatusPill.health(
      alive: alive,
      onlineLabel: 'Client online',
      offlineLabel: 'Client offline',
    );
    if (alive != true) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          if (!await openUrl(QbittorrentProcess.baseUrl)) {
            messenger.showSnackBar(const SnackBar(
              content: Text('Could not open the qBittorrent web UI — '
                  'see the error log.'),
            ));
          }
        },
        child: Tooltip(
          message: 'Open the qBittorrent web UI',
          child: pill,
        ),
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref,
      List<TorrentStatus> torrents, {required bool? alive}) {
    if (torrents.isEmpty) {
      // Distinguish "client isn't running" from "running but idle".
      return _EmptyState(offline: alive == false);
    }

    // Active downloads first (highest progress first), completed last.
    final sorted = [...torrents]..sort((a, b) {
        if (a.isComplete != b.isComplete) return a.isComplete ? 1 : -1;
        return b.progress.compareTo(a.progress);
      });

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
      ),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => _DownloadCard(
        torrent: sorted[i],
        autofocus: i == 0,
        onManage: () => showManageDownload(context, ref, sorted[i]),
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.torrent,
    this.autofocus = false,
    this.onManage,
  });

  final TorrentStatus torrent;
  final bool autofocus;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = describeTorrentState(torrent.state);
    final percent = (torrent.progress * 100)
        .toStringAsFixed(torrent.progress < 0.1 ? 1 : 0);

    return FocusableCard(
      autofocus: autofocus,
      onPressed: onManage,
      child: GlassSurface(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    torrent.name,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _StateChip(label: status.label, color: status.color),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: AppRadii.rSm,
              child: LinearProgressIndicator(
                value: torrent.progress,
                minHeight: 8,
                backgroundColor: AppColors.glassFill,
                valueColor: AlwaysStoppedAnimation(status.color),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '$percent%  ·  ${formatBytes(torrent.downloadedBytes)}'
                  ' / ${formatBytes(torrent.sizeBytes)}',
                  style: text.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const Spacer(),
                if (!torrent.isComplete) ...[
                  const Icon(Icons.download_rounded,
                      size: 15, color: AppColors.textTertiary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    formatSpeed(torrent.downloadSpeed),
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'ETA ${formatEta(torrent.etaSeconds)}',
                    style:
                        text.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.rPill,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.offline = false});
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: GlassSurface(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                size: 44, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(offline ? 'Torrent client offline' : 'Nothing downloading',
                style: text.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              offline
                  ? "The background torrent client isn't reachable, so downloads "
                      'are paused. Check the error log if this persists.'
                  : 'Anything the background client is fetching will show up here.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: TextStyle(color: color, fontSize: 16)),
    );
  }
}


/// Progress for the downscale job, when one is running. Hidden entirely when
/// idle, so the Downloads screen looks exactly as it did before on the common
/// path.
class _DownscaleBanner extends StatelessWidget {
  const _DownscaleBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<DownscaleJob?>(
      valueListenable: getIt<DownscaleService>().current,
      builder: (context, job, _) {
        if (job == null) return const SizedBox.shrink();
        final pct = job.progress == null
            ? null
            : '${(job.progress! * 100).round()}%';
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            0,
            AppSpacing.screenPadding,
            AppSpacing.md,
          ),
          child: GlassSurface(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.hd_outlined,
                          size: 18, color: AppColors.secondary),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Making "${job.title}" play smoothly',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall,
                        ),
                      ),
                      if (pct != null)
                        Text(pct,
                            style: text.labelMedium
                                ?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: AppRadii.rSm,
                    // A null value renders an indeterminate bar — right when
                    // the duration probe came back empty.
                    child: LinearProgressIndicator(
                      value: job.progress,
                      minHeight: 8,
                      backgroundColor: AppColors.glassFill,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
