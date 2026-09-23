import 'package:flutter/material.dart';

/// Nunito typography. Nunito is bundled as a *variable* font, so every style
/// sets both [FontWeight] and a matching `wght` [FontVariation] – otherwise
/// some engines render everything at the default weight.
///
/// When you change the weight of a style, use [TextStyleWeight.w] instead of
/// `copyWith(fontWeight: ...)`:
///
/// ```dart
/// Text('Halo', style: GhinaType.body.w(800));
/// ```
abstract final class GhinaType {
  static const String family = 'Nunito';

  /// Creates a Nunito style with the variable weight axis set correctly.
  static TextStyle nunito(
    double size, {
    int weight = 700,
    Color? color,
    double? height,
    double? letterSpacing,
    List<FontFeature>? features,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: _fw(weight),
      fontVariations: [FontVariation('wght', weight.toDouble())],
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: features,
    );
  }

  static FontWeight _fw(int w) {
    final i = ((w.clamp(100, 900) / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[i];
  }

  static const _tabular = [FontFeature.tabularFigures()];

  // ---- Money / display numbers (tabular figures) ---------------------------
  /// Hero balance, amount entry. 44/900.
  static final moneyXL = nunito(
    44,
    weight: 900,
    height: 1.05,
    letterSpacing: -1,
    features: _tabular,
  );

  /// Card totals. 30/900.
  static final moneyL = nunito(
    30,
    weight: 900,
    height: 1.1,
    letterSpacing: -0.5,
    features: _tabular,
  );

  /// List amounts. 17/800.
  static final moneyM = nunito(
    17,
    weight: 800,
    height: 1.2,
    features: _tabular,
  );

  /// Small amounts in captions. 13/800.
  static final moneyS = nunito(
    13,
    weight: 800,
    height: 1.2,
    features: _tabular,
  );

  // ---- Headings -------------------------------------------------------------
  /// Celebration titles ("Mantap!"). 36/900.
  static final display = nunito(
    36,
    weight: 900,
    height: 1.1,
    letterSpacing: -0.5,
  );

  /// Screen titles. 26/900.
  static final h1 = nunito(26, weight: 900, height: 1.2, letterSpacing: -0.3);

  /// Section / card titles. 20/800.
  static final h2 = nunito(20, weight: 800, height: 1.25);

  /// Tile titles. 17/800.
  static final h3 = nunito(17, weight: 800, height: 1.3);

  // ---- Body -----------------------------------------------------------------
  static final bodyL = nunito(17, weight: 600, height: 1.45);
  static final body = nunito(15, weight: 600, height: 1.45);
  static final bodyS = nunito(13, weight: 600, height: 1.4);

  /// Small labels, timestamps. 12/700.
  static final caption = nunito(12, weight: 700, height: 1.3);

  /// ALL-CAPS tracking label ("TOTAL XP", section overlines). 13/800.
  static final overline = nunito(
    13,
    weight: 800,
    height: 1.2,
    letterSpacing: 1.1,
  );

  /// Button label (apply `.toUpperCase()` to text – Duolingo-style caps). 15/800.
  static final button = nunito(
    15,
    weight: 800,
    height: 1.1,
    letterSpacing: 0.8,
  );

  /// Material [TextTheme] mapping, colored for a brightness.
  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: moneyXL.copyWith(color: primary),
      displayMedium: display.copyWith(color: primary),
      displaySmall: moneyL.copyWith(color: primary),
      headlineLarge: h1.copyWith(color: primary),
      headlineMedium: h1.copyWith(color: primary, fontSize: 24),
      headlineSmall: h2.copyWith(color: primary),
      titleLarge: h2.copyWith(color: primary),
      titleMedium: h3.copyWith(color: primary),
      titleSmall: body.w(800).copyWith(color: primary),
      bodyLarge: bodyL.copyWith(color: primary),
      bodyMedium: body.copyWith(color: primary),
      bodySmall: bodyS.copyWith(color: secondary),
      labelLarge: button.copyWith(color: primary),
      labelMedium: caption.copyWith(color: secondary),
      labelSmall: overline.copyWith(color: secondary, fontSize: 11),
    );
  }
}

/// Weight helper that keeps the variable-font axis in sync.
extension TextStyleWeight on TextStyle {
  /// Returns this style at [weight] (100–1000), e.g. `GhinaType.body.w(800)`.
  TextStyle w(int weight) => copyWith(
    fontWeight: GhinaType._fw(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
  );
}
