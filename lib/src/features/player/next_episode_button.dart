import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../services/acquisition/acquisition.dart';
import '../../theme/theme.dart';
import '../downloads/downloads_providers.dart';

/// The single "Next Episode" control for a TV episode. Shown bottom-right,
/// fading in and out with the player controls, it reflects the following
/// episode's live state and acts immediately when tapped:
///   - already downloaded → **Play Next Episode** (plays it in place)
///   - downloading → progress + **Play Next when Ready** (opens the preparing
///     dialog, which reattaches to the download and plays when buffered)
///   - not fetched yet → **Download Next Episode** (starts a background fetch)
///
/// It watches [downloadForTagProvider] for both the episode's own tag and a
/// season-pack tag (an episode can be served from a whole-season download), so a
/// download started here — or by the halfway-mark prefetch — flips it to the
/// downloading state on the next poll.
class NextEpisodeButton extends ConsumerWidget {
  const NextEpisodeButton({
    super.key,
    required this.showName,
    required this.tmdbId,
    required this.season,
    required this.episode,
    required this.localItem,
    required this.downloadRequested,
    required this.onPlayLocal,
    required this.onPlayWhenReady,
    required this.onDownload,
  });

  final String showName;
  final int tmdbId;
  final int season;
  final int episode;

  /// The next episode's library row when it's already downloaded, else null.
  final LibraryItem? localItem;

  /// Optimistic flag: the user tapped Download and the daemon hasn't reported
  /// the new task yet — bridges the gap to the first live poll.
  final bool downloadRequested;

  final void Function(LibraryItem) onPlayLocal;
  final VoidCallback onPlayWhenReady;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = localItem;

    // 1) Already in the library → play it straight away.
    if (local != null) {
      return _NextEpisodePill(
        icon: Icons.skip_next_rounded,
        label: 'Play Next Episode',
        onPressed: () => onPlayLocal(local),
      );
    }

    // 2) Downloading (its own torrent, or a season pack that contains it) →
    //    show progress and drop into the preparing dialog when tapped.
    final epTag = acquisitionTag(acquisitionDedupeKey(
        tmdbId: tmdbId, title: showName, season: season, episode: episode));
    final seasonTag = acquisitionTag(
        acquisitionDedupeKey(tmdbId: tmdbId, title: showName, season: season));
    final status = ref.watch(downloadForTagProvider(epTag)) ??
        ref.watch(downloadForTagProvider(seasonTag));
    if (status != null) {
      // Finished downloading but not yet imported into the library — it's ready
      // to play, so drop the progress bar and read like the local case.
      if (status.isComplete) {
        return _NextEpisodePill(
          icon: Icons.skip_next_rounded,
          label: 'Play Next Episode',
          onPressed: onPlayWhenReady,
        );
      }
      final pct = (status.progress * 100).round();
      return _NextEpisodePill(
        icon: Icons.hourglass_top_rounded,
        label: 'Play Next when Ready · $pct%',
        progress: status.progress,
        onPressed: onPlayWhenReady,
      );
    }

    // Optimistic: the user just tapped Download but the daemon hasn't reported
    // the task yet — show an indeterminate "Starting…" until it does.
    if (downloadRequested) {
      return const _NextEpisodePill(
        icon: Icons.hourglass_top_rounded,
        label: 'Starting…',
        indeterminate: true,
        onPressed: null,
      );
    }

    // 3) Not fetched yet → start a background download.
    return _NextEpisodePill(
      icon: Icons.download_rounded,
      label: 'Download Next Episode',
      onPressed: onDownload,
    );
  }
}

/// One visual state of [NextEpisodeButton]: a filled action button with an
/// optional thin progress bar underneath (determinate for a live percentage,
/// indeterminate for the brief "Starting…" gap).
class _NextEpisodePill extends StatelessWidget {
  const _NextEpisodePill({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.progress,
    this.indeterminate = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double? progress;
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    final showBar = progress != null || indeterminate;
    final action = FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          action,
          if (showBar)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: ClipRRect(
                borderRadius: AppRadii.rSm,
                child: LinearProgressIndicator(
                  value: indeterminate ? null : progress,
                  minHeight: 4,
                  backgroundColor: AppColors.glassFill,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.secondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
