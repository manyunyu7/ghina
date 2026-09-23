import 'package:flutter/material.dart';

/// A chunky color: a bright [base] face, a darker [edge] used for the
/// "3D" bottom border, a pale [light] tint for soft backgrounds and the
/// readable foreground [on] that sits on top of [base].
///
/// ```dart
/// ChunkyButton(label: 'Simpan', color: GhinaColors.blue, onPressed: save);
/// ```
@immutable
class ChunkySwatch {
  const ChunkySwatch({
    required this.base,
    required this.edge,
    required this.light,
    this.on = Colors.white,
  });

  /// Builds a swatch from any color (e.g. a user-picked category color),
  /// deriving the edge and tint automatically.
  factory ChunkySwatch.fromColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final edge = hsl
        .withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0))
        .toColor();
    final light = Color.alphaBlend(color.withValues(alpha: 0.16), Colors.white);
    final on = color.computeLuminance() > 0.62
        ? const Color(0xFF3C3C3C)
        : Colors.white;
    return ChunkySwatch(base: color, edge: edge, light: light, on: on);
  }

  final Color base;
  final Color edge;
  final Color light;
  final Color on;

  /// Soft tint that works in both themes (pale in light, deep in dark).
  Color tint(Brightness brightness) => brightness == Brightness.dark
      ? Color.alphaBlend(base.withValues(alpha: 0.18), GhinaColors.darkSurface)
      : light;

  /// Border color for tinted surfaces ("selected answer" look).
  Color tintBorder(Brightness brightness) => brightness == Brightness.dark
      ? base.withValues(alpha: 0.7)
      : Color.lerp(light, base, 0.45)!;

  @override
  bool operator ==(Object other) =>
      other is ChunkySwatch && other.base == base && other.edge == edge;

  @override
  int get hashCode => Object.hash(base, edge);
}

/// Ghina's raw palette. Bright, saturated, each with a darker edge shade.
///
/// Prefer the semantic helpers ([income], [expense], [transfer], [warning])
/// and `context.ghina` (theme-aware neutrals) in screens.
abstract final class GhinaColors {
  // ---- Brand swatches -----------------------------------------------------
  /// Primary "leaf" green – main CTAs, success, income.
  static const green = ChunkySwatch(
    base: Color(0xFF58CC02),
    edge: Color(0xFF46A302),
    light: Color(0xFFD7FFB8),
  );

  /// Lighter green highlight (progress shine, mascot belly).
  static const lime = ChunkySwatch(
    base: Color(0xFF89E219),
    edge: Color(0xFF6CB514),
    light: Color(0xFFEAFBD3),
    on: Color(0xFF2F5F05),
  );

  /// Sky blue – secondary actions, selection, transfer, info.
  static const blue = ChunkySwatch(
    base: Color(0xFF1CB0F6),
    edge: Color(0xFF1899D6),
    light: Color(0xFFDDF4FF),
  );

  /// Cardinal red – expense, destructive, errors, hearts.
  static const red = ChunkySwatch(
    base: Color(0xFFFF4B4B),
    edge: Color(0xFFD93A3A),
    light: Color(0xFFFFDFE0),
  );

  /// Fox orange – streaks, warnings, energy.
  static const orange = ChunkySwatch(
    base: Color(0xFFFF9600),
    edge: Color(0xFFCD7900),
    light: Color(0xFFFFF0D5),
  );

  /// Bee yellow – XP, gold, celebrations.
  static const yellow = ChunkySwatch(
    base: Color(0xFFFFC800),
    edge: Color(0xFFE0A800),
    light: Color(0xFFFFF5D3),
    on: Color(0xFF6B4A00),
  );

  /// Grape purple – levels, premium, learning.
  static const purple = ChunkySwatch(
    base: Color(0xFFCE82FF),
    edge: Color(0xFFA568CC),
    light: Color(0xFFF3E1FF),
  );

