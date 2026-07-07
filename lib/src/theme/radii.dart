import 'package:flutter/widgets.dart';

/// Corner radii. Liquid glass leans generous and soft — panels are pill-ish,
/// never sharp. See docs/STYLE.md.
abstract final class AppRadii {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 30;
  static const double pill = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}
