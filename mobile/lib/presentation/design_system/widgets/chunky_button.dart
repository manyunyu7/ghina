import 'package:flutter/material.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_surface.dart';

enum ChunkyButtonVariant {
  /// Solid green CTA ("LANJUT", "SIMPAN"). One per screen.
  primary,

  /// Solid blue – secondary positive action.
  secondary,

  /// White/surface with gray border – neutral action ("NANTI SAJA").
  outline,

  /// Solid red – destructive ("HAPUS").
  danger,

  /// No surface, blue caps text – tertiary / "Lewati".
  ghost,
}

enum ChunkyButtonSize {
  /// 36px – inline actions in cards.
  small,

  /// 46px – secondary buttons.
  medium,

  /// 54px – main CTAs at the bottom of a screen.
  large,
}

/// Duolingo-style chunky button with a darker bottom edge that sinks on tap
/// (with a light haptic). Labels render in CAPS.
///
/// ```dart
/// ChunkyButton(label: 'Simpan', icon: Icons.check_rounded, onPressed: save);
/// ChunkyButton(label: 'Hapus', variant: ChunkyButtonVariant.danger, onPressed: del);
/// ChunkyButton(label: 'Lewati', variant: ChunkyButtonVariant.ghost, onPressed: skip);
/// ChunkyButton(label: 'Menyimpan', loading: true, onPressed: null);
/// ChunkyButton(label: 'Bonus', color: GhinaColors.yellow, onPressed: claim); // custom swatch
/// ```
///
/// `onPressed == null` renders the disabled (gray) state. [expand] makes it
/// fill the available width (default for [ChunkyButtonSize.large]).
class ChunkyButton extends StatelessWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ChunkyButtonVariant.primary,
    this.size = ChunkyButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand,
    this.color,
    this.uppercase = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final ChunkyButtonVariant variant;
  final ChunkyButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Shows a spinner and blocks taps.
  final bool loading;

  /// Stretch to full width. Defaults to `true` for large buttons.
  final bool? expand;

  /// Override the swatch for solid variants (e.g. `GhinaColors.yellow`).
  final ChunkySwatch? color;
  final bool uppercase;

  double get _height => switch (size) {
    ChunkyButtonSize.small => 36,
    ChunkyButtonSize.medium => 46,
    ChunkyButtonSize.large => 54,
  };

  double get _depth => switch (size) {
    ChunkyButtonSize.small => 3,
    ChunkyButtonSize.medium => 4,
    ChunkyButtonSize.large => 5,
  };

  double get _fontSize => switch (size) {
    ChunkyButtonSize.small => 13,
    ChunkyButtonSize.medium => 15,
    ChunkyButtonSize.large => 16,
  };

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final enabled = onPressed != null && !loading;
    final expanded = expand ?? size == ChunkyButtonSize.large;

    late Color face, edge, fg;
    Color? border;
    switch (variant) {
      case ChunkyButtonVariant.primary:
      case ChunkyButtonVariant.secondary:
      case ChunkyButtonVariant.danger:
        final s =
            color ??
            switch (variant) {
              ChunkyButtonVariant.secondary => GhinaColors.blue,
              ChunkyButtonVariant.danger => GhinaColors.red,
              _ => GhinaColors.green,
            };
        face = s.base;
        edge = s.edge;
        fg = s.on;
      case ChunkyButtonVariant.outline:
        face = g.surface;
        edge = g.border;
        border = g.border;
        fg = color?.base ?? (g.isDark ? g.textPrimary : GhinaColors.blue.base);
      case ChunkyButtonVariant.ghost:
        face = Colors.transparent;
        edge = Colors.transparent;
        fg = color?.base ?? GhinaColors.blue.base;
    }

    if (!enabled && !loading) {
      if (variant == ChunkyButtonVariant.ghost) {
        fg = g.textMuted;
      } else {
        face = g.disabled;
        edge = g.disabledEdge;
        border = null;
        fg = g.onDisabled;
      }
    }

    final style = GhinaType.button.copyWith(fontSize: _fontSize, color: fg);
    final iconSize = _fontSize + 6;
    final text = uppercase ? label.toUpperCase() : label;

    final content = loading
        ? SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              color: fg,
              backgroundColor: fg.withValues(alpha: 0.25),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: iconSize, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  text,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: iconSize, color: fg),
              ],
            ],
          );

    final hPad = switch (size) {
      ChunkyButtonSize.small => 14.0,
      ChunkyButtonSize.medium => 18.0,
      ChunkyButtonSize.large => 24.0,
    };

    final isGhost = variant == ChunkyButtonVariant.ghost;
    return ChunkySurface(
      color: face,
      edgeColor: edge,
      borderColor: border,
      depth: isGhost ? 0 : _depth,
      borderRadius: size == ChunkyButtonSize.small
          ? GhinaRadii.rMd
          : GhinaRadii.rLg,
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      semanticLabel: label,
      child: SizedBox(
        height: _height,
        width: expanded ? double.infinity : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Center(widthFactor: 1, child: content),
        ),
      ),
    );
  }
}

/// Square chunky icon button (close, back, settings, +/-).
///
/// ```dart
/// ChunkyIconButton(icon: Icons.close_rounded, onPressed: () => Navigator.pop(context));
/// ChunkyIconButton(icon: Icons.add_rounded, color: GhinaColors.green, onPressed: add);
/// ```
class ChunkyIconButton extends StatelessWidget {
  const ChunkyIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.size = 44,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Solid swatch; null = neutral outlined.
  final ChunkySwatch? color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final enabled = onPressed != null;
    final s = color;
    final face = !enabled ? g.disabled : (s?.base ?? g.surface);
    final edge = !enabled ? g.disabledEdge : (s?.edge ?? g.border);
    final fg = !enabled ? g.onDisabled : (s?.on ?? g.textSecondary);
    Widget w = ChunkySurface(
      color: face,
      edgeColor: edge,
      borderColor: s == null && enabled ? g.border : null,
      depth: GhinaDepth.sm,
      borderRadius: BorderRadius.circular(size * 0.3),
      onTap: onPressed,
      semanticLabel: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: fg, size: size * 0.55),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}
