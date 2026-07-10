import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// App-wide scroll behavior that lets the **mouse** (and trackpad/stylus) drag
/// scrollables, not just touch. Flutter desktop disables pointer-drag scrolling
/// by default, which leaves the horizontal tile rails unreachable with a mouse:
/// the vertical scroll wheel doesn't move a horizontal list, and there's no
/// drag. With this, the cursor can grab a rail and fling it sideways to view the
/// tiles that run off-screen. (The remote already scrolls rails via
/// focus-follows-scroll — see FocusableCard.)
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Keep the main *vertical* page scrollbar always visible (and thus always
    // grabbable), styled by the app's ScrollbarThemeData. The horizontal tile
    // rails keep the default auto-hide so they don't clutter the landing page
    // with a scrollbar under every row. thumbVisibility needs a live
    // ScrollController, so only force it where one is attached.
    final vertical = details.direction == AxisDirection.down ||
        details.direction == AxisDirection.up;
    if (vertical) {
      return Scrollbar(
        controller: details.controller,
        thumbVisibility: details.controller != null,
        child: child,
      );
    }
    return super.buildScrollbar(context, child, details);
  }
}
