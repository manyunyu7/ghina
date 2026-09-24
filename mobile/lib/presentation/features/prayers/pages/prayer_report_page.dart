import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/prayer_sheet.dart';
import '../widgets/prayer_visuals.dart';

/// Prayer quality report for a date range: score ring + mascot, status
/// percentages, per-prayer stacked bars (weakest / strongest), sunnah & rawatib
/// counts and the color map (one row per day, newest first; tap a cell to edit).
class PrayerReportPage extends ConsumerStatefulWidget {
  const PrayerReportPage({super.key});

  @override
  ConsumerState<PrayerReportPage> createState() => _PrayerReportPageState();
}

class _PrayerReportPageState extends ConsumerState<PrayerReportPage> {
  PrayerRangePreset _preset = PrayerRangePreset.last7Days;
  ({DateTime from, DateTime to})? _custom;

  DateTime get _today => startOfDay(ref.read(clockProvider).now());

  ({DateTime from, DateTime to}) get _range =>
      _preset == PrayerRangePreset.custom && _custom != null
      ? _custom!
      : _preset.resolve(_today);

  Future<void> _pickCustom() async {
    final today = _today;
    final cur = _range;
    final from = await showGhinaDatePicker(
      context,
      initial: cur.from,
      title: 'Mulai tanggal',
      firstDate: DateTime(2000),
      lastDate: today,
      today: today,
    );
    if (from == null || !mounted) return;
    final to = await showGhinaDatePicker(
      context,
      initial: cur.to.isBefore(from) ? from : cur.to,
      title: 'Sampai tanggal',
      firstDate: from,
      lastDate: today,
      today: today,
    );
    if (to == null || !mounted) return;
    setState(() {
      _preset = PrayerRangePreset.custom;
      _custom = customPrayerRange(from, to);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _range;
    final async = ref.watch(watchPrayerReportProvider(r));
    final report = async.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan salat')),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.md,
                GhinaSpace.page,
                0,
              ),
              sliver: SliverList.list(
                children: [
                  ChunkyChoiceChips<PrayerRangePreset>(
                    scrollable: true,
                    options: [
                      for (final p in PrayerRangePreset.values)
                        ChunkyChoice(
                          value: p,
                          label: p.label,
                          icon: p == PrayerRangePreset.custom
                              ? Icons.date_range_rounded
                              : null,
                        ),
                    ],
                    selected: {_preset},
                    onChanged: (s) {
                      if (s.isEmpty) return;
                      if (s.first == PrayerRangePreset.custom) {
                        _pickCustom();
                      } else {
                        setState(() => _preset = s.first);
                      }
                    },
                  ),
                  const SizedBox(height: GhinaSpace.sm),
                  Text(
                    _rangeLabel(r.from, r.to),
                    key: const ValueKey('report-range'),
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: context.ghina.textSecondary),
                  ),
                  const SizedBox(height: GhinaSpace.md),
                ],
              ),
            ),
            if (report == null && async.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorRetry(
                  onRetry: () => ref.invalidate(watchPrayerReportProvider(r)),
                ),
              )
            else if (report == null)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: GhinaSpace.page),
                sliver: SliverToBoxAdapter(child: SkeletonList(count: 4)),
              )
            else
              ..._content(report),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  String _rangeLabel(DateTime from, DateTime to) {
    final days = daysBetween(to, from) + 1;
    return '${Fmt.date(from)} – ${Fmt.date(to)} · $days hari';
  }

  List<Widget> _content(PrayerReport report) {
    Widget pad(Widget w) => SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
      sliver: SliverToBoxAdapter(child: w),
    );
    return [
      pad(_ScoreHero(report: report)),
      pad(const SizedBox(height: GhinaSpace.md)),
      pad(_QuickStats(report: report)),
      pad(const SizedBox(height: GhinaSpace.xl)),
      pad(
        const SectionHeader(
          title: 'Status salat',
          subtitle: 'Persentase dari waktu salat yang dihitung',
        ),
      ),
      pad(_StatusBreakdown(report: report)),
      pad(const SizedBox(height: GhinaSpace.xl)),
      pad(
        const SectionHeader(
          title: 'Per waktu salat',
          subtitle: 'Mana yang paling kuat, mana yang perlu dikejar',
        ),
      ),
      pad(_PerPrayer(report: report)),
      pad(const SizedBox(height: GhinaSpace.xl)),
      pad(const SectionHeader(title: 'Sunnah & rawatib')),
      pad(_SunnahCounts(report: report)),
      pad(const SizedBox(height: GhinaSpace.xl)),
      pad(
        const SectionHeader(
          title: 'Peta warna',
          subtitle: 'Satu baris per hari · ketuk kotak untuk mengubah',
        ),
      ),
      pad(const _ColorMapHeader()),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
        sliver: SliverList.builder(
          itemCount: report.days.length,
          itemBuilder: (context, i) => _ColorMapRow(
            day: report.days[i],
            onTap: (p) => PrayerActions.edit(
              context,
              ref,
              report.days[i].day,
              p,
              report.days[i].entries,
            ),
          ),
        ),
      ),
      pad(const SizedBox(height: GhinaSpace.md)),
      pad(const _ColorMapLegend()),
    ];
  }
}

