import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../services/acquisition/archive_browse_service.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/search_field.dart';
import '../archive/archive_poster_card.dart';
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
                  data: (results) => _results(results),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(List<ArchiveItem> results) {
    if (_query.trim().isEmpty) {
      return const _Centered(
        'Type a movie or show title to search the Internet Archive.',
        color: AppColors.textSecondary,
      );
    }
    if (results.isEmpty) {
      return _Centered('No results on the Internet Archive for “$_query”.',
          color: AppColors.textSecondary);
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: AppSpacing.lg,
        mainAxisSpacing: AppSpacing.lg,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) => ArchivePosterCard(
        item: results[i],
        autofocus: i == 0,
        // Open the profile page first; pushing keeps this search screen (and its
        // cached results + scroll position) mounted underneath for the back trip.
        onPressed: () => context.push(Routes.archiveDetail, extra: results[i]),
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
