import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/open_url.dart';
import '../../data/tmdb/tmdb_video.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import 'discover_providers.dart';

/// Open the glass trailer picker for a title, then hand the chosen video to the
/// **browser**. A title with several previews (official trailer, teaser,
/// per-season trailers, clips) lists them all so the user can pick — see
/// [trailerOptionsProvider].
///
/// Why the browser and not our own player: playing a YouTube URL in libmpv means
/// resolving it with yt-dlp first, and that resolution is a moving target.
/// YouTube binds each playback URL to the client that extracted it, the source
/// IP and an expiry; it rotates which client yt-dlp may use; and it has largely
/// stopped serving the pre-muxed progressive formats a single-file fetch needs
/// (the failure that finally settled this was `Requested format is not
/// available`). Each fix held for a while and then broke again on YouTube's
/// schedule. A browser is the one client YouTube always intends to serve, so
/// trailers stop being a maintenance burden. Local playback is unaffected —
/// this only changes where *previews* play.
Future<void> showTrailerPicker(
  BuildContext context, {
  required int tmdbId,
  required bool isTv,
}) async {
  final selected = await showDialog<TrailerOption>(
    context: context,
    builder: (_) => _TrailerPickerDialog(tmdbId: tmdbId, isTv: isTv),
  );
  if (selected == null || !context.mounted) return;

  // Capture before the await — the dialog's context may be gone after it.
  final messenger = ScaffoldMessenger.of(context);
  if (!await openUrl(youtubeWatchUrl(selected.video.key))) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open the trailer in a browser.")),
    );
  }
}

/// The video's own name, or a sensible fallback from its type when TMDB left it
/// blank (e.g. "Trailer").
String trailerDisplayName(TrailerOption option) {
  final name = option.video.name.trim();
  if (name.isNotEmpty) return name;
  final type = option.video.type.trim();
  return type.isEmpty ? 'Video' : type;
}

class _TrailerPickerDialog extends ConsumerWidget {
  const _TrailerPickerDialog({required this.tmdbId, required this.isTv});

  final int tmdbId;
  final bool isTv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(trailerOptionsProvider((tmdbId, isTv)));
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: GlassSurface(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Videos', style: text.titleLarge)),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: async.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const _Message(
                    'Could not load videos — see the error log.',
                  ),
                  data: (groups) => groups.isEmpty
                      ? const _Message('No previews available for this title.')
                      : _GroupList(groups: groups),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.groups});
  final List<TrailerGroup> groups;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Flatten groups into a single scrollable so D-pad focus flows top-to-bottom
    // and focus-follows-scroll (FocusableCard) keeps the selection in view. The
    // very first row autofocuses so the remote lands somewhere actionable.
    final children = <Widget>[];
    var isFirst = true;
    for (final group in groups) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.xs),
        child: Text(
          group.title.toUpperCase(),
          style: text.labelMedium?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
      ));
      for (final option in group.options) {
        children.add(_OptionRow(option: option, autofocus: isFirst));
        isFirst = false;
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: children,
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option, required this.autofocus});
  final TrailerOption option;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = <String>[
      if (option.video.official) 'Official',
      if (option.seasonNumber != null) 'Season ${option.seasonNumber}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: FocusableCard(
        autofocus: autofocus,
        onPressed: () => Navigator.of(context).pop(option),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline_rounded,
                  color: AppColors.primaryBright),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trailerDisplayName(option),
                      style: text.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: text.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
