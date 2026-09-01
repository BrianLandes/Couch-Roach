import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/watch_history_repository.dart';
import 'package:couch_roach/src/features/library/library_providers.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:couch_roach/src/features/discover/resume_button.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
  });
  tearDown(() async => db.close());

  Future<LibraryItem> episode() async {
    await repo.upsert(const ScannedFile(
      filePath: '/tv/show.s01e03.mkv',
      title: 'Show',
      mediaType: 'tv',
      season: 1,
      episode: 3,
      tmdbId: 42,
      tmdbName: 'Show',
    ));
    return (await repo.findByPath('/tv/show.s01e03.mkv'))!;
  }

  Widget host(Widget child, List<ContinueWatchingEntry> entries) => ProviderScope(
        overrides: [
          continueWatchingProvider.overrideWith((ref) => Stream.value(entries)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('shows a labelled Resume button for a matching show', (t) async {
    final item = await episode();
    final entry = ContinueWatchingEntry(
        item: item, resumePositionSec: 120, durationSec: 1400);

    await t.pumpWidget(host(const ResumeButton(tmdbId: 42), [entry]));
    await t.pump(); // let the overridden stream deliver

    expect(find.text('Resume S01E03'), findsOneWidget);
  });

  testWidgets('renders nothing when the show has nothing in progress',
      (t) async {
    final item = await episode();
    final entry = ContinueWatchingEntry(
        item: item, resumePositionSec: 120, durationSec: 1400);

    // A different show's tmdbId → no match.
    await t.pumpWidget(host(const ResumeButton(tmdbId: 999), [entry]));
    await t.pump();

    expect(find.textContaining('Resume'), findsNothing);
  });

  testWidgets('matches a single title by libraryItemId', (t) async {
    await repo.upsert(const ScannedFile(
        filePath: '/m/dune.mkv', title: 'Dune', mediaType: 'movie'));
    final movie = (await repo.findByPath('/m/dune.mkv'))!;
    final entry = ContinueWatchingEntry(
        item: movie, resumePositionSec: 300, durationSec: 7200);

    await t.pumpWidget(host(ResumeButton(libraryItemId: movie.id), [entry]));
    await t.pump();

    expect(find.text('Resume'), findsOneWidget);
  });
}
