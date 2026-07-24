import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';

/// Live list of present (non-missing) library items, fed by the drift watch
/// query so screens update as scans land and files come and go. Kept alive (not
/// autoDispose) — it's the app's central library feed, watched across screens.
final libraryItemsProvider = StreamProvider<List<LibraryItem>>(
  (ref) => getIt<LibraryRepository>().watchPresent(),
);

/// Live Continue Watching feed (in-progress, present titles, newest first).
final continueWatchingProvider = StreamProvider<List<ContinueWatchingEntry>>(
  (ref) => getIt<WatchHistoryRepository>().watchContinueWatching(),
);

/// Live "Recently Downloaded" feed: app-acquired titles, one entry per show,
/// most-recently-downloaded first — for the landing rail of the same name.
final recentlyDownloadedProvider = StreamProvider<List<LibraryItem>>(
  (ref) => getIt<LibraryRepository>().watchRecentlyDownloaded(),
);
