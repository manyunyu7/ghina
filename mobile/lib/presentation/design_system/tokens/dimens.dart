import 'package:flutter/widgets.dart';

/// Spacing scale (4pt grid). Be generous – Ghina breathes.
abstract final class GhinaSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Default horizontal page padding.
  static const double page = 20;
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: page);

  /// Vertical gaps as widgets: `GhinaSpace.gapLg`.
  static const gapXs = SizedBox(width: xs, height: xs);
  static const gapSm = SizedBox(width: sm, height: sm);
  static const gapMd = SizedBox(width: md, height: md);
  static const gapLg = SizedBox(width: lg, height: lg);
  static const gapXl = SizedBox(width: xl, height: xl);
  static const gapXxl = SizedBox(width: xxl, height: xxl);
}

/// Corner radii. Everything is rounded; nothing is sharp.
abstract final class GhinaRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double pill = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}

/// "Elevation" in Ghina is a solid darker bottom edge, not a blur shadow.
abstract final class GhinaDepth {
  /// Chips, small keys.
  static const double sm = 3;

  /// Cards, tiles, text buttons.
  static const double md = 4;

  /// Big CTAs, path nodes.
  static const double lg = 6;

  /// Neutral border width used on cards / inputs.
  static const double border = 2;
}

/// Motion tokens. Snappy presses, bouncy entrances.
abstract final class GhinaMotion {
  static const press = Duration(milliseconds: 70);
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 500);
  static const progress = Duration(milliseconds: 800);
  static const countUp = Duration(milliseconds: 900);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve bounce = Curves.elasticOut;
  static const Curve pop = Cubic(0.34, 1.56, 0.64, 1); // easeOutBack-ish
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
}
