import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import 'settings_service.dart';

/// Whether the (opt-in, default-off) Internet Archive source is enabled, as a
/// provider so UI rebuilds when the setting is toggled. [SettingsService] is a
/// [ChangeNotifier]; we re-read on each notification (and never dispose the
/// singleton — only detach our listener).
final internetArchiveEnabledProvider = Provider<bool>((ref) {
  final settings = getIt<SettingsService>();
  void onChange() => ref.invalidateSelf();
  settings.addListener(onChange);
  ref.onDispose(() => settings.removeListener(onChange));
  return settings.internetArchiveEnabled;
});
