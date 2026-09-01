import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/acquisition_session.dart';
import 'package:couch_roach/src/services/acquisition/jackett_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit coverage for "try another source": the resolver skips already-tried
/// URLs, the tag ↔ dedupe-key mapping round-trips, and the session accumulates
/// tried URLs / request context per title.
void main() {
  const meta = ShowMeta(title: 'The Show', tmdbId: 7);

  TorznabResult ep(String url, {int seeders = 10}) => TorznabResult(
        title: 'The.Show.S01E01.1080p.x264',
        downloadUrl: url,
        sizeBytes: 900 * 1024 * 1024,
        seeders: seeders,
      );

  group('verifiedEpisodeResults excludeUrls', () {
    test('drops sources whose download URL was already tried', () {
      final results = [ep('magnet:A', seeders: 100), ep('magnet:B', seeders: 50)];
      final kept = verifiedEpisodeResults(results, meta, 1, 1,
          excludeUrls: {'magnet:A'});
      expect(kept.map((r) => r.downloadUrl), ['magnet:B']);
    });

    test('empty exclude keeps everything that verifies', () {
      final results = [ep('magnet:A'), ep('magnet:B')];
      expect(verifiedEpisodeResults(results, meta, 1, 1).length, 2);
    });

    test('ranking then exclusion yields the next-best', () {
      final results = [ep('magnet:A', seeders: 100), ep('magnet:B', seeders: 50)];
      // First pick is the highest-seeded A; once A is tried, B is next.
      expect(pickBestTorznabResult(results)!.downloadUrl, 'magnet:A');
      final next = pickBestTorznabResult(
          verifiedEpisodeResults(results, meta, 1, 1, excludeUrls: {'magnet:A'}));
      expect(next!.downloadUrl, 'magnet:B');
    });
  });

  group('seasonPackResults excludeUrls', () {
    TorznabResult pack(String url) => TorznabResult(
        title: 'The.Show.S01.COMPLETE.1080p', downloadUrl: url, seeders: 5);

    test('drops an already-tried pack', () {
      final results = [pack('magnet:P1'), pack('magnet:P2')];
      final kept =
          seasonPackResults(results, meta, 1, excludeUrls: {'magnet:P1'});
      expect(kept.map((r) => r.downloadUrl), ['magnet:P2']);
    });
  });

  group('dedupeKeyFromTag', () {
    test('round-trips an acquisition tag back to its dedupe key', () {
      final key = acquisitionDedupeKey(
          tmdbId: 7, title: 'The Show', season: 1, episode: 1);
      expect(dedupeKeyFromTag(acquisitionTag(key)), key);
    });

    test('returns null for a tag that isn\'t ours', () {
      expect(dedupeKeyFromTag('some-other-tag'), isNull);
    });
  });

  group('parseAcquisitionKey', () {
    test('reads tmdb id, season and episode off an episode key', () {
      final key = acquisitionDedupeKey(
          tmdbId: 7, title: 'The Show', season: 2, episode: 5);
      expect(parseAcquisitionKey(key), (tmdbId: 7, season: 2, episode: 5));
      // The tag wrapping the same key parses identically.
      expect(parseAcquisitionKey(acquisitionTag(key)),
          (tmdbId: 7, season: 2, episode: 5));
    });

    test('a season-pack key has no episode', () {
      final key =
          acquisitionDedupeKey(tmdbId: 42, title: 'The Show', season: 1);
      expect(parseAcquisitionKey(key), (tmdbId: 42, season: 1, episode: null));
    });

    test('a movie / whole-show key has neither season nor episode', () {
      final key = acquisitionDedupeKey(tmdbId: 99, title: 'A Film');
      expect(
          parseAcquisitionKey(key), (tmdbId: 99, season: null, episode: null));
    });

    test('a title-keyed fallback resolves to no id, never a guess', () {
      // No tmdb id → the key embeds the title, which can itself contain the
      // separators the key is built from. Refusing to guess is the point:
      // attributing files to the wrong show would be worse than skipping them.
      final key =
          acquisitionDedupeKey(title: 'Weird-Show-s2', season: 1, episode: 3);
      expect(parseAcquisitionKey(key).tmdbId, isNull);
    });

    test('returns nulls for anything that is not one of our keys', () {
      for (final s in ['', 'some-other-tag', 'cr-tmdb-', 'cr-tmdb-abc']) {
        expect(parseAcquisitionKey(s).tmdbId, isNull, reason: s);
      }
    });
  });

  group('AcquisitionSession', () {
    test('accumulates tried URLs per dedupe key', () {
      final session = AcquisitionSession();
      expect(session.triedFor('k'), isEmpty);
      session.markTried('k', 'magnet:A');
      session.markTried('k', 'magnet:B');
      expect(session.triedFor('k'), {'magnet:A', 'magnet:B'});
      // Isolated per key.
      expect(session.triedFor('other'), isEmpty);
    });

    test('stores and returns request context', () {
      final session = AcquisitionSession();
      expect(session.requestFor('k'), isNull);
      const req = AcquireRequest(
          title: 'The Show — S01E01', meta: meta, season: 1, episode: 1);
      session.recordRequest('k', req);
      expect(session.requestFor('k'), same(req));
    });
  });
}
