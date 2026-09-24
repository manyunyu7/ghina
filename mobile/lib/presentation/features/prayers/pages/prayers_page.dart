import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' show XpRules;
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/prayer_sheet.dart';
import '../widgets/prayer_visuals.dart';

const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

typedef _DayMap = Map<String, Map<Prayer, PrayerEntry>>;

/// Daily prayers: five fardhu tiles (tap = jamaah, long-press / chevron = pick
/// any status + rawatib), daily sunnah, a week strip, stats and a month heatmap
/// colored by status. The quality report is one tap away.
class PrayersPage extends ConsumerStatefulWidget {
  const PrayersPage({super.key});

  @override
  ConsumerState<PrayersPage> createState() => _PrayersPageState();
}

class _PrayersPageState extends ConsumerState<PrayersPage> {
  DateTime? _selected;
  YearMonth? _month;
  final _busy = <Prayer>{};
  final _pops = <Prayer, (int, int)>{};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  DateTime get _today => startOfDay(ref.read(clockProvider).now());

  Future<void> _refresh() async {
    try {
      await ref.read(syncNowProvider)();
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Belum bisa sinkron. Cek koneksi kamu, ya.');
      }
    }
  }

  void _select(DateTime d, {bool scrollUp = false}) {
    final today = _today;
    if (d.isAfter(today)) return;
    setState(() {
      _selected = startOfDay(d);
      _month = YearMonth.of(d);
    });
    if (scrollUp && _scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: GhinaMotion.slow,
        curve: GhinaMotion.standard,
      );
    }
  }

  Future<void> _run(Prayer p, Future<void> Function() action) async {
    if (_busy.contains(p)) return;
    setState(() => _busy.add(p));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy.remove(p));
    }
  }

  void _tap(DateTime day, Prayer p, Map<Prayer, PrayerEntry> entries) {
    if (entries[p] != null) {
      _edit(day, p, entries);
      return;
    }
    _run(p, () async {
      final ok = await PrayerActions.quickLog(context, ref, day, p, entries);
      if (ok && mounted) {
        setState(() {
          final n = (_pops[p]?.$1 ?? 0) + 1;
          _pops[p] = (n, prayerStatusXp(PrayerStatus.quick));
        });
      }
    });
  }

  void _edit(DateTime day, Prayer p, Map<Prayer, PrayerEntry> entries) =>
      _run(p, () => PrayerActions.edit(context, ref, day, p, entries));

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final today = startOfDay(ref.watch(clockProvider).now());
    final selected = _selected ?? today;
    final month = _month ?? YearMonth.of(today);

    final recentFrom = addDays(today, -62);
    final recent = ref.watch(
      watchPrayersProvider((from: recentFrom, to: today)),
    );
    final monthAsync = ref.watch(
      watchPrayersProvider((from: month.start, to: startOfDay(month.end))),
    );

    final all = [...?monthAsync.value, ...?recent.value];
    final byDate = <String, Map<Prayer, PrayerEntry>>{
      ...prayerEntriesByDate(monthAsync.value ?? const []),
      ...prayerEntriesByDate(recent.value ?? const []),
    };
    final dayEntries = byDate[dateKey(selected)] ?? const {};

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Salat'),
        actions: [
          IconButton(
            key: const ValueKey('prayer-report'),
            tooltip: 'Laporan salat',
            icon: const Icon(Icons.insights_rounded),
            color: GhinaColors.blue.base,
            onPressed: () => context.push('/prayers/report'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: switch (recent) {
          AsyncError() when recent.value == null => ListView(
            children: [
              ErrorRetry(onRetry: () => ref.invalidate(watchPrayersProvider)),
            ],
          ),
          _ => ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              8,
              GhinaSpace.page,
              48,
            ),
            children: [
              _DayHeader(
                day: selected,
                today: today,
                entries: dayEntries,
                onPrev: () => _select(addDays(selected, -1)),
                onNext: isSameDay(selected, today)
                    ? null
                    : () => _select(addDays(selected, 1)),
              ),
              const SizedBox(height: 12),
              _WeekStrip(
                selected: selected,
                today: today,
                byDate: byDate,
                onTap: _select,
              ),
              const SizedBox(height: 16),
              if (recent.value == null && monthAsync.value == null)
                const SkeletonList(count: 5)
              else ...[
                for (final p in Prayer.fardhu)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PrayerTile(
                      key: ValueKey('prayer-${p.wire}'),
                      prayer: p,
                      entry: dayEntries[p],
                      busy: _busy.contains(p),
                      pop: _pops[p],
                      onTap: () => _tap(selected, p, dayEntries),
                      onEdit: () => _edit(selected, p, dayEntries),
                    ),
                  ),
                const SizedBox(height: 4),
                _SunnahCard(
                  day: selected,
                  entries: dayEntries,
                  busy: _busy,
                  onToggle: (p, done) => _run(
                    p,
                    () => PrayerActions.setSunnah(
                      context,
                      ref,
                      selected,
                      p,
                      done: done,
                      rakaat: dayEntries[p]?.rakaat,
                    ),
                  ),
                  onRakaat: (p, r) => _run(
                    p,
                    () => PrayerActions.setSunnah(
                      context,
                      ref,
                      selected,
                      p,
                      done: true,
                      rakaat: r,
                      reward: false,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _Stats(today: today, month: month, entries: all),
              const SizedBox(height: 12),
              ChunkyCard(
                key: const ValueKey('prayer-report-card'),
                tinted: GhinaColors.blue,
                onTap: () => context.push('/prayers/report'),
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    CategoryAvatar(
                      icon: Icons.grid_view_rounded,
                      color: GhinaColors.blue.base,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Laporan & peta warna',
                            style: GhinaType.h3.copyWith(color: g.textPrimary),
                          ),
                          Text(
                            'Skor kualitas, salat terlemah, rawatib & sunnah',
                            style: GhinaType.bodyS.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: GhinaColors.blue.base,
                      size: 28,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const SectionHeader(
                title: 'Kalender',
                subtitle: 'Ketuk tanggal untuk mengubah catatannya',
              ),
              ChunkyCard(
                child: _MonthHeatmap(
                  month: month,
                  today: today,
                  selected: selected,
                  byDate: byDate,
                  loading: monthAsync.value == null,
                  onMonth: (m) => setState(() => _month = m),
                  onTap: (d) => _select(d, scrollUp: true),
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

int _prayedCount(Map<Prayer, PrayerEntry>? m) =>
    m == null ? 0 : Prayer.fardhu.where((p) => m[p]?.isPrayed ?? false).length;

// ---------------------------------------------------------------- header

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.today,
    required this.entries,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime day;
  final DateTime today;
  final Map<Prayer, PrayerEntry> entries;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final done = _prayedCount(entries);
    final all = done == 5;
    final excused = prayerDayState(entries) == PrayerDayState.neutral;
    return ChunkyCard(
      tinted: all ? GhinaColors.green : null,
      child: Row(
        children: [
          ChunkyIconButton(
            icon: Icons.chevron_left_rounded,
            size: 40,
            tooltip: 'Hari sebelumnya',
            onPressed: onPrev,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  Fmt.relativeDay(day, now: today),
                  style: GhinaType.h2.w(900),
                  textAlign: TextAlign.center,
                ),
                Text(
                  Fmt.dateFull(day),
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Pulse(
                  trigger: done,
                  child: ChunkyPill(
                    label: all
                        ? 'Lengkap $done/5'
                        : excused
                        ? 'Berhalangan'
                        : '$done/5 salat',
                    icon: all
                        ? Icons.check_circle_rounded
                        : excused
                        ? Icons.spa_rounded
                        : Icons.mosque_rounded,
                    color: all
                        ? GhinaColors.green
                        : excused
                        ? GhinaColors.purple
                        : GhinaColors.blue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ChunkyIconButton(
            icon: Icons.chevron_right_rounded,
            size: 40,
            tooltip: 'Hari berikutnya',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- week strip

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.today,
    required this.byDate,
    required this.onTap,
  });

  final DateTime selected;
  final DateTime today;
  final _DayMap byDate;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final monday = addDays(selected, -(selected.weekday - 1));
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(
              builder: (context) {
                final d = addDays(monday, i);
                final future = d.isAfter(today);
                final count = _prayedCount(byDate[dateKey(d)]);
                final isSel = isSameDay(d, selected);
                final full = count == 5;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: future ? null : () => onTap(d),
                  child: Semantics(
                    button: !future,
                    selected: isSel,
                    label: '${Fmt.dateShortWeekday(d)}, $count dari 5 salat',
                    child: AnimatedContainer(
                      duration: GhinaMotion.fast,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSel
                            ? GhinaColors.blue.tint(g.brightness)
                            : null,
                        borderRadius: GhinaRadii.rLg,
                        border: Border.all(
                          color: isSel
                              ? GhinaColors.blue.tintBorder(g.brightness)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _weekdays[i],
                            style: GhinaType.caption.copyWith(
                              color: isSameDay(d, today)
                                  ? GhinaColors.blue.base
                                  : g.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ProgressRing(
                            value: count / 5,
                            size: 34,
                            stroke: 4,
                            color: full
                                ? GhinaColors.green
                                : GhinaColors.orange,
                            child: full
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: GhinaColors.green.base,
                                  )
                                : FittedBox(
                                    child: Text(
                                      '${d.day}',
                                      style: GhinaType.caption
                                          .w(900)
                                          .copyWith(
                                            color: future
                                                ? g.textMuted
                                                : g.textPrimary,
                                          ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 5),
                          _StatusDots(
                            entries: byDate[dateKey(d)],
                            future: future,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Five tiny status-colored dots (one per fardhu).
class _StatusDots extends StatelessWidget {
  const _StatusDots({
    required this.entries,
    this.future = false,
    this.size = 5,
  });

  final Map<Prayer, PrayerEntry>? entries;
  final bool future;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final p in Prayer.fardhu)
        Container(
          width: size,
          height: size,
          margin: const EdgeInsets.symmetric(horizontal: 0.75),
          decoration: BoxDecoration(
            color: future
                ? Colors.transparent
                : prayerCellColor(context, entries?[p]?.status),
            shape: BoxShape.circle,
          ),
        ),
    ],
  );
}

// ---------------------------------------------------------------- tile

class _PrayerTile extends StatelessWidget {
  const _PrayerTile({
    super.key,
    required this.prayer,
    required this.entry,
    required this.busy,
    required this.pop,
    required this.onTap,
    required this.onEdit,
  });

  final Prayer prayer;
  final PrayerEntry? entry;
  final bool busy;

  /// (replay counter, xp) of the last "+XP" pop.
  final (int, int)? pop;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final st = prayerStyles[prayer]!;
    final e = entry;
    final status = e?.status;
    final sw = status == null ? st.color : prayerStatusSwatch(status);
    final filled = status != null;
    final fg = filled ? sw.on : g.textPrimary;
    final sub = filled ? sw.on.withValues(alpha: 0.9) : g.textSecondary;
    final rawatib = [
      if (e?.qobliyah ?? false) 'Qobliyah',
      if (e?.badiyah ?? false) "Ba'diyah",
    ];
    final subtitle = status == null
        ? '${st.time} · ketuk = jamaah'
        : [
            status.label,
            if (rawatib.isNotEmpty) '+ ${rawatib.join(' & ')}',
          ].join(' · ');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChunkySurface(
          color: filled ? sw.base : g.surface,
          edgeColor: filled ? sw.edge : g.borderEdge,
          borderColor: filled ? null : g.border,
          depth: GhinaDepth.lg,
          borderRadius: GhinaRadii.rXl,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          onTap: busy ? null : onTap,
          onLongPress: busy ? null : onEdit,
          semanticLabel: '${prayer.label}, ${status?.label ?? 'belum diisi'}',
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: filled ? sw.edge : st.color.tint(g.brightness),
                  borderRadius: GhinaRadii.rLg,
                ),
                child: Icon(
                  filled ? prayerStatusIcon(status) : st.icon,
                  color: filled ? sw.on : st.color.base,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prayer.label,
                      style: GhinaType.h3.w(900).copyWith(color: fg),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyS.copyWith(color: sub),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: GhinaMotion.fast,
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: filled
                    ? Container(
                        key: ValueKey('done-${status.wire}'),
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          status.isPrayed
                              ? Icons.check_rounded
                              : prayerStatusIcon(status),
                          color: sw.base,
                          size: 22,
                        ),
                      )
                    : Container(
                        key: const ValueKey('todo'),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: g.border, width: 3),
                        ),
                      ),
              ),
              Semantics(
                button: true,
                label: 'Pilih status ${prayer.label}',
                child: GestureDetector(
                  key: ValueKey('prayer-more-${prayer.wire}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: busy ? null : onEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: filled ? sw.on : g.textMuted,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (pop case (final n, final xp))
          Positioned(
            right: 70,
            top: 6,
            child: XpPop(key: ValueKey('pop-$n'), xp: xp),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- sunnah

class _SunnahCard extends StatelessWidget {
  const _SunnahCard({
    required this.day,
    required this.entries,
    required this.busy,
    required this.onToggle,
    required this.onRakaat,
  });

  final DateTime day;
  final Map<Prayer, PrayerEntry> entries;
  final Set<Prayer> busy;
  final void Function(Prayer p, bool done) onToggle;
  final void Function(Prayer p, int? rakaat) onRakaat;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final done = [
      for (final p in Prayer.sunnah)
        if (entries[p] != null) p,
    ];
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SUNNAH HARIAN',
                  style: GhinaType.overline.copyWith(color: g.textSecondary),
                ),
              ),
              Text(
                '+${XpRules.sunnah} XP / salat',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final p in Prayer.sunnah) ...[
                if (p != Prayer.sunnah.first) const SizedBox(width: 8),
                Expanded(
                  child: _SunnahChip(
                    key: ValueKey('sunnah-${p.wire}'),
                    prayer: p,
                    done: entries[p] != null,
                    onTap: busy.contains(p)
                        ? null
                        : () => onToggle(p, entries[p] == null),
                  ),
                ),
              ],
            ],
          ),
          for (final p in done) ...[
            const SizedBox(height: 10),
            _RakaatStepper(
              key: ValueKey('rakaat-${p.wire}'),
              prayer: p,
              rakaat: entries[p]?.rakaat,
              enabled: !busy.contains(p),
              onChanged: (r) => onRakaat(p, r),
            ),
          ],
        ],
      ),
    );
  }
}

class _SunnahChip extends StatelessWidget {
  const _SunnahChip({
    super.key,
    required this.prayer,
    required this.done,
    required this.onTap,
  });

  final Prayer prayer;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final st = prayerStyles[prayer]!;
    final sw = st.color;
    return ChunkySurface(
      color: done ? sw.base : g.surface,
      edgeColor: done ? sw.edge : g.borderEdge,
      borderColor: done ? null : g.border,
      depth: GhinaDepth.md,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      onTap: onTap,
      semanticLabel: '${prayer.label}, ${done ? 'sudah' : 'belum'}',
      child: Column(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : st.icon,
            color: done ? sw.on : sw.base,
            size: 24,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              prayer.label,
              maxLines: 1,
              style: GhinaType.bodyS
                  .w(900)
                  .copyWith(color: done ? sw.on : g.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RakaatStepper extends StatelessWidget {
  const _RakaatStepper({
    super.key,
    required this.prayer,
    required this.rakaat,
    required this.enabled,
    required this.onChanged,
  });

  final Prayer prayer;
  final int? rakaat;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final options = rakaatOptions(prayer);
    final r = rakaat;
    final i = r == null ? -1 : options.indexOf(r);
    final canDown = enabled && r != null;
    final canUp = enabled && i < options.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rLg,
      ),
      child: Row(
        children: [
          Icon(
            prayerStyles[prayer]!.icon,
            size: 18,
            color: prayerStyles[prayer]!.color.base,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              prayer.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
          ),
          ChunkyIconButton(
            icon: Icons.remove_rounded,
            size: 34,
            tooltip: 'Kurangi rakaat ${prayer.label}',
            onPressed: canDown
                ? () => onChanged(i <= 0 ? null : options[i - 1])
                : null,
          ),
          SizedBox(
            width: 78,
            child: Text(
              r == null ? 'Rakaat?' : '$r rakaat',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: GhinaType.bodyS
                  .w(900)
                  .copyWith(color: r == null ? g.textMuted : g.textPrimary),
            ),
          ),
          ChunkyIconButton(
            icon: Icons.add_rounded,
            size: 34,
            tooltip: 'Tambah rakaat ${prayer.label}',
            onPressed: canUp ? () => onChanged(options[i + 1]) : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- stats

class _Stats extends StatelessWidget {
  const _Stats({
    required this.today,
    required this.month,
    required this.entries,
  });

  final DateTime today;
  final YearMonth month;
  final List<PrayerEntry> entries;

  @override
  Widget build(BuildContext context) {
    final streak = completeDayStreak(entries, today);
    final report = buildPrayerReport(
      entries,
      from: month.start,
      to: startOfDay(month.end),
      today: today,
    );
    final todayCount = _prayedCount(
      prayerEntriesByDate(entries)[dateKey(today)],
    );
    final score = report.score;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _MiniStat(
              icon: Icons.local_fire_department_rounded,
              value: '$streak hari',
              label: 'Streak 5/5',
              color: GhinaColors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniStat(
              icon: Icons.today_rounded,
              value: '$todayCount/5',
              label: 'Hari ini',
              color: GhinaColors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniStat(
              icon: Icons.speed_rounded,
              value: score == null ? '–' : '$score',
              label: 'Skor ${Fmt.monthName(month.month)}',
              color: GhinaColors.blue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact stacked stat (icon, big value, label) for a 3-column row.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          Icon(icon, color: color.base, size: 26),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: GhinaType.h2.w(900), maxLines: 1),
          ),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- heatmap

class _MonthHeatmap extends StatelessWidget {
  const _MonthHeatmap({
    required this.month,
    required this.today,
    required this.selected,
    required this.byDate,
    required this.loading,
    required this.onMonth,
    required this.onTap,
  });

  final YearMonth month;
  final DateTime today;
  final DateTime selected;
  final _DayMap byDate;
  final bool loading;
  final ValueChanged<YearMonth> onMonth;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final isCurrent = month == YearMonth.of(today);
    final lead = month.start.weekday - 1;
    final dim = daysInMonth(month.year, month.month);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(Fmt.monthYear(month.start), style: GhinaType.h3),
            ),
            ChunkyIconButton(
              icon: Icons.chevron_left_rounded,
              size: 36,
              tooltip: 'Bulan sebelumnya',
              onPressed: () => onMonth(month.previous),
            ),
            const SizedBox(width: 8),
            ChunkyIconButton(
              icon: Icons.chevron_right_rounded,
              size: 36,
              tooltip: 'Bulan berikutnya',
              onPressed: isCurrent ? null : () => onMonth(month.next),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (loading)
          const Skeleton(height: 220, radius: 16)
        else
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            children: [
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= dim; d++)
                _HeatCell(
                  day: DateTime(month.year, month.month, d),
                  entries:
                      byDate[dateKey(DateTime(month.year, month.month, d))],
                  today: today,
                  selected: selected,
                  onTap: onTap,
                ),
            ],
          ),
        const SizedBox(height: 12),
        const PrayerStatusLegend(),
      ],
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.day,
    required this.entries,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final Map<Prayer, PrayerEntry>? entries;
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final future = day.isAfter(today);
    final isToday = isSameDay(day, today);
    final isSel = isSameDay(day, selected);
    final count = _prayedCount(entries);
    final full = count == 5;
    return GestureDetector(
      onTap: future ? null : () => onTap(day),
      child: Semantics(
        button: !future,
        label: '${day.day}: $count dari 5 salat',
        child: Container(
          decoration: BoxDecoration(
            color: future
                ? null
                : full
                ? GhinaColors.green.tint(g.brightness)
                : g.surfaceAlt,
            borderRadius: GhinaRadii.rMd,
            border: isSel
                ? Border.all(color: GhinaColors.blue.base, width: 3)
                : isToday
                ? Border.all(color: GhinaColors.green.base, width: 2)
                : future
                ? Border.all(color: g.border, width: 1.5)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: GhinaType.bodyS
                        .w(900)
                        .copyWith(color: future ? g.textMuted : g.textPrimary),
                  ),
                ),
              ),
              if (!future) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _StatusDots(entries: entries, size: 6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