// ---------------------------------------------------------------- hero

class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.report});

  final PrayerReport report;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final score = report.score;
    final (mood, title, message, color) = switch (score) {
      null => (
        MascotMood.sleeping,
        'Belum ada catatan',
        'Catat salatmu di halaman Salat, nanti skornya muncul di sini.',
        GhinaColors.gray,
      ),
      >= 85 => (
        MascotMood.excited,
        'MasyaAllah, keren!',
        'Kualitas salatmu top banget. Pertahankan, ya!',
        GhinaColors.green,
      ),
      >= 70 => (
        MascotMood.happy,
        'Bagus!',
        'Tinggal naikin jamaahnya sedikit lagi.',
        GhinaColors.green,
      ),
      >= 50 => (
        MascotMood.thinking,
        'Lumayan',
        'Yuk, kejar awal waktu dan jamaah pelan-pelan.',
        GhinaColors.yellow,
      ),
      _ => (
        MascotMood.sad,
        'Ayo bangkit lagi',
        'Mulai dari satu waktu dulu. Kamu pasti bisa 💪',
        GhinaColors.orange,
      ),
    };
    return ChunkyCard(
      key: const ValueKey('report-hero'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          ProgressRing(
            value: (score ?? 0) / 100,
            size: 108,
            stroke: 12,
            color: color,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  child: Text(
                    score == null ? '–' : '$score',
                    key: const ValueKey('report-score'),
                    style: GhinaType.display
                        .w(900)
                        .copyWith(color: g.textPrimary, height: 1),
                  ),
                ),
                Text(
                  'SKOR',
                  style: GhinaType.caption.w(900).copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GhinaType.h2
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    MascotView(mood: mood, size: 56),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  '${report.points} dari ${report.counted * prayerMaxPoints} poin',
                  style: GhinaType.caption.w(800).copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.report});

  final PrayerReport report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatTile(
            icon: Icons.groups_rounded,
            value: _pctLabel(report.jamaahPct),
            label: 'Jamaah',
            color: GhinaColors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            icon: Icons.event_available_rounded,
            value: '${report.completeDays}/${report.daysElapsed}',
            label: 'Hari lengkap',
            color: GhinaColors.blue,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- statuses

/// `40%` / `12,5%` (1 decimal, Indonesian comma).
String _pctLabel(double pct) {
  final whole = pct == pct.roundToDouble();
  return '${whole ? pct.round() : pct.toStringAsFixed(1).replaceAll('.', ',')}%';
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.report});

  final PrayerReport report;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget row(Color color, String label, int count, double? pct) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: GhinaRadii.rSm,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
                ),
              ),
              Text(
                pct == null ? '$count×' : '$count× · ${_pctLabel(pct)}',
                style: GhinaType.bodyS.w(900).copyWith(color: g.textSecondary),
              ),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: GhinaRadii.rPill,
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 7,
                color: color,
                backgroundColor: g.surfaceAlt,
              ),
            ),
          ],
        ],
      ),
    );
    return ChunkyCard(
      key: const ValueKey('report-statuses'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          for (final s in PrayerStatus.fardhu)
            if (s != PrayerStatus.excused)
              row(
                prayerStatusColor(s),
                s.label,
                report.count(s),
                report.pct(s),
              ),
          row(
            prayerEmptyColor(context),
            'Belum diisi',
            report.unfilled,
            report.unfilledPct,
          ),
          if (report.count(PrayerStatus.excused) > 0)
            row(
              prayerStatusColor(PrayerStatus.excused),
              '${PrayerStatus.excused.label} · tidak dihitung',
              report.count(PrayerStatus.excused),
              null,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- per prayer

class _PerPrayer extends StatelessWidget {
  const _PerPrayer({required this.report});

  final PrayerReport report;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final weak = report.weakest == null
        ? null
        : report.breakdownOf(report.weakest!);
    final strong = report.strongest == null
        ? null
        : report.breakdownOf(report.strongest!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (strong != null || weak != null)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (strong != null)
                  _Callout(
                    key: const ValueKey('report-strongest'),
                    color: GhinaColors.green,
                    icon: Icons.emoji_events_rounded,
                    title: 'Paling kuat: ${strong.prayer.label}',
                    message:
                        'Skor ${strong.score} · ${strong.congregation}× berjamaah',
                  ),
                if (strong != null && weak != null)
                  const SizedBox(height: GhinaSpace.sm),
                if (weak != null)
                  _Callout(
                    key: const ValueKey('report-weakest'),
                    color: GhinaColors.orange,
                    icon: Icons.trending_up_rounded,
                    title: 'Perlu dikejar: ${weak.prayer.label}',
                    message: [
                      if (weak.count(PrayerStatus.late) > 0)
                        '${weak.count(PrayerStatus.late)}× telat',
                      if (weak.count(PrayerStatus.missed) > 0)
                        '${weak.count(PrayerStatus.missed)}× terlewat',
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        ChunkyCard(
          key: const ValueKey('report-per-prayer'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            children: [
              for (final b in report.breakdown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          b.prayer.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.bodyS
                              .w(900)
                              .copyWith(
                                color: b.prayer == weak?.prayer
                                    ? GhinaColors.orange.base
                                    : b.prayer == strong?.prayer
                                    ? GhinaColors.green.base
                                    : g.textPrimary,
                              ),
                        ),
                      ),
                      Expanded(child: _StackedBar(breakdown: b)),
                      SizedBox(
                        width: 36,
                        child: Text(
                          b.score == null ? '–' : '${b.score}',
                          textAlign: TextAlign.right,
                          style: GhinaType.bodyS
                              .w(900)
                              .copyWith(color: g.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.breakdown});

  final PrayerBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    final parts = <(Color, int)>[
      for (final s in PrayerStatus.fardhu)
        if (b.count(s) > 0) (prayerStatusColor(s), b.count(s)),
      if (b.unfilled > 0) (prayerEmptyColor(context), b.unfilled),
    ];
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: context.ghina.surfaceAlt,
        borderRadius: GhinaRadii.rPill,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final (c, n) in parts)
            Expanded(
              flex: n,
              child: Container(color: c),
            ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ChunkySwatch color;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      tinted: color,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          CategoryAvatar(icon: icon, color: color.base, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GhinaType.h3.copyWith(color: g.textPrimary)),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- sunnah

class _SunnahCounts extends StatelessWidget {
  const _SunnahCounts({required this.report});

  final PrayerReport report;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget cell(IconData icon, Color color, String value, String label) =>
        Expanded(
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ],
          ),
        );
    return ChunkyCard(
      key: const ValueKey('report-sunnah'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          cell(
            Icons.auto_awesome_rounded,
            GhinaColors.green.base,
            '${report.rawatibCount}',
            'Rawatib',
          ),
          for (final p in Prayer.sunnah)
            cell(
              prayerStyles[p]!.icon,
              sunnahDotColor(p),
              '${report.sunnahCounts[p] ?? 0}',
              p.label,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- color map

const _dateColWidth = 58.0;
const _sunnahColWidth = 30.0;
const _cellGap = 4.0;

class _ColorMapHeader extends StatelessWidget {
  const _ColorMapHeader();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final style = GhinaType.caption.w(900).copyWith(color: g.textMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: _dateColWidth),
          for (final p in Prayer.fardhu)
            Expanded(
              child: Center(
                child: Text(
                  prayerShort(p),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: style,
                ),
              ),
            ),
          SizedBox(
            width: _sunnahColWidth,
            child: Center(
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: g.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorMapRow extends StatelessWidget {
  const _ColorMapRow({required this.day, required this.onTap});

  final PrayerDay day;
  final ValueChanged<Prayer> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final d = day.day;
    final weekday = Fmt.dateShortWeekday(d).split(',').first;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: _cellGap),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            SizedBox(
              width: _dateColWidth,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$weekday ',
                        style: GhinaType.caption.copyWith(
                          color: day.isToday
                              ? GhinaColors.blue.base
                              : g.textMuted,
                        ),
                      ),
                      TextSpan(
                        text: '${d.day}/${d.month}',
                        style: GhinaType.bodyS
                            .w(900)
                            .copyWith(
                              color: day.isToday
                                  ? GhinaColors.blue.base
                                  : g.textPrimary,
                            ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
            for (final c in day.cells)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _cellGap / 2),
                  child: _MapCell(
                    key: ValueKey('map-${day.key}-${c.prayer.wire}'),
                    cell: c,
                    onTap: day.isFuture ? null : () => onTap(c.prayer),
                  ),
                ),
              ),
            SizedBox(
              width: _sunnahColWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final p in Prayer.sunnah)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: day.sunnah.containsKey(p)
                            ? sunnahDotColor(p)
                            : Colors.transparent,
                        border: day.sunnah.containsKey(p)
                            ? null
                            : Border.all(color: g.border, width: 1.2),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return day.isFuture ? Opacity(opacity: 0.35, child: row) : row;
  }
}

class _MapCell extends StatelessWidget {
  const _MapCell({super.key, required this.cell, required this.onTap});

  final PrayerCell cell;

  /// Null for future days (not editable).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = cell.status;
    final color = prayerCellColor(context, s);
    return Semantics(
      button: true,
      label: '${cell.prayer.label}: ${s?.label ?? 'belum diisi'}',
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _RawatibMarks(
            qobliyah: cell.qobliyah,
            badiyah: cell.badiyah,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: GhinaRadii.rSm,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rawatib corner marks (spec): white dot top-left = qobliyah, top-right =
/// ba'diyah. A faint ring keeps the dot visible on light cells.
class _RawatibMarks extends CustomPainter {
  const _RawatibMarks({required this.qobliyah, required this.badiyah});

  final bool qobliyah;
  final bool badiyah;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 2.6, inset = 5.0;
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    void dot(Offset c) {
      canvas.drawCircle(c, r, fill);
      canvas.drawCircle(c, r, ring);
    }

    if (qobliyah) dot(const Offset(inset, inset));
    if (badiyah) dot(Offset(size.width - inset, inset));
  }

  @override
  bool shouldRepaint(_RawatibMarks old) =>
      old.qobliyah != qobliyah || old.badiyah != badiyah;
}

class _ColorMapLegend extends StatelessWidget {
  const _ColorMapLegend();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          const PrayerStatusLegend(),
          const SizedBox(height: 10),
          Divider(height: 2, thickness: 2, color: g.border),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final p in Prayer.sunnah)
                PrayerLegendItem(
                  color: sunnahDotColor(p),
                  label: p.label,
                  round: true,
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 14,
                    decoration: BoxDecoration(
                      color: prayerStatusColor(PrayerStatus.jamaah),
                      borderRadius: GhinaRadii.rSm,
                    ),
                    child: const CustomPaint(
                      painter: _RawatibMarks(qobliyah: true, badiyah: true),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      "Titik putih = rawatib (kiri qobliyah, kanan ba'diyah)",
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
