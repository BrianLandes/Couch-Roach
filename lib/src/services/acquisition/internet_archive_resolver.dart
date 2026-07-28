import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/error_log_service.dart';
import '../../core/media/video_extensions.dart';
import 'acquisition.dart';

/// [AcquisitionResolver] for the **Internet Archive** (archive.org) — a legal,
/// licensed-for-distribution source of public-domain video (HANDOFF §8;
/// CLAUDE.md legal boundary). Every IA item exposes an auto-generated
/// `_archive.torrent`, so resolving is: search → confirm the item has a video
/// file → hand back that torrent URL. The daemon picks the primary file at
/// download time.
///
/// This is the one legal, zero-config resolver that ships active in the repo;
/// the content-agnostic Jackett resolver (user-configured) lands separately.
/// Both are composed behind the [AcquisitionResolver] seam by
/// [CompositeAcquisitionResolver] — this registers as itself, not the seam.
@LazySingleton()
// `extends` (not `implements`) so it inherits the null pack-resolver defaults —
// the Internet Archive serves single public-domain titles, not TV season/series
// packs.
class InternetArchiveResolver extends AcquisitionResolver {
  InternetArchiveResolver(this._http, this._log);

  final http.Client _http;
  final ErrorLogService _log;

  static const _host = 'archive.org';

  /// How many search hits to check (each costs a metadata call) before giving up.
  static const _maxCandidates = 5;

  @override
  Future<TorrentHandle?> resolve(
    ShowMeta meta,
    int? season,
    int? episode, {
    Set<String> exclude = const {},
    bool allowSeasonPack = true, // IA serves single titles; no packs to skip
  }) async {
    final searchUri = Uri.https(_host, '/advancedsearch.php', {
      'q': buildInternetArchiveQuery(meta, season, episode),
      'fl[]': ['identifier', 'title'],
      'rows': '$_maxCandidates',
      'output': 'json',
      // IA web-seeds every torrent, so seed health is a non-issue; sort by
      // downloads to prefer the canonical/most-used copy of a title.
      'sort[]': ['downloads desc'],
    });

    final search = await _getJson(searchUri, 'search');
    final docs = ((search?['response'] as Map?)?['docs'] as List?) ?? const [];

    for (final doc in docs.whereType<Map>()) {
      final id = doc['identifier'] as String?;
      if (id == null || id.isEmpty) continue;

      // Skip a source already tried for this title ("try another source").
      if (exclude.contains(internetArchiveTorrentUrl(id))) continue;

      // Confirm the item actually has playable video before committing to it —
      // IA items can be audio/text/metadata only.
      final metadata = await _getJson(Uri.https(_host, '/metadata/$id'), 'metadata');
      final files = (metadata?['files'] as List?)?.whereType<Map>().toList();
      if (files == null || !files.any(fileLooksLikeVideo)) continue;

      return TorrentHandle(
        magnetOrUrl: internetArchiveTorrentUrl(id),
        displayName: _asString(doc['title']) ?? id,
      );
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri, String what) async {
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) {
        _log.warn('Internet Archive $what ${res.statusCode}',
            source: 'InternetArchiveResolver');
        return null;
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'InternetArchiveResolver.$what');
      return null;
    }
  }
}

/// IA multivalued fields can arrive as a `String` or a `List`. Coerce to the
/// first string, or null.
String? _asString(Object? v) {
  if (v is String) return v;
  if (v is List && v.isNotEmpty && v.first is String) return v.first as String;
  return null;
}

/// Build the archive.org advanced-search query. Scoped to the `title` field and
/// `mediatype:movies` so hits are actual films, not full-text noise. Pure +
/// tested.
String buildInternetArchiveQuery(ShowMeta meta, int? season, int? episode) {
  final terms = <String>[_sanitizeLucene(meta.title)];
  if (season != null && episode != null) {
    terms.add('S${_two(season)}E${_two(episode)}');
  }
  final title = terms.where((t) => t.isNotEmpty).join(' ').trim();
  return 'title:($title) AND mediatype:(movies)';
}

/// The deterministic URL of an IA item's auto-generated torrent. Pure + tested.
String internetArchiveTorrentUrl(String identifier) =>
    'https://archive.org/download/$identifier/${identifier}_archive.torrent';

/// Whether an IA `files[]` entry is a video — by extension **or** by IA's
/// `format` label (IA uses formats like `h.264`, `Ogg Video`, `512Kb MPEG4`,
/// `MPEG2` that don't all map to an extension in [kVideoExtensions]). Pure +
/// tested.
bool fileLooksLikeVideo(Map<dynamic, dynamic> file) {
  final name = file['name'];
  if (name is String &&
      kVideoExtensions.contains(p.extension(name).toLowerCase())) {
    return true;
  }
  final format = (file['format'] as String?)?.toLowerCase() ?? '';
  if (format.isEmpty) return false;
  const hints = [
    'h.264', 'mpeg4', 'mpeg2', 'mpeg', 'ogg video', 'matroska',
    'quicktime', 'divx', 'webm', 'video',
  ];
  return hints.any(format.contains);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Strip Lucene/IA query metacharacters from a title so it can't break the
/// query or inject syntax; collapse whitespace.
String _sanitizeLucene(String s) => s
    .replaceAll(RegExp(r'[+\-&|!(){}\[\]^"~*?:\\/]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
