import 'package:couch_roach/src/features/archive/archive_detail_screen.dart';
import 'package:couch_roach/src/features/archive/archive_providers.dart';
import 'package:couch_roach/src/features/search/search_providers.dart';
import 'package:couch_roach/src/features/search/search_results_screen.dart';
import 'package:couch_roach/src/router/app_router.dart';
import 'package:couch_roach/src/services/acquisition/archive_browse_service.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('search result opens the profile page; back keeps the results',
      (tester) async {
    const item = ArchiveItem(identifier: 'batman43', title: 'Batman 1943');
    const detail = ArchiveDetail(
        identifier: 'batman43', title: 'Batman', description: 'A serial.');

    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const SearchResultsScreen(query: 'batman')),
      GoRoute(
        path: Routes.archiveDetail,
        builder: (_, s) => ArchiveDetailScreen(item: s.extra as ArchiveItem),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchResultsProvider('batman')
            .overrideWith((ref) => Future.value(const [item])),
        archiveDetailProvider('batman43')
            .overrideWith((ref) => Future.value(detail)),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // On the results grid.
    expect(find.text('Batman 1943'), findsOneWidget);
    expect(find.text('Play'), findsNothing);

    // Tap the tile → the IA profile page.
    await tester.tap(find.text('Batman 1943'));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);

    // Back → the search results are still there (state preserved under the push).
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Batman 1943'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
  });
}
