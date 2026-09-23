import 'package:flutter/material.dart';

import '../icons/ghina_icons.dart';
import '../theme/ghina_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_surface.dart';

/// Grid of chunky icon keys for picking a category/wallet icon. Works with
/// icon *names* (what the server stores); see [GhinaIcons].
///
/// ```dart
/// IconGridPicker(
///   selected: form.icon,                       // e.g. 'utensils'
///   color: CategoryColors.parse(form.color),   // selected tint
///   onChanged: (name) => setState(() => form.icon = name),
/// );
/// ```
///
/// It is a non-scrolling grid ([shrinkWrap]) – put it inside your page scroll.
class IconGridPicker extends StatelessWidget {
  const IconGridPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.icons = GhinaIcons.categoryNames,
    this.color,
    this.crossAxisCount = 6,
  });

  final String? selected;
  final ValueChanged<String> onChanged;
  final List<String> icons;

  /// Color used for the selected key (defaults to blue).
  final Color? color;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = ChunkySwatch.fromColor(color ?? GhinaColors.blue.base);
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      padding: EdgeInsets.zero,
      children: [
        for (final name in icons)
          _key(
            g: g,
            selected: name == selected,
            sw: sw,
            onTap: () => onChanged(name),
            label: name,
            icon: GhinaIcons.of(name),
          ),
      ],
    );
  }

  Widget _key({
    required GhinaTokens g,
    required bool selected,
    required ChunkySwatch sw,
    required VoidCallback onTap,
    required String label,
    required IconData icon,
  }) {
    return ChunkySurface(
      color: selected ? sw.base : g.surface,
      edgeColor: selected ? sw.edge : g.borderEdge,
      borderColor: selected ? null : g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rMd,
      onTap: onTap,
      semanticLabel: label,
      child: Center(
        child: Icon(icon, size: 24, color: selected ? sw.on : g.textSecondary),
      ),
    );
  }
}

/// Row/wrap of round chunky color dots. Works with hex strings (the web
/// format, e.g. `#f97316`), defaulting to the web palette.
///
/// ```dart
/// ChunkyColorPicker(
///   selected: form.color,
///   onChanged: (hex) => setState(() => form.color = hex),
/// );
/// ```
class ChunkyColorPicker extends StatelessWidget {
  const ChunkyColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.palette = CategoryColors.palette,
    this.size = 44,
  });

  final String? selected;
  final ValueChanged<String> onChanged;
  final List<String> palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sel = selected?.toLowerCase();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in palette)
          Builder(
            builder: (context) {
              final sw = CategoryColors.swatch(hex);
              final isSel = hex.toLowerCase() == sel;
              return AnimatedContainer(
                duration: GhinaMotion.fast,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSel ? sw.base : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: ChunkySurface(
                  color: sw.base,
                  edgeColor: sw.edge,
                  depth: GhinaDepth.sm,
                  borderRadius: BorderRadius.circular(size),
                  onTap: () => onChanged(hex),
                  semanticLabel: 'Warna $hex',
                  child: SizedBox(
                    width: size - 6,
                    height: size - 6,
                    child: AnimatedScale(
                      duration: GhinaMotion.fast,
                      curve: GhinaMotion.pop,
                      scale: isSel ? 1 : 0,
                      child: Icon(Icons.check_rounded, color: sw.on, size: 22),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