  /// Bubblegum pink – cheeks, gifts, fun accents.
  static const pink = ChunkySwatch(
    base: Color(0xFFFF86D0),
    edge: Color(0xFFD663AB),
    light: Color(0xFFFFE3F4),
  );

  /// Neutral gray swatch (disabled / neutral buttons).
  static const gray = ChunkySwatch(
    base: Color(0xFFE5E5E5),
    edge: Color(0xFFCFCFCF),
    light: Color(0xFFF7F7F7),
    on: Color(0xFFAFAFAF),
  );

  /// All brand swatches, handy for pickers & demos.
  static const swatches = <ChunkySwatch>[
    green,
    blue,
    red,
    orange,
    yellow,
    purple,
    pink,
    lime,
  ];

  // ---- Neutrals (light) ---------------------------------------------------
  static const snow = Color(0xFFFFFFFF); // surfaces
  static const polar = Color(0xFFF7F7F7); // input fill, tracks
  static const swan = Color(0xFFE5E5E5); // borders
  static const swanEdge = Color(0xFFD5D5D5); // bottom edge of neutral cards
  static const hare = Color(0xFFAFAFAF); // muted text / disabled
  static const wolf = Color(0xFF777777); // secondary text
  static const eel = Color(0xFF4B4B4B); // primary text
  static const ink = Color(0xFF3C3C3C); // headline text

  // ---- Neutrals (dark: deep navy/charcoal) --------------------------------
  static const darkBackground = Color(0xFF131F24);
  static const darkSurface = Color(0xFF1A2A31);
  static const darkSurfaceAlt = Color(0xFF202F36);
  static const darkBorder = Color(0xFF37464F);
  static const darkBorderEdge = Color(0xFF2B3940);
  static const darkTextPrimary = Color(0xFFF1F7FB);
  static const darkTextSecondary = Color(0xFFA7B6BE);
  static const darkTextMuted = Color(0xFF52656D);

  // ---- Semantic -------------------------------------------------------------
  static const income = green;
  static const expense = red;
  static const transfer = blue;
  static const warning = orange;
  static const xp = yellow;
  static const streak = orange;
  static const heart = red;
  static const gem = blue;
  static const level = purple;

  /// Confetti / celebration colors.
  static const confetti = <Color>[
    Color(0xFF58CC02),
    Color(0xFF1CB0F6),
    Color(0xFFFFC800),
    Color(0xFFFF4B4B),
    Color(0xFFCE82FF),
    Color(0xFFFF9600),
    Color(0xFFFF86D0),
  ];
}

/// Helpers for user-chosen category / wallet colors (stored as hex strings
/// like `#f97316` – same palette as the web app).
abstract final class CategoryColors {
  /// The web's `COLOR_PALETTE` (src/lib/constants.ts), same order.
  static const palette = <String>[
    '#6366f1',
    '#8b5cf6',
    '#ec4899',
    '#ef4444',
    '#f97316',
    '#f59e0b',
    '#eab308',
    '#84cc16',
    '#22c55e',
    '#10b981',
    '#14b8a6',
    '#06b6d4',
    '#0ea5e9',
    '#3b82f6',
    '#64748b',
  ];

  /// Fallback when a hex string is missing or malformed.
  static const fallback = Color(0xFF64748B);

  /// Parses `#rgb`, `#rrggbb` or `#aarrggbb` (with or without `#`).
  static Color parse(String? hex, {Color fallback = CategoryColors.fallback}) {
    if (hex == null) return fallback;
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  /// `Color` -> `#rrggbb` (lowercase, like the web).
  static String toHex(Color c) {
    String two(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${two(c.r)}${two(c.g)}${two(c.b)}';
  }

  /// A full chunky swatch for a hex color (face, edge, tint).
  static ChunkySwatch swatch(String? hex) => ChunkySwatch.fromColor(parse(hex));

  /// Deterministic color for things without a stored color (e.g. by name).
  static Color forKey(String key) {
    final i = key.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return parse(palette[i % palette.length]);
  }
}
