import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../services/acquisition/archive_browse_service.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/search_field.dart';
import '../archive/archive_poster_card.dart';
import '../discover/discover_nav.dart';
import '../discover/discover_poster_card.dart';
import '../discover/discover_providers.dart';
import '../discover/discover_tile.dart';
import 'search_providers.dart';

/// Internet Archive search results, shown as poster tiles like the landing page.
/// The search field stays at the top so the query can be refined; selecting a
/// result runs the IA download-and-watch flow.
class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key, required this.query});
  final String query;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late String _query = widget.query;

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider(_query));
    // TMDB matches are supplementary — they surface above the IA grid as they
    // arrive, without gating the (IA-driven) loading state below.
    final tmdbTiles =
        ref.watch(tmdbSearchProvider(_query)).asData?.value ?? const [];

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    const AppBackButton(),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SearchField(
                        initialText: _query,
                        // Opened with no query → focus so the user can just type.
                        autofocus: widget.query.isEmpty,
                        onSubmitted: (q) => setState(() => _query = q),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: resultsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const _Centered(
                    'Search error — see the error log.',
                    color: AppColors.danger,
                  ),
                  data: (results) => _body(tmdbTiles, results),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<DiscoverTile> tmdbTiles, List<ArchiveItem> ia) {
    if (_query.trim().isEmpty) {
      return const _Centered(
        'Type a movie or show title to search.',
        color: AppColors.textSecondary,
      );
    }

    return CustomScrollView(
      slivers: [
        // TMDB matches (TV + movies) as a horizontal rail up top.
        if (tmdbTiles.isNotEmpty) ...[
          const _SliverSectionLabel('From TMDB'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding),
                itemCount: tmdbTiles.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.lg),
                itemBuilder: (context, i) => DiscoverPosterCard(
                  tile: tmdbTiles[i],
                  onPressed: () => openDiscoverTile(context, tmdbTiles[i]),
                ),
              ),
            ),
          ),
        ],

        // Internet Archive results as the main grid.
        const _SliverSectionLabel('On the Internet Archive'),
        if (ia.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Text(
                'No public-domain results on the Internet Archive for “$_query”.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              AppSpacing.screenPadding,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: AppSpacing.lg,
                mainAxisSpacing: AppSpacing.lg,
              ),
              itemCount: ia.length,
              itemBuilder: (context, i) => ArchivePosterCard(
                item: ia[i],
                // Open the profile page first; pushing keeps this search screen
                // (cached results + scroll) mounted underneath for the back trip.
                onPressed: () =>
                    context.push(Routes.archiveDetail, extra: ia[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _SliverSectionLabel extends StatelessWidget {
  const _SliverSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding, AppSpacing.md, AppSpacing.screenPadding, 0),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textTertiary, letterSpacing: 1.5),
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 16)),
      ),
    );
  }
}
