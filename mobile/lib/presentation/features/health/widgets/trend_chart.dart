import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

/// One line of a [TrendChart].
class TrendSeries {
  const TrendSeries({
    required this.label,
    required this.values,
    required this.color,
    this.fill = false,
  });

  final String label;

  /// One value per x label (null = no point).
  final List<double?> values;
  final ChunkySwatch color;
  final bool fill;
}

/// Chunky line chart for health trends (weight, blood pressure).
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.labels,
    required this.series,
    this.guides = const [],
    this.unit = '',
    this.decimals = 0,
    this.height = 190,
  });

  /// X-axis labels (oldest → newest).
  final List<String> labels;
  final List<TrendSeries> series;

  /// Dashed reference lines (value, color).
  final List<(double, Color)> guides;
  final String unit;
  final int decimals;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final all = [
      for (final s in series)
        for (final v in s.values) ?v,
      for (final (v, _) in guides) v,
    ];
    if (all.isEmpty) return SizedBox(height: height);
    var minY = all.reduce((a, b) => a < b ? a : b);
    var maxY = all.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.18).clamp(1.0, double.infinity);
    minY = (minY - pad).floorToDouble();
    maxY = (maxY + pad).ceilToDouble();
    final n = labels.length;
    final step = n <= 6 ? 1 : (n / 5).ceil();
    final axisStyle = GhinaType.caption.copyWith(
      color: g.textMuted,
      fontSize: 11,
    );

    String fmt(double v) => decimals == 0
        ? v.round().toString()
        : v.toStringAsFixed(decimals).replaceAll('.', ',');

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          // A little air left/right so the end dots and labels aren't clipped.
          minX: -0.4,
          maxX: (n - 1).toDouble().clamp(1, double.infinity) + 0.4,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: g.border, strokeWidth: 1.5, dashArray: [4, 4]),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              for (final (v, c) in guides)
                HorizontalLine(
                  y: v,
                  color: c.withValues(alpha: 0.6),
                  strokeWidth: 1.5,
                  dashArray: [6, 5],
                ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (v, meta) {
                  if (v == meta.min || v == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(fmt(v), style: axisStyle),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= n || v != i.toDouble()) {
                    return const SizedBox.shrink();
                  }
                  if (i % step != 0 && i != n - 1) {
                    return const SizedBox.shrink();
                  }
                  if (i != n - 1 && n - 1 - i < step) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(labels[i], style: axisStyle),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => g.isDark ? g.surfaceAlt : GhinaColors.ink,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${labels[s.x.round()]}: ${fmt(s.y)}$unit',
                    GhinaType.caption
                        .w(800)
                        .copyWith(color: series[s.barIndex].color.base),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < s.values.length; i++)
                    if (s.values[i] != null) FlSpot(i.toDouble(), s.values[i]!),
                ],
                isCurved: true,
                preventCurveOverShooting: true,
                color: s.color.base,
                barWidth: 4,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 4,
                    color: g.surface,
                    strokeWidth: 3,
                    strokeColor: s.color.base,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: s.fill,
                  color: s.color.base.withValues(alpha: 0.14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
