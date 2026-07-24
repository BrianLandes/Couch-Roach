import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/error_log_service.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../../injection.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/poster_art.dart';
import 'discover_tile.dart';

/// A portrait poster card for a discovery item (trending / recommendations /
/// search), for either a TV show or a movie. A long-press / right-click opens a
/// quick "Not interested" action that hides the title from the landing rails.
class DiscoverPosterCard extends ConsumerWidget {
  const DiscoverPosterCard({
    super.key,
    required this.tile,
    this.onPressed,
    this.autofocus = false,
  });

  final DiscoverTile tile;
  final VoidCallback? onPressed;
  final bool autofocus;

  Future<void> _showContextMenu(BuildContext context, WidgetRef ref) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final card = context.findRenderObject() as RenderBox?;
    if (overlay == null || card == null) return;
    final topLeft = card.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + card.size.height / 2,
      overlay.size.width - topLeft.dx - card.size.width,
      0,
    );
    final messenger = ScaffoldMessenger.of(context);
    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: 'not_interested',
          child: ListTile(
            leading: Icon(Icons.not_interested_rounded),
            title: Text('Not interested'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (selected != 'not_interested') return;
    try {
      await getIt<SavedTitlesRepository>().setNotInterested(
        tmdbId: tile.tmdbId,
        mediaType: tile.mediaType,
        name: tile.title,
        posterPath: tile.posterPath,
        value: true,
      );
      messenger.showSnackBar(
        SnackBar(content: Text("Hidden '${tile.title}' from your rows")),
      );
    } catch (e, st) {
      getIt<ErrorLogService>().logError(e,
          stackTrace: st, source: 'DiscoverPosterCard.notInterested');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't hide this title")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 150,
      child: FocusableCard(
        onPressed: onPressed,
        onContextAction: () => _showContextMenu(context, ref),
        autofocus: autofocus,
        child: ClipRRect(
          borderRadius: AppRadii.rLg,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterArt(posterPath: tile.posterPath, seed: tile.title),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC05060A)],
                      stops: [0.5, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      tile.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge,
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
}
