import 'package:couch_roach/src/features/downloads/downloads_providers.dart';
import 'package:couch_roach/src/features/downloads/downloads_screen.dart';
import 'package:couch_roach/src/features/downloads/manage_download.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/transcode/downscale_service.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The screen watches the downscaler's current job directly (it's a
/// ValueListenable, not a provider), so the container has to hold one. This fake
/// lets a test drive that job without an ffmpeg process.
class _FakeDownscaleService implements DownscaleService {
  final _job = ValueNotifier<DownscaleJob?>(null);

  @override
  ValueListenable<DownscaleJob?> get current => _job;

  set job(DownscaleJob? value) => _job.value = value;

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

// ignore: library_private_types_in_public_api
late _FakeDownscaleService downscaler;

Widget _app(List<TorrentStatus> torrents, {bool alive = true}) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => const DownloadsScreen())],
  );
  return ProviderScope(
    overrides: [
      downloadsProvider.overrideWith((ref) => Stream.value(torrents)),
      daemonAliveProvider.overrideWith((ref) => Stream.value(alive)),
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
  setUp(() async {
    await getIt.reset();
    downscaler = _FakeDownscaleService();
    getIt.registerLazySingleton<DownscaleService>(() => downscaler);
  });

  tearDown(() async => getIt.reset());

  testWidgets('shows the idle empty state when the client is online',
      (tester) async {
    await tester.pumpWidget(_app(const [], alive: true));
    await tester.pumpAndSettle();

    expect(find.text('Nothing downloading'), findsOneWidget);
    expect(find.text('Client online'), findsOneWidget);
  });

  testWidgets('shows an offline state + chip when the client is unreachable',
      (tester) async {
    await tester.pumpWidget(_app(const [], alive: false));
    await tester.pumpAndSettle();

    expect(find.text('Torrent client offline'), findsOneWidget);
    expect(find.text('Client offline'), findsOneWidget);
    expect(find.text('Nothing downloading'), findsNothing);
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

  testWidgets('tapping a download opens the manage sheet', (tester) async {
    await tester.pumpWidget(_app([_torrent(name: 'Popeye')]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Popeye'));
    await tester.pumpAndSettle();

    expect(find.text('Manage download'), findsOneWidget);
    expect(find.text('Remove & delete files from disk'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget); // downloading → stoppable
  });

  test('isPausedState recognizes paused/stopped states', () {
    expect(isPausedState('pausedDL'), isTrue);
    expect(isPausedState('stoppedDL'), isTrue);
    expect(isPausedState('downloading'), isFalse);
    expect(isPausedState('stalledDL'), isFalse);
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

  group('downscale banner', () {
    // Idle is the common path: the banner must take up no room at all, so the
    // screen looks exactly as it did before the downscaler existed.
    testWidgets('is absent while nothing is downscaling', (tester) async {
      await tester.pumpWidget(_app(const []));
      await tester.pump();
      expect(find.textContaining('play smoothly'), findsNothing);
    });

    testWidgets('names the file being downscaled, with its progress',
        (tester) async {
      await tester.pumpWidget(_app(const []));
      await tester.pump();

      downscaler.job =
          (filePath: '/tv/big.mkv', title: 'Sintel', progress: 0.42);
      await tester.pump();

      expect(find.text('Making "Sintel" play smoothly'), findsOneWidget);
      expect(find.textContaining('42%'), findsOneWidget);
    });

    // ffmpeg reports progress only once it gets going; before that there's a
    // job but no percentage, and the banner still has to say something.
    testWidgets('renders without a percentage before ffmpeg reports one',
        (tester) async {
      await tester.pumpWidget(_app(const []));
      await tester.pump();

      downscaler.job =
          (filePath: '/tv/big.mkv', title: 'Sintel', progress: null);
      await tester.pump();

      expect(find.text('Making "Sintel" play smoothly'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('disappears again when the job finishes', (tester) async {
      await tester.pumpWidget(_app(const []));
      downscaler.job =
          (filePath: '/tv/big.mkv', title: 'Sintel', progress: 0.9);
      await tester.pump();
      expect(find.textContaining('play smoothly'), findsOneWidget);

      downscaler.job = null;
      await tester.pump();
      expect(find.textContaining('play smoothly'), findsNothing);
    });

    // The banner is extra activity on a screen that already lists torrents —
    // it must not push the list out of the viewport.
    testWidgets('coexists with a download list without overflowing',
        (tester) async {
      await tester.pumpWidget(_app([_torrent()]));
      downscaler.job =
          (filePath: '/tv/big.mkv', title: 'Sintel', progress: 0.42);
      await tester.pump();

      expect(find.textContaining('play smoothly'), findsOneWidget);
      expect(find.text('Sintel'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
