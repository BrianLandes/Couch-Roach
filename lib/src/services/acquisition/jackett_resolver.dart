import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:xml/xml.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/settings/settings_service.dart';
import '../subtitles/filename_media_info.dart';
import 'acquisition.dart';

/// [AcquisitionResolver] over a **Jackett** Torznab endpoint (DECISIONS §D).
///
/// CONTENT-AGNOSTIC BY CONSTRUCTION. This queries the aggregate `indexers/all`
/// endpoint — i.e. **whatever indexers the user configured in their own Jackett**.
/// It hardcodes **no** indexers and ships **no** tracker/indexer list; the choice
/// of sources (and the legal responsibility for it) lives entirely in the user's
/// local Jackett instance, not in this repo (CLAUDE.md acquisition invariant).
///
/// The Jackett base URL + auto-generated API key come from the sidecar at
/// runtime via [configure]; until it's up and configured, [resolve] returns null
/// (acquisition simply degrades — the play flow can fall back or surface it).
@LazySingleton()
class JackettResolver implements AcquisitionResolver {
  JackettResolver(this._http, this._log, this._settings);

  final http.Client _http;
  final ErrorLogService _log;
  final SettingsService _settings;

  JackettConfig? _config;

  /// Point the resolver at the running sidecar (or null to disable). Called by
  /// the Jackett sidecar once its Torznab API answers and the key is read.
  void configure(JackettConfig? config) => _config = config;

  bool get isConfigured => _config != null;

