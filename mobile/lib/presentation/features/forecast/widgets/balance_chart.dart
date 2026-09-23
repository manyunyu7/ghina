import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../forecast_state.dart';

/// Chunky projected-balance line: thick rounded stroke, dots on days with a
/// planned item or bill, soft fill, red zero line when it dips below 0.
class BalanceChart extends StatelessWidget {
  const BalanceChart({
    super.key,
    required this.points,
    required this.currency,
    required this.monthShort,
  });

  final List<BalancePoint> points;
  final String currency;

  /// `Okt` — for tooltips.
  final String monthShort;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final start = points.first.balance;
    final end = points.last.balance;
    final minB = points.map((p) => p.balance).reduce(math.min);
    final maxB = points.map((p) => p.balance).reduce(math.max);
    final sw = minB < 0
        ? GhinaColors.red
        : end < start
        ? GhinaColors.orange
        : GhinaColors.green;
    final span = (maxB - minB).abs();
    final pad = span == 0 ? (maxB.abs() * 0.1 + 1000) : span * 0.15;
    final minY = minB - pad;
    final maxY = maxB + pad;
    final interval = _niceInterval((maxY - minY) / 3);
    final lastDay = points.last.day.toDouble();
    final labelStyle = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 11,
    );

    return LineChart(
      duration: GhinaMotion.slow,
      curve: GhinaMotion.standard,
      LineChartData(
        minX: 0,
        maxX: lastDay,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: g.border, strokeWidth: 1.5, dashArray: [6, 6]),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (minY < 0 && maxY > 0)
              HorizontalLine(
                y: 0,
                color: GhinaColors.red.base.withValues(alpha: 0.7),
                strokeWidth: 2,
                dashArray: [4, 4],
              ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 58,
              interval: interval,
              getTitlesWidget: (v, meta) {
                if (v == meta.min || v == meta.max) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    GhinaMoney.format(v, currency: currency, compact: true),
                    style: labelStyle,
                  ),
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
                final d = v.round();
                if (v != d ||
                    !(d == 1 ||
                        d == 8 ||
                        d == 15 ||
                        d == 22 ||
                        d == lastDay.round())) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text('$d', style: labelStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                g.isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.ink,
            tooltipBorderRadius: GhinaRadii.rMd,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  s.x == 0 ? 'Sekarang\n' : '${s.x.round()} $monthShort\n',
                  GhinaType.caption.copyWith(color: Colors.white70),
                  children: [
                    TextSpan(
                      text: GhinaMoney.format(s.y, currency: currency),
                      style: GhinaType.moneyS.copyWith(color: Colors.white),
                    ),
                  ],
                ),
            ],
          ),
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                FlLine(color: sw.base.withValues(alpha: 0.5), strokeWidth: 2),
                FlDotData(
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 7,
                    color: sw.base,
                    strokeWidth: 3,
                    strokeColor: g.surface,
                  ),
                ),
              ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final p in points) FlSpot(p.day.toDouble(), p.balance),
            ],
            isCurved: true,
            curveSmoothness: 0.18,
            preventCurveOverShooting: true,
            color: sw.base,
            barWidth: 5,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            shadow: Shadow(color: sw.edge, offset: const Offset(0, 3)),
            dotData: FlDotData(
              checkToShowDot: (spot, _) =>
                  spot.x == 0 || points[spot.x.round()].event,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: spot.x == 0 ? 5 : 4.5,
                color: spot.x == 0 ? g.surface : sw.base,
                strokeWidth: 3,
                strokeColor: spot.x == 0 ? sw.base : g.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  sw.base.withValues(alpha: g.isDark ? 0.28 : 0.22),
                  sw.base.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1/2/2.5/5 × 10^n step close to [raw].
double _niceInterval(double raw) {
  if (raw <= 0 || raw.isNaN) return 1;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final nice = f <= 1
      ? 1
      : f <= 2
      ? 2
      : f <= 2.5
      ? 2.5
      : f <= 5
      ? 5
      : 10;
  return nice * exp;
}
