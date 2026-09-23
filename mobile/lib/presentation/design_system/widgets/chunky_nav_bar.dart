import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_surface.dart';

/// A tab in [ChunkyNavBar].
class ChunkyNavItem {
  const ChunkyNavItem({
    required this.icon,
    required this.label,
    this.activeIcon,
    this.color,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;

  /// Active color (defaults to blue).
  final ChunkySwatch? color;
}

/// Bottom navigation with 4 tabs and a big raised center "+" button between
/// tab 2 and 3. The active tab gets a tinted rounded box, Duolingo-style.
///
/// ```dart
/// ChunkyNavBar(
///   currentIndex: shell.currentIndex,
///   onTap: shell.goBranch,
///   onCenterTap: () => showQuickAdd(context),
///   items: const [
///     ChunkyNavItem(icon: Icons.home_rounded, label: 'Beranda'),
///     ChunkyNavItem(icon: Icons.receipt_long_rounded, label: 'Transaksi'),
///     ChunkyNavItem(icon: Icons.school_rounded, label: 'Belajar'),
///     ChunkyNavItem(icon: Icons.person_rounded, label: 'Profil'),
///   ],
/// );
/// ```
/// Use it as `Scaffold.bottomNavigationBar`. It handles the bottom safe area.
class ChunkyNavBar extends StatelessWidget {
  const ChunkyNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.onCenterTap,
    this.centerIcon = Icons.add_rounded,
    this.centerLabel = 'Tambah transaksi',
    this.showLabels = true,
  }) : assert(items.length == 4, 'ChunkyNavBar expects 4 tabs');

  final List<ChunkyNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Null hides the center button.
  final VoidCallback? onCenterTap;
  final IconData centerIcon;
  final String centerLabel;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget tab(int i) => Expanded(
      child: _NavTab(
        item: items[i],
        selected: i == currentIndex,
        showLabel: showLabels,
        onTap: () {
          if (i != currentIndex) HapticFeedback.selectionClick();
          onTap(i);
        },
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.background,
        border: Border(top: BorderSide(color: g.border, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: showLabels ? 70 : 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 6),
              tab(0),
              tab(1),
              if (onCenterTap != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Transform.translate(
                    offset: const Offset(0, -14),
                    child: ChunkySurface(
                      color: GhinaColors.green.base,
                      edgeColor: GhinaColors.green.edge,
                      depth: GhinaDepth.lg,
                      borderRadius: GhinaRadii.rXl,
                      semanticLabel: centerLabel,
                      onTap: onCenterTap,
                      child: SizedBox(
                        width: 62,
                        height: 58,
                        child: Icon(centerIcon, color: Colors.white, size: 38),
                      ),
                    ),
                  ),
                ),
              tab(2),
              tab(3),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.showLabel,
  });

  final ChunkyNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = item.color ?? GhinaColors.blue;
    final fg = selected ? sw.base : g.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: GhinaMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? sw.tint(g.brightness) : Colors.transparent,
              borderRadius: GhinaRadii.rMd,
              border: Border.all(
                color: selected
                    ? sw.tintBorder(g.brightness)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: GhinaMotion.medium,
                  curve: GhinaMotion.pop,
                  scale: selected ? 1.12 : 1,
                  child: Icon(
                    selected ? (item.activeIcon ?? item.icon) : item.icon,
                    color: fg,
                    size: 26,
                  ),
                ),
                if (showLabel)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      style: GhinaType.caption
                          .w(900)
                          .copyWith(color: fg, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
