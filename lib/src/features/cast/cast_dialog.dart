import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/tmdb/credits.dart';
import '../../data/tmdb/tmdb_images.dart';
import '../../core/platform/open_url.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/poster_art.dart';
import '../discover/discover_tile.dart';
import '../discover/show_detail_screen.dart' show ShowDetailArgs;
import 'cast_providers.dart';

/// What the cast panel is about — a specific TV episode, or a movie.
class CastQuery {
  const CastQuery.episode({
    required this.tmdbId,
    required this.season,
    required this.episode,
    this.title,
  });
  const CastQuery.movie({required this.tmdbId, this.title})
      : season = null,
        episode = null;

  final int tmdbId;
  final int? season;
  final int? episode;
  final String? title;

  bool get isEpisode => season != null && episode != null;
}

/// Open the "Who's in this?" panel over the player.
Future<void> showCastDialog(BuildContext context, CastQuery query) =>
    showDialog<void>(context: context, builder: (_) => CastDialog(query: query));

class CastDialog extends StatefulWidget {
  const CastDialog({super.key, required this.query});
  final CastQuery query;

  @override
  State<CastDialog> createState() => _CastDialogState();
}

class _CastDialogState extends State<CastDialog> {
  ({int id, String name})? _person;

  void _openTitle(PersonCredit c) {
    // Capture the router before popping (the dialog's context unmounts on pop),
    // then open the title's detail page over the player.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (c.mediaType == 'tv') {
      router.push(Routes.showDetail,
          extra: ShowDetailArgs(tmdbId: c.tmdbId, name: c.displayTitle));
    } else {
      router.push(Routes.movieDetail,
          extra: DiscoverTile(
            tmdbId: c.tmdbId,
            title: c.displayTitle,
            mediaType: 'movie',
            posterPath: c.posterPath,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _person;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: GlassSurface(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: person == null
              ? _CastListView(
                  query: widget.query,
                  onPick: (id, name) => setState(() => _person = (id: id, name: name)),
                )
              : _PersonView(
                  personId: person.id,
                  name: person.name,
                  excludeTmdbId: widget.query.tmdbId,
                  onBack: () => setState(() => _person = null),
                  onOpenTitle: _openTitle,
                ),
        ),
      ),
    );
  }
}

class _CastListView extends ConsumerWidget {
  const _CastListView({required this.query, required this.onPick});
  final CastQuery query;
  final void Function(int id, String name) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = query.isEpisode
        ? ref.watch(episodeCastProvider((
            tmdbId: query.tmdbId,
            season: query.season!,
            episode: query.episode!,
          )))
        : ref.watch(movieCastProvider(query.tmdbId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          title: 'Who’s in this?',
          subtitle: query.title,
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: async.when(
            loading: () => const _Busy(),
            error: (_, __) => const _Notice('Couldn’t load the cast — see the error log.'),
            data: (cast) => cast.isEmpty
                ? const _Notice('No cast is listed for this title.')
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    itemCount: cast.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final m = cast[i];
                      return _CastRow(
                        member: m,
                        autofocus: i == 0,
                        onTap: () => onPick(m.personId, m.name),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.member, required this.onTap, this.autofocus = false});
  final CastMember member;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FocusableCard(
      autofocus: autofocus,
      borderRadius: AppRadii.rMd,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            _Headshot(path: member.profilePath),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (member.character.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('as ${member.character}',
                        style: text.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Headshot extends StatelessWidget {
  const _Headshot({this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final url = TmdbImages.profile(path);
    return ClipRRect(
      borderRadius: AppRadii.rSm,
      child: SizedBox(
        width: 48,
        height: 64,
        child: url == null
            ? const ColoredBox(
                color: AppColors.glassFill,
                child: Icon(Icons.person_rounded, color: AppColors.textTertiary),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 160,
                placeholder: (_, __) => const ColoredBox(color: AppColors.glassFill),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: AppColors.glassFill,
                  child: Icon(Icons.person_rounded, color: AppColors.textTertiary),
                ),
              ),
      ),
    );
  }
}

class _PersonView extends ConsumerWidget {
  const _PersonView({
    required this.personId,
    required this.name,
    required this.excludeTmdbId,
    required this.onBack,
    required this.onOpenTitle,
  });
  final int personId;
  final String name;
  final int excludeTmdbId;
  final VoidCallback onBack;
  final void Function(PersonCredit) onOpenTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(personKnownForProvider(personId));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: name, onClose: () => Navigator.of(context).pop(), onBack: onBack),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: OutlinedButton.icon(
            onPressed: () => openUrl(
                'https://www.google.com/search?q=${Uri.encodeQueryComponent(name)}'),
            icon: const Icon(Icons.travel_explore_rounded),
            label: const Text('Search Google'),
          ),
        ),
        const _SectionLabel('Known for'),
        Flexible(
          child: async.when(
            loading: () => const _Busy(),
            error: (_, __) => const _Notice('Couldn’t load their other titles.'),
            data: (titles) => titles.isEmpty
                ? const _Notice('No other titles found.')
                : GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 120,
                      childAspectRatio: 2 / 3.4,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                    ),
                    itemCount: titles.length,
                    itemBuilder: (context, i) => _KnownForTile(
                      credit: titles[i],
                      onTap: () => onOpenTitle(titles[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _KnownForTile extends StatelessWidget {
  const _KnownForTile({required this.credit, required this.onTap});
  final PersonCredit credit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FocusableCard(
      borderRadius: AppRadii.rMd,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: AppRadii.rSm,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: PosterArt(
                    posterPath: credit.posterPath, seed: credit.displayTitle),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(credit.displayTitle,
              style: text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose, this.subtitle, this.onBack});
  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!,
                    style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textTertiary, letterSpacing: 1.5),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
}