  @override
  Future<TorrentHandle?> resolve(
    ShowMeta meta,
    int? season,
    int? episode, {
    Set<String> exclude = const {},
    bool allowSeasonPack = true,
  }) async {
    final config = _config;
    if (config == null) {
      // Sidecar not up / not configured — degrade, but say so: this is the most
      // common reason a Download & Play finds "no source".
      _log.info('Jackett not configured (sidecar not ready) — skipping',
          source: 'JackettResolver');
      return null;
    }

    final excludeSign = _settings.excludeSignLanguage;
    final preferLang = _settings.preferredAudioLanguage;
    try {
      // TV episode: verify the release actually is this episode — never trust the
      // indexer's season/ep filtering, which routinely returns other episodes.
      if (season != null && episode != null) {
        // Tier 1 — prefer a whole-season pack: it's usually better-seeded and one
        // consistent A/V source across the season, and the daemon extracts just
        // this episode's file from it (season-only query). Skipped when the
        // caller says the season is still airing (no complete pack can exist).
        if (allowSeasonPack) {
          final packResults = await _query(config, meta, season, null);
          final packBest = pickBestTorznabResult(
              seasonPackResults(packResults, meta, season,
                  excludeSignLanguage: excludeSign, excludeUrls: exclude),
              preferAudioLanguage: preferLang);
          if (packBest != null) {
            _log.info(
                'resolved S${season}E$episode via season pack "${packBest.title}"',
                source: 'JackettResolver');
            return TorrentHandle(
                magnetOrUrl: packBest.downloadUrl,
                displayName: packBest.title,
                seasonPack: true);
          }
        }

        // Tier 2 — no verified season pack (or packs skipped): a release whose
        // title parses to exactly this S/E.
        final episodeResults = await _query(config, meta, season, episode);
        final episodeBest = pickBestTorznabResult(
            verifiedEpisodeResults(episodeResults, meta, season, episode,
                excludeSignLanguage: excludeSign, excludeUrls: exclude),
            preferAudioLanguage: preferLang);
        if (episodeBest != null) {
          _log.info(
              'no verified season pack for S${season}E$episode — using single '
              'episode "${episodeBest.title}"',
              source: 'JackettResolver');
          return TorrentHandle(
              magnetOrUrl: episodeBest.downloadUrl,
              displayName: episodeBest.title);
        }

        _log.info(
            'no verified source for S${season}E$episode of "${meta.title}"',
            source: 'JackettResolver');
        return null;
      }

      // Movie / unscoped search: keep only releases whose title actually names
      // this movie (a strict match — not mere containment — so "Descendants"
      // never grabs "Descendants Wicked Wonderland"), then rank by seed health.
      final results = await _query(config, meta, season, episode);
      final pool = verifiedMovieResults(results, meta,
          excludeSignLanguage: excludeSign, excludeUrls: exclude);
      final best = pickBestTorznabResult(pool, preferAudioLanguage: preferLang);
      if (best == null) {
        _log.info('no title-verified source for movie "${meta.title}"',
            source: 'JackettResolver');
        return null;
      }
      return TorrentHandle(
          magnetOrUrl: best.downloadUrl, displayName: best.title);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'JackettResolver.resolve');
      return null;
    }
  }

  @override
  Future<TorrentHandle?> resolveSeasonPack(
    ShowMeta meta,
    int season, {
    Set<String> exclude = const {},
  }) async {
    final config = _config;
    if (config == null) return null;
    try {
      final results = await _query(config, meta, season, null);
      final best = pickBestTorznabResult(
        seasonPackResults(results, meta, season,
            excludeSignLanguage: _settings.excludeSignLanguage,
            excludeUrls: exclude),
        preferAudioLanguage: _settings.preferredAudioLanguage,
      );
      if (best == null) return null;
      return TorrentHandle(
          magnetOrUrl: best.downloadUrl,
          displayName: best.title,
          seasonPack: true);
    } catch (e, st) {
      _log.logError(e,
          stackTrace: st, source: 'JackettResolver.resolveSeasonPack');
      return null;
    }
  }

  @override
  Future<TorrentHandle?> resolveShowPack(
    ShowMeta meta, {
    Set<String> exclude = const {},
  }) async {
    final config = _config;
    if (config == null) return null;
    try {
      final results = await _query(config, meta, null, null, showPack: true);
      final best = pickBestTorznabResult(
        showPackResults(results, meta,
            excludeSignLanguage: _settings.excludeSignLanguage,
            excludeUrls: exclude),
        preferAudioLanguage: _settings.preferredAudioLanguage,
      );
      if (best == null) return null;
      return TorrentHandle(
          magnetOrUrl: best.downloadUrl,
          displayName: best.title,
          seasonPack: true);
    } catch (e, st) {
      _log.logError(e,
          stackTrace: st, source: 'JackettResolver.resolveShowPack');
      return null;
    }
  }

  @override
  Future<List<SourceCandidate>> candidates(
    ShowMeta meta,
    int? season,
    int? episode, {
    Set<String> exclude = const {},
  }) async {
    final config = _config;
    if (config == null) return const [];
    final excludeSign = _settings.excludeSignLanguage;
    try {
      // Gather verified sources, tagging each as a single episode or a pack.
      final pack = <String, bool>{}; // downloadUrl → isSeasonPack
      final results = <TorznabResult>[];
      if (season != null && episode != null) {
        final eps = verifiedEpisodeResults(
            await _query(config, meta, season, episode), meta, season, episode,
            excludeSignLanguage: excludeSign, excludeUrls: exclude);
        for (final r in eps) {
          results.add(r);
          pack[r.downloadUrl] = false;
        }
        final packs = seasonPackResults(
            await _query(config, meta, season, null), meta, season,
            excludeSignLanguage: excludeSign, excludeUrls: exclude);
        for (final r in packs) {
          results.add(r);
          pack[r.downloadUrl] = true;
        }
      } else {
        final movies = verifiedMovieResults(
            await _query(config, meta, season, episode), meta,
            excludeSignLanguage: excludeSign, excludeUrls: exclude);
        for (final r in movies) {
          results.add(r);
          pack[r.downloadUrl] = false;
        }
      }

      // Rank episodes + packs together, then collapse same-content duplicates.
      final ranked = dedupeTorznabResults(rankedTorznabResults(results,
          preferAudioLanguage: _settings.preferredAudioLanguage));
      return [
        for (final r in ranked)
          SourceCandidate(
            handle: TorrentHandle(
                magnetOrUrl: r.downloadUrl,
                displayName: r.title,
                seasonPack: pack[r.downloadUrl] ?? false),
            title: r.title,
            sizeBytes: r.sizeBytes,
            seeders: r.seeders,
          ),
      ];
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'JackettResolver.candidates');
      return const [];
    }
  }

  /// Run one Torznab query and parse it; [] on a non-200 or empty feed.
  Future<List<TorznabResult>> _query(
      JackettConfig config, ShowMeta meta, int? season, int? episode,
      {bool showPack = false}) async {
    final res = await _http
        .get(buildTorznabUri(config, meta, season, episode, showPack: showPack));
    if (res.statusCode != 200) {
      _log.warn('Jackett Torznab HTTP ${res.statusCode}',
          source: 'JackettResolver');
      return const [];
    }
    return parseTorznabResults(res.body);
  }
}

