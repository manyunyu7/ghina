import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

TextStyle _axis(GhinaTokens g) =>
    GhinaType.caption.copyWith(color: g.textSecondary, fontSize: 11);

Color _tooltipBg(GhinaTokens g) =>
    g.isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.ink;

double niceStep(double raw) {
  if (raw <= 0 || raw.isNaN) return 1;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final n = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)));
  return n * exp;
}

FlGridData _grid(GhinaTokens g, double interval) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (v) => FlLine(
    color: v == 0 ? g.textMuted : g.border,
    strokeWidth: v == 0 ? 2 : 1.5,
    dashArray: v == 0 ? null : [6, 6],
  ),
);

AxisTitles _leftMoney(GhinaTokens g, double interval, String currency) =>
    AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 56,
        interval: interval,
        getTitlesWidget: (v, meta) {
          if (v == meta.max && v != 0) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            space: 6,
            child: Text(
              GhinaMoney.format(v, currency: currency, compact: true),
              style: _axis(g),
            ),
          );
        },
      ),
    );

AxisTitles _bottomMonths(GhinaTokens g, List<MonthTotals> months) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 26,
    getTitlesWidget: (v, meta) {
      final i = v.round();
      if (i < 0 || i >= months.length) return const SizedBox.shrink();
      // Keep it readable with 12 months on a phone.
      if (months.length > 7 && i.isOdd && i != months.length - 1) {
        return const SizedBox.shrink();
      }
      return SideTitleWidget(
        meta: meta,
        space: 6,
        child: Text(Fmt.monthShort(months[i].month.month), style: _axis(g)),
      );
    },
  ),
);

/// Grouped income (green) vs expense (red) bars per month.
class IncomeExpenseChart extends StatelessWidget {
  const IncomeExpenseChart({
    super.key,
    required this.months,
    required this.currency,
  });

  final List<MonthTotals> months;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final maxV = months.fold<double>(
      0,
      (m, x) => math.max(m, math.max(x.income, x.expense)),
    );
    final interval = niceStep((maxV == 0 ? 1 : maxV) / 3);
    final maxY =
        (maxV / interval).ceil() * interval + (maxV == 0 ? interval : 0);
    final n = months.length;
    final rodW = n <= 1 ? 28.0 : (n <= 6 ? 12.0 : 7.0);
    BarChartRodData rod(double v, ChunkySwatch sw) => BarChartRodData(
      toY: v,
      width: rodW,
      color: sw.base,
      borderRadius: BorderRadius.vertical(top: Radius.circular(rodW / 2.2)),
      borderSide: BorderSide(color: sw.edge, width: 0),
    );
    return BarChart(
      duration: GhinaMotion.slow,
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _grid(g, interval),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: _leftMoney(g, interval, currency),
          bottomTitles: _bottomMonths(g, months),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tooltipBg(g),
            tooltipBorderRadius: GhinaRadii.rMd,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, gi, r, ri) => BarTooltipItem(
              '${ri == 0 ? 'Masuk' : 'Keluar'} ${Fmt.monthShort(months[gi].month.month)}\n',
              GhinaType.caption.copyWith(color: Colors.white70),
              children: [
                TextSpan(
                  text: GhinaMoney.format(r.toY, currency: currency),
                  style: GhinaType.moneyS.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barsSpace: n <= 6 ? 4 : 2,
              barRods: [
                rod(months[i].income, GhinaColors.green),
                rod(months[i].expense, GhinaColors.red),
              ],
            ),
        ],
      ),
    );
  }
}

/// Net cashflow per month: green above zero, red below.
class CashflowChart extends StatelessWidget {
  const CashflowChart({
    super.key,
    required this.months,
    required this.currency,
  });

