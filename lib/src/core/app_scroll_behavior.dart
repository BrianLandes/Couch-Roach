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
}
