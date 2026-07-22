import 'package:injectable/injectable.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/settings/settings_service.dart';
import 'acquisition.dart';
import 'internet_archive_resolver.dart';
import 'jackett_resolver.dart';

/// The [AcquisitionResolver] the play flow uses — it fans a request across the
/// available sub-resolvers and returns the **first hit**.
///
/// Order when enabled: **Internet Archive first** (a zero-config public-domain
/// source), then **Jackett** (the user's own configured indexers). IA is now
/// **opt-in and off by default** (deprecated in favour of Jackett; see
/// `SettingsService.internetArchiveEnabled` and DECISIONS §D) — so by default
/// this is Jackett-only, and IA only rejoins the chain when the user turns it
/// back on. Jackett also returns null until its sidecar is up + configured. A
/// throwing sub-resolver is logged and skipped, never failing the whole resolve.
@LazySingleton(as: AcquisitionResolver)
class CompositeAcquisitionResolver implements AcquisitionResolver {
  CompositeAcquisitionResolver(this._ia, this._jackett, this._settings, this._log);

  final InternetArchiveResolver _ia;
  final JackettResolver _jackett;
  final SettingsService _settings;
  final ErrorLogService _log;

  List<AcquisitionResolver> get _ordered => [
        if (_settings.internetArchiveEnabled) _ia,
        _jackett,
      ];

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

  @override
  Future<TorrentHandle?> resolveSeasonPack(
    ShowMeta meta,
    int season, {
    Set<String> exclude = const {},
  }) =>
      _firstPackHit(
        (r) => r.resolveSeasonPack(meta, season, exclude: exclude),
        '${meta.title} S$season pack',
      );

  @override
  Future<TorrentHandle?> resolveShowPack(
    ShowMeta meta, {
    Set<String> exclude = const {},
  }) =>
      _firstPackHit(
        (r) => r.resolveShowPack(meta, exclude: exclude),
        '${meta.title} complete-series pack',
      );

  @override
  Future<List<SourceCandidate>> candidates(
    ShowMeta meta,
    int? season,
    int? episode, {
    Set<String> exclude = const {},
  }) async {
    final all = <SourceCandidate>[];
    for (final resolver in _ordered) {
      try {
        all.addAll(
            await resolver.candidates(meta, season, episode, exclude: exclude));
      } catch (e, st) {
        _log.logError(e,
            stackTrace: st,
            source: 'CompositeResolver.candidates.${resolver.runtimeType}');
      }
    }
    return all;
  }

  /// Fan a pack request across the sub-resolvers, returning the first hit. A
  /// throwing sub-resolver is logged and skipped (mirrors [resolve]).
  Future<TorrentHandle?> _firstPackHit(
    Future<TorrentHandle?> Function(AcquisitionResolver) query,
    String label,
  ) async {
    for (final resolver in _ordered) {
      try {
        final hit = await query(resolver);
        if (hit != null) {
          _log.info('resolved $label via ${resolver.runtimeType}',
              source: 'CompositeResolver');
          return hit;
        }
      } catch (e, st) {
        _log.logError(e,
            stackTrace: st,
            source: 'CompositeResolver.${resolver.runtimeType}');
      }
    }
    return null;
  }
}
