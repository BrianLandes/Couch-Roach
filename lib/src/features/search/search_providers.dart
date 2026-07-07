import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/acquisition/archive_browse_service.dart';

/// Internet Archive search results for a query, for the search results screen.
/// Keyed by the query string so results are cached per search. Empty on failure
/// or an empty query.
final searchResultsProvider =
    FutureProvider.family<List<ArchiveItem>, String>(
  (ref, query) => getIt<ArchiveBrowseService>().search(query),
);
