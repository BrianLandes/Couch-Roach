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

  bool get hasTmdbKey => tmdbApiKey.isNotEmpty;
  bool get hasOpenSubtitlesKey => openSubtitlesApiKey.isNotEmpty;
}