/// The local Jackett endpoint: base URL (e.g. `http://127.0.0.1:9117`) plus the
/// auto-generated Torznab API key (read from `ServerConfig.json`).
class JackettConfig {
  const JackettConfig({required this.baseUrl, required this.apiKey});
  final String baseUrl;
  final String apiKey;
}

/// One normalized row from a Torznab feed.
class TorznabResult {
  const TorznabResult({
    required this.title,
    required this.downloadUrl,
    this.sizeBytes = 0,
    this.seeders = 0,
    this.peers = 0,
  });

  final String title;

  /// A magnet or a `.torrent` URL — handed straight to the daemon, which fetches
  /// a URL or adds a magnet uniformly.
  final String downloadUrl;
  final int sizeBytes;
  final int seeders;
  final int peers;
}

/// Build the aggregate Torznab request against `indexers/all`. Uses `tvsearch`
/// (category 5000) whenever a [season] is given — with `ep` when an [episode] is
/// too (single episode), or season-only (a season-pack query) when it's null —
/// else a movie `search` (category 2000). Pure + tested. Newznab category
/// numbers: 2000 = Movies, 5000 = TV.
Uri buildTorznabUri(
    JackettConfig config, ShowMeta meta, int? season, int? episode,
    {bool showPack = false}) {
  // A show-pack search is TV with no season scope (the whole series in one
  // query); otherwise TV whenever a season is given, else a movie search.
  final isTv = showPack || season != null;
  final params = <String, String>{
    'apikey': config.apiKey,
    't': isTv ? 'tvsearch' : 'search',
    'q': meta.title,
    'cat': isTv ? '5000' : '2000',
    if (season != null) 'season': '$season',
    if (episode != null) 'ep': '$episode',
  };
  final base = config.baseUrl.endsWith('/')
      ? config.baseUrl.substring(0, config.baseUrl.length - 1)
      : config.baseUrl;
  return Uri.parse('$base/api/v2.0/indexers/all/results/torznab/api')
      .replace(queryParameters: params);
}

/// Parse a Torznab (RSS) XML response into [TorznabResult]s. Reads the download
/// link from the `magneturl` torznab attr, else the `<enclosure>` url, else
/// `<link>`; seeders/peers/size from torznab attrs (falling back to `<size>`).
/// `torznab:attr` elements are matched by local name so a different namespace
/// prefix still works. Malformed XML yields an empty list (never throws). Pure +
/// tested.
List<TorznabResult> parseTorznabResults(String xmlBody) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlBody);
  } catch (_) {
    return const [];
  }

  final results = <TorznabResult>[];
  for (final item in doc.findAllElements('item')) {
    final attrs = <String, String>{};
    for (final el in item.childElements) {
      if (el.name.local == 'attr') {
        final name = el.getAttribute('name');
        final value = el.getAttribute('value');
        if (name != null && value != null) attrs[name] = value;
      }
    }

    final title = item.getElement('title')?.innerText.trim() ?? '';
    final enclosureUrl = item.getElement('enclosure')?.getAttribute('url');
    final link = item.getElement('link')?.innerText.trim();
    final download = _firstNonEmpty([attrs['magneturl'], enclosureUrl, link]);
    if (title.isEmpty || download == null) continue;

    final size = int.tryParse(item.getElement('size')?.innerText ?? '') ??
        int.tryParse(attrs['size'] ?? '') ??
        int.tryParse(
            item.getElement('enclosure')?.getAttribute('length') ?? '') ??
        0;

    results.add(TorznabResult(
      title: title,
      downloadUrl: download,
      sizeBytes: size,
      seeders: int.tryParse(attrs['seeders'] ?? '') ?? 0,
      peers: int.tryParse(attrs['peers'] ?? '') ?? 0,
    ));
  }
  return results;
}

