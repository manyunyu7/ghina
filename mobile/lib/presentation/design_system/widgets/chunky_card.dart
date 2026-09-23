import 'package:flutter/material.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_surface.dart';

/// Bordered card with a solid bottom edge. Pass [onTap] for the press effect.
///
/// ```dart
/// ChunkyCard(child: Text('Saldo'));                         // neutral
/// ChunkyCard(color: GhinaColors.blue, child: ...);          // solid colored
/// ChunkyCard(tinted: GhinaColors.green, onTap: open, ...);  // pale tint + colored border
/// ```
class ChunkyCard extends StatelessWidget {
  const ChunkyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(GhinaSpace.lg),
    this.onTap,
    this.onLongPress,
    this.color,
    this.tinted,
    this.depth = GhinaDepth.md,
    this.borderRadius = GhinaRadii.rXl,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Solid colored card (white text recommended).
  final ChunkySwatch? color;

  /// Pale tinted card with a colored border (selected / highlighted).
  final ChunkySwatch? tinted;
  final double depth;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final Color face, edge;
    Color? border;
    if (color != null) {
      face = color!.base;
      edge = color!.edge;
    } else if (tinted != null) {
      face = tinted!.tint(g.brightness);
      border = tinted!.tintBorder(g.brightness);
      edge = border;
    } else {
      face = g.surface;
      border = g.border;
      edge = g.borderEdge;
    }
    return ChunkySurface(
      color: face,
      edgeColor: edge,
      borderColor: border,
      depth: depth,
      borderRadius: borderRadius,
      padding: padding,
      onTap: onTap,
      onLongPress: onLongPress,
      isButton: onTap != null,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

/// A list row inside a chunky card: leading visual, title/subtitle, trailing.
/// Set [framed] to `false` for a flat row (inside a grouped card or list).
///
/// ```dart
/// ChunkyTile(
///   leading: CategoryAvatar(iconName: 'utensils', colorHex: '#f97316'),
///   title: 'Makan siang',
///   subtitle: 'Dompet · 12:30',
///   trailing: MoneyText(amount: -25000),
///   onTap: () => context.push('/transactions/$id'),
/// );
/// ```
class ChunkyTile extends StatelessWidget {
  const ChunkyTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.framed = true,
    this.showChevron = false,
    this.tinted,
    this.titleWidget,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool framed;
  final bool showChevron;
  final ChunkySwatch? tinted;

  /// Replaces the title text (e.g. title + pill).
  final Widget? titleWidget;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final row = Row(
      children: [
        if (leading != null) ...[leading!, SizedBox(width: dense ? 10 : 14)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleWidget ??
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (dense ? GhinaType.body.w(800) : GhinaType.h3)
                        .copyWith(color: g.textPrimary),
                  ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        if (showChevron) ...[
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: g.textMuted, size: 26),
        ],
      ],
    );

    final pad = EdgeInsets.symmetric(
      horizontal: framed ? GhinaSpace.lg : GhinaSpace.xs,
      vertical: dense ? 10 : 14,
    );

    if (framed) {
      return ChunkyCard(
        padding: pad,
        tinted: tinted,
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: GhinaRadii.rLg,
        semanticLabel: title,
        child: row,
      );
    }
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: GhinaRadii.rLg,
        child: Padding(padding: pad, child: row),
      ),
    );
  }
}

/// Compact stat card: colored icon, big value, caption label.
/// Profile / home stats ("12 hari streak", "Level 4").
///
/// ```dart
/// StatTile(icon: Icons.local_fire_department_rounded, color: GhinaColors.orange,
///          value: '12', label: 'Hari streak');
/// ```
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = GhinaColors.blue,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final ChunkySwatch color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: GhinaRadii.rLg,
      child: Row(
        children: [
          Icon(icon, color: color.base, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small rounded label pill ("BARU", "LUNAS", "-20%").
///
/// ```dart
/// ChunkyPill(label: 'Baru', color: GhinaColors.purple);
/// ChunkyPill(label: 'Lunas', color: GhinaColors.green, soft: true, icon: Icons.check_rounded);
/// ```
class ChunkyPill extends StatelessWidget {
  const ChunkyPill({
    super.key,
    required this.label,
    this.color = GhinaColors.blue,
    this.soft = false,
    this.icon,
    this.uppercase = true,
  });

  final String label;
  final ChunkySwatch color;

  /// Pale background + colored text instead of solid.
  final bool soft;
  final IconData? icon;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final bg = soft ? color.tint(g.brightness) : color.base;
    final fg = soft ? (g.isDark ? color.base : color.edge) : color.on;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: GhinaRadii.rSm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            uppercase ? label.toUpperCase() : label,
            style: GhinaType.caption
                .w(900)
                .copyWith(color: fg, letterSpacing: 0.6, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
