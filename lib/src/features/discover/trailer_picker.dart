import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/tmdb/tmdb_video.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../player/player_screen.dart';
import 'discover_providers.dart';

/// Open the glass trailer picker for a title. The dialog returns the chosen
/// [TrailerOption]; we then push the player with its YouTube URL. A title with
/// several previews (official trailer, teaser, per-season trailers, clips) lists
/// them all so the user can pick — see [trailerOptionsProvider].
Future<void> showTrailerPicker(
  BuildContext context, {
  required int tmdbId,
  required bool isTv,
  required String title,
}) async {
  final selected = await showDialog<TrailerOption>(
    context: context,
    builder: (_) => _TrailerPickerDialog(tmdbId: tmdbId, isTv: isTv),
  );
  if (selected == null || !context.mounted) return;

  final name = trailerDisplayName(selected);
  context.push(
    Routes.player,
    extra: PlayerArgs(
      filePath: youtubeWatchUrl(selected.video.key),
      title: '$title — $name',
    ),
  );
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
