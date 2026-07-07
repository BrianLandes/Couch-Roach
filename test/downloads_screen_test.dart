import 'package:couch_roach/src/features/downloads/downloads_providers.dart';
import 'package:couch_roach/src/features/downloads/downloads_screen.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(List<TorrentStatus> torrents) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => const DownloadsScreen())],
  );
  return ProviderScope(
    overrides: [
      downloadsProvider.overrideWith((ref) => Stream.value(torrents)),
    ],
    child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
}

TorrentStatus _torrent({
  String name = 'Sintel',
  double progress = 0.42,
  String state = 'downloading',
  int dl = 1048576,
  int? eta = 300,
}) =>
    TorrentStatus(
      hash: 'h',
      name: name,
      progress: progress,
      state: state,
      downloadSpeed: dl,
      sizeBytes: 2000000000,
      downloadedBytes: 840000000,
      etaSeconds: eta,
    );

void main() {
  testWidgets('shows the empty state when nothing is downloading',
      (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();

    expect(find.text('Nothing downloading'), findsOneWidget);
  });

  testWidgets('renders a card with name, state, percent, and ETA',
      (tester) async {
    await tester.pumpWidget(_app([_torrent()]));
    await tester.pumpAndSettle();

    expect(find.text('Sintel'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.textContaining('42%'), findsOneWidget);
    expect(find.textContaining('ETA 5m'), findsOneWidget); // 300s → 5m 0s
    expect(find.text('Nothing downloading'), findsNothing);
  });

  testWidgets('hides speed/ETA for a completed torrent', (tester) async {
    await tester.pumpWidget(_app([
      _torrent(name: 'Done', progress: 1.0, state: 'uploading', eta: null),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.textContaining('ETA'), findsNothing);
  });
}
