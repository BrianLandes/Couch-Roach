import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';
import 'acquisition.dart';
import 'internet_archive_resolver.dart';
import 'jackett_resolver.dart';

/// The [AcquisitionResolver] the play flow uses — it fans a request across the
/// available sub-resolvers and returns the **first hit** (DECISIONS §D resolved
/// the open "coexist/precede" question this way).
///
/// Order: **Internet Archive first** (a clean, zero-config public-domain source),
/// then **Jackett** (the user's own configured indexers). IA returns null for
/// almost every mainstream title, so in practice Jackett handles the common case
/// and IA only wins for the rare public-domain title present in both. Jackett
/// also returns null until its sidecar is up + configured, so this degrades to
/// IA-only automatically. A throwing sub-resolver is logged and skipped, never
/// failing the whole resolve.
@LazySingleton(as: AcquisitionResolver)
class CompositeAcquisitionResolver implements AcquisitionResolver {
  CompositeAcquisitionResolver(this._ia, this._jackett, this._log);

  final InternetArchiveResolver _ia;
  final JackettResolver _jackett;
  final ErrorLogService _log;

  List<AcquisitionResolver> get _ordered => [_ia, _jackett];

  @override
  Future<TorrentHandle?> resolve(
    ShowMeta meta,
    int? season,
    int? episode, {
    Set<String> exclude = const {},
  }) async {
    final ep = (season != null && episode != null) ? ' S${season}E$episode' : '';
    for (final resolver in _ordered) {
      try {
        final hit = await resolver.resolve(meta, season, episode,
            exclude: exclude);
        if (hit != null) {
          _log.info('resolved "${meta.title}"$ep via ${resolver.runtimeType}',
              source: 'CompositeResolver');
          return hit;
        }
      } catch (e, st) {
        _log.logError(e,
            stackTrace: st,
            source: 'CompositeResolver.${resolver.runtimeType}');
      }
    }
    _log.warn(
      'no source found for "${meta.title}"$ep — tried '
      '${_ordered.map((r) => r.runtimeType).join(', ')}',
      source: 'CompositeResolver',
    );
    return null;
  }
}
