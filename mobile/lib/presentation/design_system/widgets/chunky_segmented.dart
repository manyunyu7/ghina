import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// One segment of a [ChunkySegmented].
class ChunkySegment<T> {
  const ChunkySegment({
    required this.value,
    required this.label,
    this.icon,
    this.color,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Thumb color when this segment is active (e.g. red for Pengeluaran).
  final ChunkySwatch? color;
}

/// Segmented control with a sliding chunky thumb that takes the active
/// segment's color. Perfect for transaction type.
///
/// ```dart
/// ChunkySegmented<TxKind>(
///   segments: const [
///     ChunkySegment(value: TxKind.expense, label: 'Pengeluaran', color: GhinaColors.red),
///     ChunkySegment(value: TxKind.income, label: 'Pemasukan', color: GhinaColors.green),
///     ChunkySegment(value: TxKind.transfer, label: 'Transfer', color: GhinaColors.blue),
///   ],
///   value: kind,
///   onChanged: (k) => setState(() => kind = k),
/// );
/// ```
class ChunkySegmented<T> extends StatelessWidget {
  const ChunkySegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 48,
  });

  final List<ChunkySegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final index = segments
        .indexWhere((s) => s.value == value)
        .clamp(0, segments.length - 1);
    final active = segments[index];
    final sw = active.color ?? GhinaColors.blue;
    const pad = 4.0;
    const depth = 3.0;

    return Container(
      padding: const EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rLg,
        border: Border.all(color: g.border, width: 2),
      ),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: GhinaMotion.medium,
              curve: GhinaMotion.pop,
              alignment: Alignment(
                segments.length == 1
                    ? 0
                    : -1 + 2 * index / (segments.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / segments.length,
                heightFactor: 1,
                child: AnimatedContainer(
                  duration: GhinaMotion.medium,
                  decoration: BoxDecoration(
                    color: sw.edge,
                    borderRadius: GhinaRadii.rMd,
                  ),
                  padding: const EdgeInsets.only(bottom: depth),
                  child: AnimatedContainer(
                    duration: GhinaMotion.medium,
                    decoration: BoxDecoration(
                      color: sw.base,
                      borderRadius: GhinaRadii.rMd,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < segments.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: segments[i].label,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == index) return;
                          HapticFeedback.selectionClick();
                          onChanged(segments[i].value);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: depth),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: GhinaMotion.fast,
                              style: GhinaType.body
                                  .w(900)
                                  .copyWith(
                                    color: i == index ? sw.on : g.textSecondary,
                                  ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (segments[i].icon != null) ...[
                                      Icon(
                                        segments[i].icon,
                                        size: 18,
                                        color: i == index
                                            ? sw.on
                                            : g.textSecondary,
                                      ),
                                      const SizedBox(width: 5),
                                    ],
                                    Text(segments[i].label),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