/// Rank Torznab hits best-first. When [preferAudioLanguage] is set (a non-empty
/// language the user wants dubbed audio in), releases whose title tags that
/// language rank first — an explicit tag over a generic multi/dual-audio marker
/// over neither — before the usual signals. Otherwise, and to break ties, seed
/// health dominates (the streaming signal), then the larger file (usually higher
/// quality). Pure + tested.
List<TorznabResult> rankedTorznabResults(
  List<TorznabResult> results, {
  String? preferAudioLanguage,
}) {
  final lang = preferAudioLanguage?.trim() ?? '';
  return [...results]..sort((a, b) {
      if (lang.isNotEmpty) {
        final sa = FilenameMediaInfo.audioLanguageScore(a.title, lang);
        final sb = FilenameMediaInfo.audioLanguageScore(b.title, lang);
        if (sa != sb) return sb.compareTo(sa);
      }
      if (a.seeders != b.seeders) return b.seeders.compareTo(a.seeders);
      return b.sizeBytes.compareTo(a.sizeBytes);
    });
}

/// The best-ranked hit, or null when [results] is empty. See [rankedTorznabResults].
TorznabResult? pickBestTorznabResult(
  List<TorznabResult> results, {
  String? preferAudioLanguage,
}) {
  final ranked =
      rankedTorznabResults(results, preferAudioLanguage: preferAudioLanguage);
  return ranked.isEmpty ? null : ranked.first;
}

/// The BitTorrent infohash in a magnet URL (`…btih:<hash>…`), lowercased — or
/// null for a `.torrent` URL, whose infohash isn't known until it's fetched.
/// Pure + tested.
String? torrentInfohash(String url) {
  final m = RegExp(r'btih:([a-fA-F0-9]{40}|[a-zA-Z2-7]{32})').firstMatch(url);
  return m?.group(1)?.toLowerCase();
}

/// Collapse [results] that point at the **same torrent** — same magnet infohash,
/// or (for `.torrent` URLs that hide it) same normalized title + size — keeping
/// the first of each group. Feed a ranked list so the survivor is the best-seeded
/// listing. Stops "try another source" and the source picker from offering the
/// same content re-listed by several indexers. Pure + tested.
List<TorznabResult> dedupeTorznabResults(List<TorznabResult> results) {
  final seen = <String>{};
  final out = <TorznabResult>[];
  for (final r in results) {
    final key = torrentInfohash(r.downloadUrl) ??
        '${FilenameMediaInfo.normalizeTitle(r.title)}|${r.sizeBytes}';
    if (seen.add(key)) out.add(r);
  }
  return out;
}

/// Minimum plausible episode size — drops `.nfo`/sample/fake rows that sometimes
/// out-seed the real release. Only applied when a size is reported.
const int _minEpisodeBytes = 50 * 1024 * 1024; // 50 MB

/// Keep only [results] that **verify** as the requested [season]/[episode] of
/// [meta]'s show: the title must name the same show AND parse to exactly that
/// `SxxExx`. This is the fix for "asked for episode 1, got episode 9" — the
/// indexer's own season/ep filtering is not trusted. Sign-language cuts are
/// dropped when [excludeSignLanguage]; sources whose download URL is in
/// [excludeUrls] (already tried) are dropped; implausibly tiny files are dropped.
/// Order is preserved (rank with [pickBestTorznabResult]). Pure + tested.
List<TorznabResult> verifiedEpisodeResults(
  List<TorznabResult> results,
  ShowMeta meta,
  int season,
  int episode, {
  bool excludeSignLanguage = true,
  Set<String> excludeUrls = const {},
}) {
  return results.where((r) {
    if (excludeSignLanguage &&
        FilenameMediaInfo.looksLikeSignLanguage(r.title)) {
      return false;
    }
    if (excludeUrls.contains(r.downloadUrl)) return false;
    if (r.sizeBytes > 0 && r.sizeBytes < _minEpisodeBytes) return false;
    if (!FilenameMediaInfo.titleMatches(r.title, meta.title)) return false;
    final parsed = FilenameMediaInfo.parse(r.title);
    return parsed.season == season && parsed.episode == episode;
  }).toList();
}

