import 'package:couch_roach/src/features/archive/archive_detail_screen.dart';
import 'package:couch_roach/src/features/archive/archive_providers.dart';
import 'package:couch_roach/src/services/acquisition/archive_browse_service.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renders IA detail: title, description, files, and Play',
      (tester) async {
    const item = ArchiveItem(identifier: 'notld', title: 'NOTLD', year: 1968);
    const detail = ArchiveDetail(
      identifier: 'notld',
      title: 'Night of the Living Dead',
      year: 1968,
      description: 'A group is trapped by the undead.',
      videos: [
        ArchiveVideoFile(name: 'feature.mp4', sizeBytes: 600000000),
        ArchiveVideoFile(name: 'alt.ogv', sizeBytes: 400000000),
      ],
    );

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ArchiveDetailScreen(item: item)),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        archiveDetailProvider('notld')
            .overrideWith((ref) => Future.value(detail)),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Night of the Living Dead'), findsOneWidget);
    expect(find.text('A group is trapped by the undead.'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('2 videos'), findsOneWidget);
    expect(find.text('feature.mp4'), findsOneWidget);
  });
}
