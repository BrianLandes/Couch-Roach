import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';

/// One browsable Internet Archive title for the landing rail. [thumbnailUrl] is
/// IA's per-item image service (always returns something). [sizeBytes] is the
/// item's total size (from the search `item_size` field), used to pick a
/// download target disk.
class ArchiveItem {
  const ArchiveItem({
    required this.identifier,
    required this.title,
    this.year,
    this.sizeBytes = 0,
  });

  final String identifier;
  final String title;
  final int? year;
  final int sizeBytes;

  String get thumbnailUrl => 'https://archive.org/services/img/$identifier';

  static ArchiveItem? fromDoc(Map<String, dynamic> doc) {
    final id = doc['identifier'];
    if (id is! String || id.isEmpty) return null;
    return ArchiveItem(
      identifier: id,
      title: _firstString(doc['title']) ?? id,
      year: _parseYear(doc['year']),
      sizeBytes: (doc['item_size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Browses the Internet Archive for a **curated, family-safe** set of
/// public-domain titles to surface on the landing page ("Free to Watch"). It is
/// deliberately restricted to vetted collections — IA's open movie feeds
/// surface pirated/adult/exploitation uploads, so this never queries them.
///
/// Sourcing decision recorded with the feature: silent-film classics + classic
/// cartoons, sorted by all-time downloads so recognizable titles surface.
@LazySingleton()
class ArchiveBrowseService {
  ArchiveBrowseService(this._http, this._log);

  final http.Client _http;
  final ErrorLogService _log;

  static const _host = 'archive.org';

  /// Vetted public-domain collections only. Extend deliberately — anything
  /// added here shows up unfiltered on the family TV.
  static const curatedCollections = ['silent_films', 'classic_cartoons'];

  /// Top public-domain picks for the landing rail. Returns [] on failure so the
  /// rail just hides rather than erroring.
  Future<List<ArchiveItem>> popularPicks({int limit = 15}) async {
    final uri = Uri.https(_host, '/advancedsearch.php', {
      'q': curatedPicksQuery,
      'fl[]': ['identifier', 'title', 'year', 'item_size'],
      'rows': '$limit',
      'output': 'json',
      'sort[]': ['downloads desc'],
    });
    try {
      final res = await _http.get(uri);
      if (res.statusCode != 200) {
        _log.warn('Internet Archive browse ${res.statusCode}',
            source: 'ArchiveBrowseService');
        return const [];
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final docs = ((json['response'] as Map?)?['docs'] as List?) ?? const [];
      return docs
          .whereType<Map<String, dynamic>>()
          .map(ArchiveItem.fromDoc)
          .whereType<ArchiveItem>()
          .toList(growable: false);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'ArchiveBrowseService.popularPicks');
      return const [];
    }
  }
}

/// The advanced-search query for the curated picks (pure, exposed for testing).
String get curatedPicksQuery =>
    'mediatype:(movies) AND collection:(${ArchiveBrowseService.curatedCollections.join(' OR ')})';

String? _firstString(Object? v) {
  if (v is String) return v;
  if (v is List && v.isNotEmpty && v.first is String) return v.first as String;
  return null;
}

int? _parseYear(Object? v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v);
  if (v is List && v.isNotEmpty) return _parseYear(v.first);
  return null;
}
