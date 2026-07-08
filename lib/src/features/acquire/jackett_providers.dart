import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/acquisition/jackett_process.dart';

/// How often the settings indexer status re-checks the Jackett sidecar. Same
/// spirit as the Downloads daemon ping — there's no push channel, so poll.
const _pollInterval = Duration(seconds: 3);

/// Whether the Jackett indexer sidecar's Torznab API is reachable — drives the
/// online/offline pill in Settings. autoDispose so polling stops when the
/// settings screen is closed.
final jackettAliveProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final jackett = getIt<JackettProcess>();
  while (true) {
    yield await jackett.isAlive();
    await Future<void>.delayed(_pollInterval);
  }
});
