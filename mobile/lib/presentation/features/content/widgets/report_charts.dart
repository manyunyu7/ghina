import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

double _niceStep(double raw) {
  if (raw <= 0 || raw.isNaN) return 1;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final n = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)));
  return n * exp;
}

/// One bar of [SimpleBarChart].
typedef BarDatum = ({String label, double value, String tooltip});

/// Single-hue vertical bars (magnitude), recessive dashed grid, value
/// tooltip on touch. Used for weekday / hour averages and sponsor months.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.data,
    required this.color,
    required this.formatAxis,
    this.height = 180,
  });

  final List<BarDatum> data;
  final ChunkySwatch color;
  final String Function(double) formatAxis;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final maxV = data.fold<double>(0, (m, d) => math.max(m, d.value));
    final interval = _niceStep((maxV == 0 ? 1 : maxV) / 3);
    final maxY =
        (maxV / interval).ceil() * interval + (maxV == 0 ? interval : 0);
    final n = data.length;
    final rodW = n <= 4 ? 22.0 : (n <= 8 ? 16.0 : (n <= 14 ? 10.0 : 6.0));
    final axis = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 11,
    );
    return SizedBox(
      height: height,
      child: BarChart(
        duration: GhinaMotion.slow,
        BarChartData(
          maxY: maxY,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (v) => FlLine(
              color: v == 0 ? g.textMuted : g.border,
              strokeWidth: v == 0 ? 2 : 1.5,
              dashArray: v == 0 ? null : [6, 6],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: interval,
                getTitlesWidget: (v, meta) {
                  if (v == meta.max && v != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(formatAxis(v), style: axis),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= n) return const SizedBox.shrink();
                  if (n > 8 && i.isOdd && i != n - 1) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(data[i].label, style: axis),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) =>
                  g.isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.ink,
              tooltipBorderRadius: GhinaRadii.rMd,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, gi, r, ri) => BarTooltipItem(
                data[gi].tooltip,
                GhinaType.caption.w(800).copyWith(color: Colors.white),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].value,
                    width: rodW,
                    color: color.base,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
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

/// Horizontal bar rows: label · bar · value (readable with long labels).
class HBarList extends StatelessWidget {
  const HBarList({super.key, required this.rows, required this.color});

  final List<({String label, double value, String display, Color? dot})> rows;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final maxV = rows.fold<double>(0, (m, r) => math.max(m, r.value));
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Row(
                    children: [
                      if (r.dot != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: r.dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          r.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.bodyS
                              .w(700)
                              .copyWith(color: g.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: GhinaMotion.slow,
                        curve: GhinaMotion.standard,
                        height: 12,
                        width: maxV <= 0
                            ? 0
                            : math.max(4, c.maxWidth * r.value / maxV),
                        decoration: BoxDecoration(
                          color: color.base,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 58,
                  child: Text(
                    r.display,
                    textAlign: TextAlign.right,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(
                          color: g.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A 100% stacked bar of shares (pillar balance) with 2px surface gaps and a
/// legend below (identity never by color alone).
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.parts});

  final List<({String label, double share, Color color, int count})> parts;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: GhinaRadii.rMd,
          child: SizedBox(
            height: 22,
            child: Row(
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0) Container(width: 2, color: g.surface),
                  Expanded(
                    flex: math.max(1, (parts[i].share * 1000).round()),
                    child: Container(color: parts[i].color),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${p.label} ${(p.share * 100).round()}%',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textPrimary),
                  ),
                  Text(
                    ' · ${p.count}',
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
