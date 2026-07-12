import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../discovery/tmdb_client.dart';

/// Poll-and-drain consumer for the Alexa voice inbox (see docs handoff). Titles
/// spoken to the Alexa skill sit in a Cloudflare KV queue behind a Worker; this
/// service drains that queue on demand — once at startup and again on returning
/// to the landing page — resolves each title against TMDB, and drops the top hit
/// onto the Want-to-watch list tagged `source: 'alexa'`.
///
/// There is **no** background timer: the queue waits patiently in KV (30-day
/// TTL) for the next drain, so a title spoken while the app is closed is picked
/// up on the next launch. Delivery is at-least-once; dedupe is inherent because
/// the Want-to-watch upsert is keyed by TMDB id, so a re-delivered title just
/// re-stamps the same row.
@LazySingleton()
class AlexaInboxService {
  AlexaInboxService(this._http, this._tmdb, this._saved, this._log);

  final http.Client _http;
  final DiscoveryClient _tmdb;
  final SavedTitlesRepository _saved;
  final ErrorLogService _log;

  static const _timeout = Duration(seconds: 10);

  bool _busy = false;
  DateTime? _lastDrain;

  /// Guards the "drain disabled" diagnostic so it's logged once per process
  /// rather than on every startup + landing-page trigger.
  bool _loggedDisabled = false;

  /// Drain the queue: fetch pending titles, resolve + save each, then ack the
  /// ones that succeeded. Fire-and-forget — call at startup and on landing-page
  /// re-entry. No-ops if the inbox isn't configured, a drain is already running,
  /// or one completed within [minGap] (pass `Duration.zero` to bypass the
  /// throttle for a manual refresh or a test). Never throws: routine network
  /// blips are swallowed (and logged) so the empty-queue common case stays
  /// silent and cheap.
  Future<void> drain({Duration minGap = const Duration(seconds: 30)}) async {
    const src = 'AlexaInboxService.drain';
    // An unconfigured build (no token, or TMDB unavailable to resolve titles)
    // never talks to the Worker. This is the #1 reason a release build silently
    // does nothing — the token must be compiled in via
    // `--dart-define-from-file=dart_define.json`, which a plain
    // `flutter build windows` omits — so say so loudly (once per process).
    const cfg = AppConfig();
    if (!cfg.hasAlexaInbox || !cfg.hasTmdbKey) {
      if (!_loggedDisabled) {
        _loggedDisabled = true;
        _log.warn(
          'inbox drain DISABLED: token=${cfg.hasAlexaInbox ? "set" : "MISSING"}, '
          'tmdbKey=${cfg.hasTmdbKey ? "set" : "MISSING"} — a release build must '
          'pass --dart-define-from-file=dart_define.json',
          source: src,
        );
      }
      return;
    }
    if (_busy) return;
    final last = _lastDrain;
    if (last != null && DateTime.now().difference(last) < minGap) {
      _log.info('inbox drain skipped (throttled, <${minGap.inSeconds}s)',
          source: src);
      return;
    }
    _busy = true;
    try {
      const base = AppConfig.alexaInboxBaseUrl;
      const token = AppConfig.alexaInboxToken;

      // Base URL is safe to log (public endpoint); the token is NOT — never log
      // it. This line + the status line below localize a VPN/DNS/TLS failure.
      _log.info('inbox draining $base/pending', source: src);
      final res = await _http
          .get(Uri.parse('$base/pending?token=$token'))
          .timeout(_timeout);
      if (res.statusCode != 200) {
        // 401 => token mismatch between build and Worker; anything else =>
        // Worker/routing problem.
        _log.warn('inbox /pending -> ${res.statusCode} ${res.reasonPhrase}',
            source: src);
        return;
      }

      final items =
          (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      _log.info('inbox /pending -> 200, ${items.length} queued', source: src);
      if (items.isNotEmpty) {
        final done = <String>[];
        for (final item in items) {
          final id = item['id'] as String;
          final title = item['title'] as String;
          try {
            await addFromAlexa(title);
            done.add(id); // resolved, saved, or a deliberate no-match → ack it
          } catch (e, st) {
            // Transient (e.g. a db lock): leave it queued for the next drain.
            _log.logError(e,
                stackTrace: st,
                source: 'AlexaInboxService.addFromAlexa($title)');
          }
        }

        if (done.isNotEmpty) {
          final ack = await _http
              .post(
                Uri.parse('$base/ack?token=$token'),
                headers: const {'content-type': 'application/json'},
                body: jsonEncode({'ids': done}),
              )
              .timeout(_timeout);
          _log.info('inbox acked ${done.length}/${items.length} -> '
              '${ack.statusCode}', source: src);
        }
      }
      // Only stamp on a completed cycle, so a network hiccup lets the next
      // trigger retry immediately rather than being throttled out.
      _lastDrain = DateTime.now();
    } catch (e, st) {
      // A SocketException / TimeoutException here on the Windows box points at
      // the VPN (DNS for the custom domain, or blocked/split-tunnelled egress).
      _log.logError(e, stackTrace: st, source: src);
    } finally {
      _busy = false;
    }
  }

  /// Resolve a raw ASR [rawTitle] to a TMDB title and add it to Want-to-watch.
  ///
  /// v1 policy (handoff §5): the ASR text is a search query, not a canonical
  /// title, so we take the **top** TMDB hit — movies first (the skill says
  /// "add movie"), then TV as a fallback so a spoken show still lands somewhere.
  /// A no-match is logged and swallowed (returns normally so the queue item is
  /// acked, not looped forever). Only genuinely transient failures should throw
  /// — and note [DiscoveryClient] already swallows its own network errors and
  /// returns an empty list, so a TMDB *outage* reads as a no-match here (the
  /// title is acked and lost); a db-write failure below still throws and keeps
  /// the item queued.
  Future<void> addFromAlexa(String rawTitle) async {
    final query = rawTitle.trim();
    if (query.isEmpty) return;

    final movies = await _tmdb.searchMovies(query);
    if (movies.isNotEmpty) {
      final m = movies.first;
      await _saved.setWantToWatch(
        tmdbId: m.tmdbId,
        mediaType: 'movie',
        name: m.title,
        posterPath: m.posterPath,
        value: true,
        source: 'alexa',
      );
      _log.info('Alexa added "$rawTitle" → ${m.title} (movie ${m.tmdbId})',
          source: 'AlexaInboxService');
      return;
    }

    final shows = await _tmdb.searchTv(query);
    if (shows.isNotEmpty) {
      final s = shows.first;
      await _saved.setWantToWatch(
        tmdbId: s.tmdbId,
        mediaType: 'tv',
        name: s.name,
        posterPath: s.posterPath,
        value: true,
        source: 'alexa',
      );
      _log.info('Alexa added "$rawTitle" → ${s.name} (tv ${s.tmdbId})',
          source: 'AlexaInboxService');
      return;
    }

    // No-match: log + swallow so it acks and doesn't re-deliver forever.
    _log.warn('Alexa inbox: no TMDB match for "$rawTitle"',
        source: 'AlexaInboxService');
  }
}