  final List<MonthTotals> months;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final maxV = months.fold<double>(0, (m, x) => math.max(m, x.net));
    final minV = months.fold<double>(0, (m, x) => math.min(m, x.net));
    final interval = niceStep(math.max(1, maxV - minV) / 3);
    final maxY = maxV <= 0 ? interval : (maxV / interval).ceil() * interval;
    final minY = minV >= 0 ? 0.0 : (minV / interval).floor() * interval;
    final n = months.length;
    final rodW = n <= 1 ? 32.0 : (n <= 6 ? 20.0 : 12.0);
    return BarChart(
      duration: GhinaMotion.slow,
      BarChartData(
        maxY: maxY,
        minY: minY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _grid(g, interval),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: _leftMoney(g, interval, currency),
          bottomTitles: _bottomMonths(g, months),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tooltipBg(g),
            tooltipBorderRadius: GhinaRadii.rMd,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, gi, r, ri) => BarTooltipItem(
              'Bersih ${Fmt.monthShort(months[gi].month.month)}\n',
              GhinaType.caption.copyWith(color: Colors.white70),
              children: [
                TextSpan(
                  text: GhinaMoney.format(
                    r.toY,
                    currency: currency,
                    showSign: true,
                  ),
                  style: GhinaType.moneyS.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: months[i].net,
                  width: rodW,
                  color: months[i].net >= 0
                      ? GhinaColors.green.base
                      : GhinaColors.red.base,
                  borderRadius: months[i].net >= 0
                      ? BorderRadius.vertical(top: Radius.circular(rodW / 3))
                      : BorderRadius.vertical(
                          bottom: Radius.circular(rodW / 3),
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Donut with the total in the middle and a legend underneath (never beside
/// it, so long names can't overflow on narrow phones). Small slices beyond
/// [maxSlices] are merged into "Lainnya".
class CategoryDonut extends StatefulWidget {
  const CategoryDonut({
    super.key,
    required this.rows,
    required this.currency,
    required this.centerLabel,
    this.maxSlices = 6,
  });

  final List<CategoryTotal> rows;
  final String currency;
  final String centerLabel;
  final int maxSlices;

  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rows = widget.rows.where((r) => r.total > 0).toList();
    final total = rows.fold<double>(0, (s, r) => s + r.total);
    final slices = <({String name, Color color, double value})>[
      for (final r in rows.take(widget.maxSlices))
        (name: r.name, color: CategoryColors.parse(r.color), value: r.total),
      if (rows.length > widget.maxSlices)
        (
          name: 'Lainnya',
          color: CategoryColors.parse(CategoryTotal.uncategorizedColor),
          value: rows.skip(widget.maxSlices).fold(0, (s, r) => s + r.total),
        ),
    ];
    final t = _touched;
    final focus = t != null && t < slices.length ? slices[t] : null;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                duration: GhinaMotion.medium,
                PieChartData(
                  centerSpaceRadius: 58,
                  sectionsSpace: 3,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (e, r) {
                      if (!e.isInterestedForInteractions) return;
                      setState(
                        () => _touched = r?.touchedSection?.touchedSectionIndex,
                      );
                    },
                  ),
                  sections: [
                    for (var i = 0; i < slices.length; i++)
                      PieChartSectionData(
                        value: slices[i].value,
                        color: slices[i].color,
                        radius: i == t ? 42 : 34,
                        showTitle: false,
                        borderSide: BorderSide(color: g.surface, width: 2),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 104,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      focus?.name ?? widget.centerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        GhinaMoney.format(
                          focus?.value ?? total,
                          currency: widget.currency,
                          compact: true,
                        ),
                        style: GhinaType.h3
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (focus != null)
                      Text(
                        '${(focus.value / total * 100).toStringAsFixed(0)}%',
                        style: GhinaType.caption
                            .w(900)
                            .copyWith(color: focus.color),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < slices.length; i++)
          InkWell(
            borderRadius: GhinaRadii.rMd,
            onTap: () => setState(() => _touched = _touched == i ? null : i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: slices[i].color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      slices[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyS
                          .w(i == t ? 900 : 700)
                          .copyWith(color: g.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    GhinaMoney.format(
                      slices[i].value,
                      currency: widget.currency,
                      compact: true,
                    ),
                    style: GhinaType.moneyS.copyWith(color: g.textPrimary),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(slices[i].value / total * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
