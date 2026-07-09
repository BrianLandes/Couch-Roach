import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/settings_providers.dart';
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

/// Search results as poster tiles. TMDB matches (shows/movies) fill a grid; when
/// the opt-in Internet Archive source is enabled, its public-domain results show
/// below as their own grid. The search field stays pinned so the query can be
/// refined.
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
    // Internet Archive is opt-in (default off). When on, IA is the primary grid
    // and TMDB matches surface above it as they arrive; when off, the page is
    // TMDB-only and its loading state drives the spinner.
    final iaEnabled = ref.watch(internetArchiveEnabledProvider);
    final tmdbAsync = ref.watch(tmdbSearchProvider(_query));
    final tmdbTiles = tmdbAsync.asData?.value ?? const <DiscoverTile>[];

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
                child: iaEnabled
                    ? ref.watch(searchResultsProvider(_query)).when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, __) => const _Centered(
                            'Search error — see the error log.',
                            color: AppColors.danger,
                          ),
                          data: (results) =>
                              _body(tmdbTiles, results, iaEnabled: true),
                        )
                    : tmdbAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => const _Centered(
                          'Search error — see the error log.',
                          color: AppColors.danger,
                        ),
                        data: (tiles) =>
                            _body(tiles, const [], iaEnabled: false),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    List<DiscoverTile> tmdbTiles,
    List<ArchiveItem> ia, {
    required bool iaEnabled,
  }) {
    if (_query.trim().isEmpty) {
      return const _Centered(
        'Type a movie or show title to search.',
        color: AppColors.textSecondary,
      );
    }

    // TMDB-only (Internet Archive off) with no matches → a plain empty state.
    if (!iaEnabled && tmdbTiles.isEmpty) {
      return _Centered(
        'No results for “$_query”.',
        color: AppColors.textSecondary,
      );
    }

    return CustomScrollView(
      slivers: [
        // TMDB matches (TV + movies) as a grid that wraps to fill the width,
        // rather than a horizontal rail that runs off the side of the screen.
        if (tmdbTiles.isNotEmpty) ...[
          const _SliverSectionLabel('From TMDB'),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              AppSpacing.sm,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: AppSpacing.lg,
                mainAxisSpacing: AppSpacing.lg,
              ),
              itemCount: tmdbTiles.length,
              itemBuilder: (context, i) => DiscoverPosterCard(
                tile: tmdbTiles[i],
                onPressed: () => openDiscoverTile(context, tmdbTiles[i]),
              ),
            ),
          ),
        ],

        // Internet Archive results as the main grid — only when IA is enabled.
        if (iaEnabled) ...[
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
                  // Open the profile page first; pushing keeps this search
                  // screen (cached results + scroll) mounted underneath for the
                  // back trip.
                  onPressed: () =>
                      context.push(Routes.archiveDetail, extra: ia[i]),
                ),
              ),
            ),
        ],
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
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding,
            AppSpacing.md, AppSpacing.screenPadding, 0),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: AppColors.textTertiary, letterSpacing: 1.5),
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
