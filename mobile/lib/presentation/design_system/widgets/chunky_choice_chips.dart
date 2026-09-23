import 'package:flutter/material.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_surface.dart';

/// One option for [ChunkyChoiceChips].
class ChunkyChoice<T> {
  const ChunkyChoice({
    required this.value,
    required this.label,
    this.icon,
    this.color,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Selected color (defaults to blue).
  final ChunkySwatch? color;
}

/// Wrap of chunky chips. Single-select by default; set [multi] for
/// multi-select. Selected chips get the tinted "selected answer" look.
///
/// ```dart
/// ChunkyChoiceChips<String>(
///   options: const [
///     ChunkyChoice(value: 'all', label: 'Semua'),
///     ChunkyChoice(value: 'expense', label: 'Keluar', icon: Icons.south_west_rounded),
///   ],
///   selected: {filter},
///   onChanged: (s) => setState(() => filter = s.first),
/// );
/// ```
class ChunkyChoiceChips<T> extends StatelessWidget {
  const ChunkyChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multi = false,
    this.allowEmpty = false,
    this.scrollable = false,
  });

  final List<ChunkyChoice<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool multi;

  /// Allow deselecting the last selected chip.
  final bool allowEmpty;

  /// One horizontally scrolling row instead of a wrap (filters bar).
  final bool scrollable;

  void _toggle(T v) {
    final next = {...selected};
    if (multi) {
      if (!next.remove(v)) next.add(v);
    } else {
      if (next.contains(v)) {
        next.clear();
      } else {
        next
          ..clear()
          ..add(v);
      }
    }
    if (next.isEmpty && !allowEmpty) return;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final o in options)
        ChunkyChip(
          label: o.label,
          icon: o.icon,
          color: o.color ?? GhinaColors.blue,
          selected: selected.contains(o.value),
          onTap: () => _toggle(o.value),
        ),
    ];
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final c in chips)
              Padding(padding: const EdgeInsets.only(right: 8), child: c),
          ],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

/// A single chunky chip (see [ChunkyChoiceChips]).
class ChunkyChip extends StatelessWidget {
  const ChunkyChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color = GhinaColors.blue,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final b = g.brightness;
    final fg = selected ? color.base : g.textSecondary;
    return AnimatedScale(
      scale: selected ? 1.0 : 0.98,
      duration: GhinaMotion.fast,
      child: ChunkySurface(
        color: selected ? color.tint(b) : g.surface,
        edgeColor: selected ? color.tintBorder(b) : g.borderEdge,
        borderColor: selected ? color.tintBorder(b) : g.border,
        depth: GhinaDepth.sm,
        borderRadius: GhinaRadii.rMd,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        onTap: onTap,
        semanticLabel: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label, style: GhinaType.body.w(800).copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
