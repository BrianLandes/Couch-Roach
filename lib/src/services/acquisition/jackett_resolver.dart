import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:xml/xml.dart';

import '../../core/logging/error_log_service.dart';
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
  JackettResolver(this._http, this._log);

  final http.Client _http;
  final ErrorLogService _log;

  JackettConfig? _config;

  /// Point the resolver at the running sidecar (or null to disable). Called by
  /// the Jackett sidecar once its Torznab API answers and the key is read.
  void configure(JackettConfig? config) => _config = config;

  bool get isConfigured => _config != null;

  @override
  Future<TorrentHandle?> resolve(ShowMeta meta, int? season, int? episode) async {
    final config = _config;
    if (config == null) return null; // sidecar not ready → degrade quietly

    final uri = buildTorznabUri(config, meta, season, episode);
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) {
        _log.warn('Jackett Torznab HTTP ${res.statusCode}',
            source: 'JackettResolver');
        return null;
      }
      final best = pickBestTorznabResult(parseTorznabResults(res.body));
      if (best == null) return null;
      return TorrentHandle(
          magnetOrUrl: best.downloadUrl, displayName: best.title);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'JackettResolver.resolve');
      return null;
    }
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
/// (category 5000) with season/episode when both are known, else a movie
/// `search` (category 2000). Pure + tested. Newznab category numbers:
/// 2000 = Movies, 5000 = TV.
Uri buildTorznabUri(
    JackettConfig config, ShowMeta meta, int? season, int? episode) {
  final isEpisode = season != null && episode != null;
  final params = <String, String>{
    'apikey': config.apiKey,
    't': isEpisode ? 'tvsearch' : 'search',
    'q': meta.title,
    'cat': isEpisode ? '5000' : '2000',
    if (isEpisode) 'season': '$season',
    if (isEpisode) 'ep': '$episode',
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

/// Rank Torznab hits and return the best, or null when [results] is empty.
/// Seed health is the dominant streaming signal, so sort by seeders desc, then
/// prefer the larger file (usually the higher-quality release). Pure + tested.
TorznabResult? pickBestTorznabResult(List<TorznabResult> results) {
  if (results.isEmpty) return null;
  final sorted = [...results]..sort((a, b) {
      if (a.seeders != b.seeders) return b.seeders.compareTo(a.seeders);
      return b.sizeBytes.compareTo(a.sizeBytes);
    });
  return sorted.first;
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