/// Keep only [results] that verify as the requested **movie** [meta]: the title
/// must strictly name the same film (not merely contain it, so "Descendants"
/// never grabs "Descendants Wicked Wonderland" — see
/// [FilenameMediaInfo.titleMatchesStrict]). Sign-language cuts dropped when
/// [excludeSignLanguage]; already-tried sources dropped when their URL is in
/// [excludeUrls]; implausibly tiny files dropped. Order preserved (rank with
/// [pickBestTorznabResult]). Pure + tested.
List<TorznabResult> verifiedMovieResults(
  List<TorznabResult> results,
  ShowMeta meta, {
  bool excludeSignLanguage = true,
  Set<String> excludeUrls = const {},
}) {
  return results.where((r) {
    if (excludeSignLanguage &&
        FilenameMediaInfo.looksLikeSignLanguage(r.title)) {
      return false;
    }
    if (excludeUrls.contains(r.downloadUrl)) return false;
    if (r.sizeBytes > 0 && r.sizeBytes < _minEpisodeBytes) return false;
    return FilenameMediaInfo.titleMatchesStrict(r.title, meta.title);
  }).toList();
}

/// Keep only [results] that verify as a **whole-season pack** for [season] of
/// [meta]'s show (right show + a season-pack marker for this season, and *not* a
/// single different episode). The requested episode is later extracted from the
/// pack's file list. Sign-language cuts dropped when [excludeSignLanguage];
/// already-tried sources dropped when their URL is in [excludeUrls]. Order
/// preserved. Pure + tested.
List<TorznabResult> seasonPackResults(
  List<TorznabResult> results,
  ShowMeta meta,
  int season, {
  bool excludeSignLanguage = true,
  Set<String> excludeUrls = const {},
}) {
  return results.where((r) {
    if (excludeSignLanguage &&
        FilenameMediaInfo.looksLikeSignLanguage(r.title)) {
      return false;
    }
    if (excludeUrls.contains(r.downloadUrl)) return false;
    if (!FilenameMediaInfo.titleMatches(r.title, meta.title)) return false;
    return FilenameMediaInfo.seasonPackNumber(r.title) == season;
  }).toList();
}

/// Keep only [results] that verify as a **whole-series pack** for [meta]'s show
/// (right show + a complete-series / season-range marker — see
/// [FilenameMediaInfo.isShowPack]). Used by the bulk "Download all seasons" flow
/// to prefer one series torrent over per-season/per-episode ones. Sign-language
/// cuts dropped when [excludeSignLanguage]; already-tried sources dropped when
/// their URL is in [excludeUrls]. Order preserved. Pure + tested.
List<TorznabResult> showPackResults(
  List<TorznabResult> results,
  ShowMeta meta, {
  bool excludeSignLanguage = true,
  Set<String> excludeUrls = const {},
}) {
  return results.where((r) {
    if (excludeSignLanguage &&
        FilenameMediaInfo.looksLikeSignLanguage(r.title)) {
      return false;
    }
    if (excludeUrls.contains(r.downloadUrl)) return false;
    if (!FilenameMediaInfo.titleMatches(r.title, meta.title)) return false;
    return FilenameMediaInfo.isShowPack(r.title);
  }).toList();
}

/// Read Jackett's auto-generated Torznab API key from the contents of its
/// `ServerConfig.json` (`{"APIKey": "..."}`). Null if absent/malformed. Pure +
/// tested — the sidecar will use this once it's built.
String? parseJackettApiKey(String serverConfigJson) {
  try {
    final json = jsonDecode(serverConfigJson) as Map<String, dynamic>;
    final key = json['APIKey'];
    return (key is String && key.isNotEmpty) ? key : null;
  } catch (_) {
    return null;
  }
}

String? _firstNonEmpty(List<String?> candidates) {
  for (final c in candidates) {
    if (c != null && c.trim().isNotEmpty) return c.trim();
  }
  return null;
}
