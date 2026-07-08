import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
import '../../theme/theme.dart';
import '../downloads/downloads_providers.dart';
import '../player/player_screen.dart';
import 'acquire_play.dart';
import 'acquisition_controller.dart';

/// Inline, non-blocking acquire control for a not-local title: a **Download**
/// button that kicks off the download in place (no dialog), shows a live
/// **progress bar** while it fetches + buffers, then becomes a **Play** button
/// once it's ready to stream. Download continues in the background if the user
/// navigates away; an already-running download is auto-adopted so returning to
/// the page picks up its progress.
class AcquireButton extends ConsumerWidget {
  const AcquireButton({
    super.key,
    required this.title,
    required this.meta,
    this.season,
    this.episode,
    this.autofocus = false,
  });

  /// Display/player title (e.g. "The Show — S01E01 · Pilot").
  final String title;

  /// What the resolver searches for (the show/movie name + tmdb id + type).
  final ShowMeta meta;
  final int? season;
  final int? episode;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dedupeKey = acquisitionDedupeKey(
      tmdbId: meta.tmdbId,
      title: meta.title,
      season: season,
      episode: episode,
    );
    final tag = acquisitionTag(dedupeKey);
    final state = ref.watch(acquisitionControllerProvider(dedupeKey));

    // Auto-adopt: if the daemon is already running this title's download (from
    // earlier this session, or a prior run), drive the controller so the page
    // reflects its progress and rolls forward to Play — without re-downloading.
    ref.listen(downloadForTagProvider(tag), (_, next) {
      if (next != null &&
          ref.read(acquisitionControllerProvider(dedupeKey)).phase ==
              AcquirePhase.idle) {
        _start(ref, dedupeKey);
      }
    });

    switch (state.phase) {
      case AcquirePhase.preparing:
        return _Preparing(
          progress: state.progress,
          onPlayWhenReady: () => playWhenReady(
            context,
            title: title,
            meta: meta,
            season: season,
            episode: episode,
          ),
        );
      case AcquirePhase.ready:
        return FilledButton.icon(
          autofocus: autofocus,
          onPressed: () => context.push(
            Routes.player,
            extra: PlayerArgs(
              filePath: state.filePath!,
              title: title,
              libraryItemId: state.libraryItemId,
            ),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play'),
        );
      case AcquirePhase.idle:
      case AcquirePhase.failed:
        return FilledButton.icon(
          autofocus: autofocus,
          onPressed: () async {
            if (await ensureStreamingVpn(context)) _start(ref, dedupeKey);
          },
          icon: const Icon(Icons.download_rounded),
          label: Text(state.phase == AcquirePhase.failed ? 'Retry' : 'Download'),
        );
    }
  }

  void _start(WidgetRef ref, String dedupeKey) {
    ref.read(acquisitionControllerProvider(dedupeKey).notifier).start(
          title: title,
          meta: meta,
          season: season,
          episode: episode,
        );
  }
}

/// Stands in for the button while a title is preparing: a live progress bar
/// (determinate once the torrent reports progress, indeterminate before then —
/// resolving / fetching metadata) plus a **Play when Ready** action that opens
/// the blocking dialog and drops into the player the moment it's streamable.
class _Preparing extends StatelessWidget {
  const _Preparing({required this.progress, required this.onPlayWhenReady});
  final double? progress;
  final VoidCallback onPlayWhenReady;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = progress == null
        ? 'Starting…'
        : 'Downloading ${(progress! * 100).round()}%';
    return SizedBox(
      width: 176,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadii.rSm,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.glassFill,
              valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label,
              style: text.labelMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: onPlayWhenReady,
            icon: const Icon(Icons.hourglass_top_rounded, size: 18),
            label: const Text('Play when Ready'),
          ),
        ],
      ),
    );
  }
}
