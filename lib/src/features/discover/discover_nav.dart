import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import 'discover_tile.dart';
import 'show_detail_screen.dart';

/// Open the right detail page for a [DiscoverTile]: TV → the show detail
/// (seasons/episodes), movie → the movie detail. Shared by the discovery rails
/// and the search screen so tap behavior is uniform.
void openDiscoverTile(BuildContext context, DiscoverTile tile) {
  if (tile.isTv) {
    openShowDetail(context, tmdbId: tile.tmdbId, name: tile.title);
  } else {
    context.push(Routes.movieDetail, extra: tile);
  }
}

/// Open the show detail page (seasons/episodes with local availability). Shared
/// by the discovery rails and the grouped-show tiles in the library grid.
void openShowDetail(BuildContext context,
    {required int tmdbId, required String name}) {
  context.push(
    Routes.showDetail,
    extra: ShowDetailArgs(tmdbId: tmdbId, name: name),
  );
}
