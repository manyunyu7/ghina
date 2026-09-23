import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// Theme-aware neutrals & semantic colors. Read with `context.ghina`.
///
/// ```dart
/// final g = context.ghina;
/// Container(color: g.surface, child: Text('Hai', style: TextStyle(color: g.textPrimary)));
/// ```
@immutable
class GhinaTokens extends ThemeExtension<GhinaTokens> {
  const GhinaTokens({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderEdge,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.skeleton,
    required this.skeletonHighlight,
    required this.disabled,
    required this.disabledEdge,
    required this.onDisabled,
  });

  static const light = GhinaTokens(
    brightness: Brightness.light,
    background: GhinaColors.snow,
    surface: GhinaColors.snow,
    surfaceAlt: GhinaColors.polar,
    border: GhinaColors.swan,
    borderEdge: GhinaColors.swanEdge,
    textPrimary: GhinaColors.ink,
    textSecondary: GhinaColors.wolf,
    textMuted: GhinaColors.hare,
    skeleton: Color(0xFFEDEDED),
    skeletonHighlight: Color(0xFFF9F9F9),
    disabled: GhinaColors.swan,
    disabledEdge: GhinaColors.swanEdge,
    onDisabled: GhinaColors.hare,
  );

  static const dark = GhinaTokens(
    brightness: Brightness.dark,
    background: GhinaColors.darkBackground,
    surface: GhinaColors.darkBackground,
    surfaceAlt: GhinaColors.darkSurface,
    border: GhinaColors.darkBorder,
    borderEdge: GhinaColors.darkBorder,
    textPrimary: GhinaColors.darkTextPrimary,
    textSecondary: GhinaColors.darkTextSecondary,
    textMuted: GhinaColors.darkTextMuted,
    skeleton: Color(0xFF22323A),
    skeletonHighlight: Color(0xFF2E4049),
    disabled: GhinaColors.darkBorder,
    disabledEdge: GhinaColors.darkBorderEdge,
    onDisabled: GhinaColors.darkTextMuted,
  );

  final Brightness brightness;

  /// Page background.
  final Color background;

  /// Card face.
  final Color surface;

  /// Input fills, progress tracks, subtle panels.
  final Color surfaceAlt;

  /// 2px card / input border.
  final Color border;

  /// Bottom "3D" edge for neutral cards.
  final Color borderEdge;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color skeleton;
  final Color skeletonHighlight;
  final Color disabled;
  final Color disabledEdge;
  final Color onDisabled;

  bool get isDark => brightness == Brightness.dark;

  Color get income => GhinaColors.income.base;
  Color get expense => GhinaColors.expense.base;
  Color get transfer => GhinaColors.transfer.base;
  Color get warning => GhinaColors.warning.base;

  /// Theme-aware pale tint of a swatch.
  Color tint(ChunkySwatch s) => s.tint(brightness);

  @override
  GhinaTokens copyWith({Color? background, Color? surface}) => GhinaTokens(
    brightness: brightness,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt,
    border: border,
    borderEdge: borderEdge,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textMuted: textMuted,
    skeleton: skeleton,
    skeletonHighlight: skeletonHighlight,
    disabled: disabled,
    disabledEdge: disabledEdge,
    onDisabled: onDisabled,
  );

  @override
  GhinaTokens lerp(GhinaTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GhinaTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      borderEdge: l(borderEdge, other.borderEdge),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      skeleton: l(skeleton, other.skeleton),
      skeletonHighlight: l(skeletonHighlight, other.skeletonHighlight),
      disabled: l(disabled, other.disabled),
      disabledEdge: l(disabledEdge, other.disabledEdge),
      onDisabled: l(onDisabled, other.onDisabled),
    );
  }
}

/// `context.ghina` – quick access to [GhinaTokens] (falls back to light).
extension GhinaContext on BuildContext {
  GhinaTokens get ghina =>
      Theme.of(this).extension<GhinaTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? GhinaTokens.dark
          : GhinaTokens.light);
}
