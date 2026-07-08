import '../../data/db/database.dart';

/// One cell in the library grid: either a standalone [ItemEntry] (a movie or a
/// loose/unmatched file) or a [ShowEntry] collapsing all downloaded episodes of
/// one matched TV show into a single tile.
sealed class LibraryEntry {
  const LibraryEntry();
}

class ItemEntry extends LibraryEntry {
  const ItemEntry(this.item);
  final LibraryItem item;
}

class ShowEntry extends LibraryEntry {
  const ShowEntry({
    required this.tmdbId,
    required this.name,
    required this.posterPath,
    required this.episodeCount,
  });
  final int tmdbId;
  final String name;
  final String? posterPath;
  final int episodeCount;
}

/// Collapse a flat library list so a matched TV show (mediaType `tv` with a
/// `tmdbId`) shows as a single [ShowEntry] instead of one tile per episode;
/// everything else (movies, unmatched files) stays its own [ItemEntry]. Order
/// follows each show's first-seen position so the grid stays stable as episodes
/// come and go. Pure + tested.
List<LibraryEntry> groupLibraryItems(List<LibraryItem> items) {
  final byShow = <int, List<LibraryItem>>{};
  for (final item in items) {
    if (item.mediaType == 'tv' && item.tmdbId != null) {
      byShow.putIfAbsent(item.tmdbId!, () => []).add(item);
    }
  }

  final emitted = <int>{};
  final entries = <LibraryEntry>[];
  for (final item in items) {
    final id = item.tmdbId;
    if (item.mediaType == 'tv' && id != null) {
      if (emitted.add(id)) {
        final eps = byShow[id]!;
        final poster = eps
            .map((e) => e.tmdbPosterPath)
            .firstWhere((p) => p != null, orElse: () => null);
        final name = eps
                .map((e) => e.tmdbName)
                .firstWhere((n) => n != null, orElse: () => null) ??
            item.title;
        entries.add(ShowEntry(
          tmdbId: id,
          name: name,
          posterPath: poster,
          episodeCount: eps.length,
        ));
      }
    } else {
      entries.add(ItemEntry(item));
    }
  }
  return entries;
}
