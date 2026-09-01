import 'package:couch_roach/src/core/config/app_config.dart';

/// An [AppConfig] whose key-gated getters can be set from a test.
///
/// The real values come from `--dart-define` and are compile-time constants, so
/// a test binary always sees them empty — which means every code path behind a
/// `hasTmdbKey` / `hasAlexaInbox` check is unreachable with the real config.
/// Services take an [AppConfig] as a constructor dependency precisely so a test
/// can pass this instead and exercise the configured path.
///
/// Defaults to **fully configured**, since that's the interesting case; pass
/// `false` to assert the no-op behaviour of an unconfigured build.
class FakeAppConfig implements AppConfig {
  const FakeAppConfig({
    this.hasTmdbKey = true,
    this.hasOpenSubtitlesKey = true,
    this.hasAlexaInbox = true,
    this.inboxBaseUrl = 'https://inbox.test',
    this.inboxToken = 'test-token',
  });

  @override
  final bool hasTmdbKey;

  @override
  final bool hasOpenSubtitlesKey;

  @override
  final bool hasAlexaInbox;

  @override
  final String inboxBaseUrl;

  @override
  final String inboxToken;
}
