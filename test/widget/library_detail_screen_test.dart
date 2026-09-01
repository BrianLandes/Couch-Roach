import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/saved_titles_repository.dart';
import 'package:couch_roach/src/data/tmdb/tv_show_details.dart';
import 'package:couch_roach/src/features/discover/discover_providers.dart';
import 'package:couch_roach/src/features/discover/discover_tile.dart';
import 'package:couch_roach/src/features/library/library_detail_screen.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:couch_roach/src/router/app_router.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A DiscoveryClient that answers "nothing" to everything, so the TMDB-enrichment
/// providers this screen watches resolve immediately instead of hanging on an
/// unregistered dependency. Tests that care about the enriched content override
/// the provider directly.
class _StubDiscovery implements DiscoveryClient {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// Records `setKeep` so the Keep button's write can be asserted without a real
/// database. drift's query streams never complete inside `testWidgets`' fake
/// async zone, so this widget test uses fakes throughout and leaves the real
/// schema to the repository tests in `test/unit/`.
class _FakeLibraryRepo implements LibraryRepository {
  final keepWrites = <(int, bool)>[];

  @override
  Future<void> setKeep(int id, bool keep) async => keepWrites.add((id, keep));

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// Reports every title as unsaved, so the Favorite / Want-to-watch toggles
/// render in their default state.
class _FakeSavedTitlesRepo implements SavedTitlesRepository {
  @override
  Stream<SavedTitle?> watchTitle(
          {required int tmdbId, required String mediaType}) =>
      Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// A library row as the scanner would have written it. Only the columns this
/// screen reads are interesting; the rest take their table defaults.
LibraryItem _item({
  int id = 1,
  String filePath = r'C:\media\movies\Inception.mkv',
  String title = 'Inception',
  String mediaType = 'movie',
  int? season,
  int? episode,
  int? tmdbId,
  String? tmdbName,
  String? tmdbPosterPath,
  bool keep = false,
  bool missing = false,
  String? container,
  String? videoCodec,
  bool hasEmbeddedEnSub = false,
}) =>
    LibraryItem(
      id: id,
      filePath: filePath,
      title: title,
      mediaType: mediaType,
      season: season,
      episode: episode,
      tmdbId: tmdbId,
      tmdbName: tmdbName,
      tmdbPosterPath: tmdbPosterPath,
      keep: keep,
      missing: missing,
      container: container,
      videoCodec: videoCodec,
      hasEmbeddedEnSub: hasEmbeddedEnSub,
      addedAt: DateTime(2026),
      subtitleOffsetMs: 0,
      managed: true,
    );

void main() {
  late _FakeLibraryRepo library;

  setUp(() async {
    library = _FakeLibraryRepo();
    await getIt.reset();
    getIt
      ..registerLazySingleton<LibraryRepository>(() => library)
      ..registerLazySingleton<SavedTitlesRepository>(_FakeSavedTitlesRepo.new)
      ..registerLazySingleton<DiscoveryClient>(_StubDiscovery.new);
  });

  tearDown(() async => getIt.reset());

  Future<void> pump(
    WidgetTester tester,
    LibraryItem item, {
    List<Override> overrides = const [],
  }) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => LibraryDetailScreen(item: item)),
      GoRoute(
          path: Routes.showDetail,
          builder: (_, __) => const Scaffold(body: Text('SHOW PAGE'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    // Bounded pumps rather than pumpAndSettle: the glass surfaces run
    // continuous decorative animations, so the tree never reaches a settled
    // frame. A few pumps is enough for the providers to resolve and paint.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('hero', () {
    testWidgets('an unmatched movie shows its filename-derived title',
        (tester) async {
      await pump(tester, _item());
      // Twice: the scaffold header and the hero block.
      expect(find.text('Inception'), findsNWidgets(2));
      expect(find.text('Movie'), findsOneWidget);
    });

    testWidgets('the TMDB name wins over the scanned title', (tester) async {
      await pump(tester,
          _item(title: 'inception.2010.1080p', tmdbId: 27205, tmdbName: 'Inception'));
      expect(find.text('Inception'), findsWidgets);
      expect(find.text('inception.2010.1080p'), findsNothing);
    });

    testWidgets('an episode is badged with its season and episode',
        (tester) async {
      await pump(tester,
          _item(title: 'The Show', mediaType: 'tv', season: 2, episode: 5));
      expect(find.text('Season 2 · Episode 5'), findsOneWidget);
      expect(find.text('Movie'), findsNothing);
    });

    testWidgets('technical details are joined, and omitted when unknown',
        (tester) async {
      await pump(
          tester,
          _item(
              container: 'mkv', videoCodec: 'h264', hasEmbeddedEnSub: true));
      expect(find.text('MKV  ·  h264  ·  Subtitles'), findsOneWidget);
    });

    testWidgets('no technical details renders no tech line', (tester) async {
      await pump(tester, _item());
      expect(find.textContaining('·  Subtitles'), findsNothing);
    });
  });

  group('actions', () {
    testWidgets('a present file offers Play, Keep and Delete', (tester) async {
      await pump(tester, _item());
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a kept title reads "Kept" and explains why', (tester) async {
      await pump(tester, _item(keep: true));
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('Keep'), findsNothing);
      expect(find.textContaining('exempt from auto-cleanup'), findsOneWidget);
    });

    testWidgets('tapping Keep flips the badge and persists it', (tester) async {
      await pump(tester, _item(id: 7));
      await tester.tap(find.text('Keep'));
      await tester.pump();

      // Optimistic in the UI, and written through to the repository.
      expect(find.text('Kept'), findsOneWidget);
      expect(library.keepWrites, [(7, true)]);
    });

    testWidgets('tapping Kept again un-pins it', (tester) async {
      await pump(tester, _item(id: 7, keep: true));
      await tester.tap(find.text('Kept'));
      await tester.pump();

      expect(find.text('Keep'), findsOneWidget);
      expect(library.keepWrites, [(7, false)]);
    });

    // A missing file has nothing to play — offering Play would only produce an
    // mpv error, so the whole action row is replaced by an explanation.
    testWidgets('a missing file offers only "Remove from library"',
        (tester) async {
      await pump(tester, _item(missing: true));
      expect(find.text('Play'), findsNothing);
      expect(find.text('Keep'), findsNothing);
      expect(find.text('Remove from library'), findsOneWidget);
      expect(find.textContaining("isn't on disk right now"), findsOneWidget);
    });

    testWidgets('a missing file suppresses the kept note too', (tester) async {
      await pump(tester, _item(keep: true, missing: true));
      expect(find.textContaining('exempt from auto-cleanup'), findsNothing);
    });

    // A matched episode links out to the show page; a movie has nowhere to go.
    testWidgets('a matched episode links to the full show', (tester) async {
      await pump(
          tester,
          _item(
              mediaType: 'tv',
              season: 1,
              episode: 1,
              tmdbId: 4242,
              tmdbName: 'The Show'),
          overrides: [
            tvDetailsProvider(4242).overrideWith((ref) => Future.value(null)),
            trailerUrlProvider((4242, true))
                .overrideWith((ref) => Future.value(null)),
          ]);
      expect(find.text('View full show'), findsOneWidget);
    });

    testWidgets('an unmatched episode has no show link', (tester) async {
      await pump(tester, _item(mediaType: 'tv', season: 1, episode: 1));
      expect(find.text('View full show'), findsNothing);
    });

    testWidgets('a matched movie has no show link', (tester) async {
      await pump(tester, _item(tmdbId: 27205, tmdbName: 'Inception'),
          overrides: [
            movieTileProvider(27205).overrideWith((ref) => Future.value(null)),
            trailerUrlProvider((27205, false))
                .overrideWith((ref) => Future.value(null)),
          ]);
      expect(find.text('View full show'), findsNothing);
    });

    testWidgets('a trailer is offered only when one resolves', (tester) async {
      await pump(tester, _item(tmdbId: 27205, tmdbName: 'Inception'),
          overrides: [
            movieTileProvider(27205).overrideWith((ref) => Future.value(null)),
            trailerUrlProvider((27205, false))
                .overrideWith((ref) => Future.value('https://youtu.be/abc')),
          ]);
      expect(find.text('Trailers'), findsOneWidget);
    });

    testWidgets('no trailer, no Trailers button', (tester) async {
      await pump(tester, _item(tmdbId: 27205, tmdbName: 'Inception'),
          overrides: [
            movieTileProvider(27205).overrideWith((ref) => Future.value(null)),
            trailerUrlProvider((27205, false))
                .overrideWith((ref) => Future.value(null)),
          ]);
      expect(find.text('Trailers'), findsNothing);
    });

    // Without this the movie is stranded on its owned-title page with no way to
    // favorite or shortlist it — a matched TV item gets those on the show page.
    testWidgets('a matched movie carries the Favorite / Want-to-watch toggles',
        (tester) async {
      await pump(tester, _item(tmdbId: 27205, tmdbName: 'Inception'),
          overrides: [
            movieTileProvider(27205).overrideWith((ref) => Future.value(null)),
            trailerUrlProvider((27205, false))
                .overrideWith((ref) => Future.value(null)),
          ]);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('an unmatched movie has no save toggles', (tester) async {
      await pump(tester, _item());
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    });
  });

  group('TMDB enrichment', () {
    testWidgets('a matched movie shows its overview, year and rating',
        (tester) async {
      await pump(tester, _item(tmdbId: 27205, tmdbName: 'Inception'),
          overrides: [
            movieTileProvider(27205).overrideWith((ref) => Future.value(
                  const DiscoverTile(
                    tmdbId: 27205,
                    title: 'Inception',
                    mediaType: 'movie',
                    overview: 'A thief who steals corporate secrets.',
                    year: 2010,
                    voteAverage: 8.4,
                  ),
                )),
            trailerUrlProvider((27205, false))
                .overrideWith((ref) => Future.value(null)),
          ]);

      expect(find.text('A thief who steals corporate secrets.'), findsOneWidget);
      expect(find.text('2010  ·  ★ 8.4'), findsOneWidget);
    });

    testWidgets('a matched show reads its year off the first air date',
        (tester) async {
      await pump(
          tester,
          _item(
              mediaType: 'tv',
              season: 1,
              episode: 1,
              tmdbId: 4242,
              tmdbName: 'The Show'),
          overrides: [
            tvDetailsProvider(4242).overrideWith((ref) => Future.value(
                  TvShowDetails(
                    tmdbId: 4242,
                    name: 'The Show',
                    overview: 'Some people do some things.',
                    firstAirDate: '2008-03-21',
                    voteAverage: 7.5,
                    seasons: [],
                  ),
                )),
            trailerUrlProvider((4242, true))
                .overrideWith((ref) => Future.value(null)),
          ]);

      expect(find.text('Some people do some things.'), findsOneWidget);
      expect(find.text('2008  ·  ★ 7.5'), findsOneWidget);
    });

    // The row itself only cached id/name/poster, so an unmatched title has no
    // profile to show and must render without one rather than blocking.
    testWidgets('an unmatched title renders with no overview or rating',
        (tester) async {
      await pump(tester, _item());
      expect(find.textContaining('★'), findsNothing);
    });

    testWidgets('a zero rating is omitted rather than shown as ★ 0.0',
        (tester) async {
      await pump(tester, _item(tmdbId: 27205, tmdbName: 'Inception'),
          overrides: [
            movieTileProvider(27205).overrideWith((ref) => Future.value(
                  const DiscoverTile(
                    tmdbId: 27205,
                    title: 'Inception',
                    mediaType: 'movie',
                    year: 2010,
                    voteAverage: 0,
                  ),
                )),
            trailerUrlProvider((27205, false))
                .overrideWith((ref) => Future.value(null)),
          ]);

      expect(find.text('2010'), findsOneWidget);
      expect(find.textContaining('★'), findsNothing);
    });
  });
}
