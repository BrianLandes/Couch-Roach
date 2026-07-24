import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../../injection.dart';

/// Live Favorites list (newest-favorited first) for the landing rail.
final favoritesProvider = StreamProvider<List<SavedTitle>>(
  (ref) => getIt<SavedTitlesRepository>().watchFavorites(),
);

/// Live Want-to-watch list (newest-added first) for the landing rail.
final wantToWatchProvider = StreamProvider<List<SavedTitle>>(
  (ref) => getIt<SavedTitlesRepository>().watchWantToWatch(),
);

/// Live saved-state (favorite / want-to-watch flags) for one TMDB title, so a
/// detail page's toggle buttons reflect and update the current state.
final savedTitleProvider =
    StreamProvider.family<SavedTitle?, ({int tmdbId, String mediaType})>(
  (ref, key) => getIt<SavedTitlesRepository>()
      .watchTitle(tmdbId: key.tmdbId, mediaType: key.mediaType),
);

/// Live set of "not interested" titles, keyed `'<mediaType>:<tmdbId>'` — the
/// landing rails subtract these from their discovery tiles.
final notInterestedProvider = StreamProvider<Set<String>>(
  (ref) => getIt<SavedTitlesRepository>().watchNotInterested(),
);

/// The key a [DiscoverTile]-like title matches against [notInterestedProvider].
String notInterestedKey(int tmdbId, String mediaType) => '$mediaType:$tmdbId';

/// Live "not interested" titles (newest-flagged first) for the Settings surface
/// that lets the user un-hide them.
final notInterestedTitlesProvider = StreamProvider<List<SavedTitle>>(
  (ref) => getIt<SavedTitlesRepository>().watchNotInterestedTitles(),
);
