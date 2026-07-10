import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/features/downloads/downloads_providers.dart';
import 'package:couch_roach/src/features/player/next_episode_button.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const showName = 'The Show';
  const tmdbId = 100;
  // The button is handed the *next* episode to play (resolved by the player);
  // these are that episode's coordinates.
  const season = 1;
  const episode = 3;

  // A torrent status tagged so it maps back to the tracked next episode.
  TorrentStatus statusFor({required String tag, required double progress}) =>
      TorrentStatus(
        hash: 'h',
        name: 'n',
        progress: progress,
        state: 'downloading',
        downloadSpeed: 0,
        sizeBytes: 0,
        downloadedBytes: 0,
        tags: [tag],
      );

  Widget host(
    Widget child, {
    List<TorrentStatus> torrents = const [],
  }) {
    return ProviderScope(
      overrides: [
        downloadsProvider.overrideWith((ref) => Stream.value(torrents)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  NextEpisodeButton button({
    LibraryItem? localItem,
    bool downloadRequested = false,
  }) {
    return NextEpisodeButton(
      showName: showName,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
      localItem: localItem,
      downloadRequested: downloadRequested,
      onPlayLocal: (_) {},
      onPlayWhenReady: () {},
      onDownload: () {},
    );
  }

  testWidgets('not fetched → "Download Next Episode"', (tester) async {
    await tester.pumpWidget(host(button()));
    await tester.pump();
    expect(find.text('Download Next Episode'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('downloading → progress + "Play Next when Ready"',
      (tester) async {
    // The button's season/episode ARE the next episode it tracks, so tag the
    // torrent with exactly those.
    final nextTag = acquisitionTag(acquisitionDedupeKey(
        tmdbId: tmdbId, title: showName, season: season, episode: episode));
    await tester.pumpWidget(host(
      button(),
      torrents: [statusFor(tag: nextTag, progress: 0.42)],
    ));
    await tester.pump(); // let the overridden stream deliver its value
    await tester.pump();
    expect(find.text('Play Next when Ready · 42%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a season-pack download also counts as downloading',
      (tester) async {
    final seasonTag = acquisitionTag(
        acquisitionDedupeKey(tmdbId: tmdbId, title: showName, season: season));
    await tester.pumpWidget(host(
      button(),
      torrents: [statusFor(tag: seasonTag, progress: 0.10)],
    ));
    await tester.pump(); // let the overridden stream deliver its value
    await tester.pump();
    expect(find.text('Play Next when Ready · 10%'), findsOneWidget);
  });

  testWidgets('just-tapped download shows an indeterminate "Starting…"',
      (tester) async {
    await tester.pumpWidget(host(button(downloadRequested: true)));
    await tester.pump();
    expect(find.text('Starting…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, isNull); // indeterminate
  });

  testWidgets('already downloaded → "Play Next Episode"', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final library = DriftLibraryRepository(db);
    await library.upsert(const ScannedFile(
        filePath: '/tv/s1e4.mkv', title: 'S01E04', mediaType: 'tv'));
    final item = await library.findByPath('/tv/s1e4.mkv');

    await tester.pumpWidget(host(button(localItem: item)));
    await tester.pump();
    expect(find.text('Play Next Episode'), findsOneWidget);
    // A ready-to-play local episode has no progress bar.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('finished download (not yet imported) → "Play Next Episode", '
      'no bar', (tester) async {
    final nextTag = acquisitionTag(acquisitionDedupeKey(
        tmdbId: tmdbId, title: showName, season: season, episode: episode));
    await tester.pumpWidget(host(
      button(),
      torrents: [statusFor(tag: nextTag, progress: 1.0)],
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Play Next Episode'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
