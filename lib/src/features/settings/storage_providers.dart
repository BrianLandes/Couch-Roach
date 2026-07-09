import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_root.dart';
import '../../data/repositories/storage_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';

/// Live list of all configured storage roots (enabled and disabled), fed by the
/// drift watch query so the settings UI updates as rows change.
final storageRootsProvider = StreamProvider.autoDispose<List<StorageRoot>>(
  (ref) => getIt<StorageRepository>().watchRoots(),
);

/// Live queue of watched files awaiting auto-cleanup — completed, not pinned,
/// still on disk — soonest-reaped first. Settings shows these so the user can
/// see what's about to be deleted and pin anything worth keeping.
final reapCandidatesProvider = StreamProvider.autoDispose<List<ReapCandidate>>(
  (ref) => getIt<WatchHistoryRepository>().watchReapCandidates(),
);
