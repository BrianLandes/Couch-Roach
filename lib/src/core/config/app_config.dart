/// Runtime configuration. Secrets are injected at build/run time via
/// `--dart-define` so nothing sensitive lands in git (see DECISIONS: secrets).
///
/// Example:
///   flutter run --dart-define=OPENSUBTITLES_API_KEY=xxx --dart-define=TMDB_API_KEY=yyy
class AppConfig {
  const AppConfig();

  /// Required by OpenSubtitles or requests are rejected (HANDOFF §4.6).
  static const String openSubtitlesUserAgent = 'CouchRoach v0.1.0';

  static const String openSubtitlesApiKey =
      String.fromEnvironment('OPENSUBTITLES_API_KEY');

  static const String tmdbApiKey =
      String.fromEnvironment('TMDB_API_KEY');

  /// Cloudflare Worker that queues titles spoken to the Alexa skill. The base
  /// URL is the public endpoint (not a secret) so it has a default; the token
  /// is the shared secret and must come from `--dart-define` (never hardcoded).
  static const String alexaInboxBaseUrl = String.fromEnvironment(
    'ALEXA_INBOX_BASE_URL',
    defaultValue: 'https://alexa.couchroach.professionalbadguys.com',
  );

  static const String alexaInboxToken =
      String.fromEnvironment('ALEXA_INBOX_TOKEN');

  // Every value a service reads is exposed as an **instance** getter over the
  // `--dart-define` constant above, and services take an [AppConfig] as a
  // constructor dependency (registered in `RegisterModule`) rather than
  // constructing one inline. That's what makes a key-gated code path reachable
  // in a test: a fake overrides the getter, since the constants themselves are
  // fixed at compile time and a test binary has no `--dart-define`.

  bool get hasTmdbKey => tmdbApiKey.isNotEmpty;
  bool get hasOpenSubtitlesKey => openSubtitlesApiKey.isNotEmpty;

  /// True only when the inbox token is configured — the drain no-ops otherwise
  /// (an unconfigured build never polls the Worker).
  bool get hasAlexaInbox => alexaInboxToken.isNotEmpty;

  /// Public Worker endpoint the Alexa inbox drains from.
  String get inboxBaseUrl => alexaInboxBaseUrl;

  /// Shared secret for the Worker. Never log this.
  String get inboxToken => alexaInboxToken;
}
