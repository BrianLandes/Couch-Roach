import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../data/db/database.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../player/player_screen.dart';

/// Lists the episodes of an unmatched show group (folder) so each can be played.
/// Used when a pile of episodes couldn't be matched to TMDB but clearly belong
/// together — the grid shows one tile, and this is what it opens.
Future<void> showUnmatchedShowSheet(
  BuildContext context,
  String name,
  List<LibraryItem> items,
) {
  final sorted = [...items]..sort((a, b) {
      final sa = a.season ?? 0, sb = b.season ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      final ea = a.episode ?? 0, eb = b.episode ?? 0;
      if (ea != eb) return ea.compareTo(eb);
      return a.filePath.compareTo(b.filePath);
    });

  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: GlassSurface(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Not matched to a show yet — here's what's in this folder.",
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _EpisodeRow(
                    item: sorted[i],
                    autofocus: i == 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.item, this.autofocus = false});
  final LibraryItem item;
  final bool autofocus;

  String get _label {
    final s = item.season, e = item.episode;
    if (s != null && e != null) {
      return 'S${s.toString().padLeft(2, '0')} · E${e.toString().padLeft(2, '0')}';
    }
    return p.basenameWithoutExtension(item.filePath);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FocusableCard(
      autofocus: autofocus,
      borderRadius: AppRadii.rMd,
      onPressed: () => context.push(
        Routes.player,
        extra: PlayerArgs(
          filePath: item.filePath,
          title: item.tmdbName ?? item.title,
          libraryItemId: item.id,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.play_arrow_rounded, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(_label,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
