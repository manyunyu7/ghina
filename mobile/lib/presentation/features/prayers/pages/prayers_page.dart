import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' show XpRules;
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/rewards/rewards.dart';

/// Look of each prayer tile.
typedef _PrayerStyle = ({IconData icon, String time, ChunkySwatch color});

const Map<Prayer, _PrayerStyle> _styles = {
  Prayer.subuh: (
    icon: Icons.wb_twilight_rounded,
    time: 'Fajar',
    color: GhinaColors.purple,
  ),
  Prayer.dzuhur: (
    icon: Icons.wb_sunny_rounded,
    time: 'Siang',
    color: GhinaColors.yellow,
  ),
  Prayer.ashar: (
    icon: Icons.brightness_medium_rounded,
    time: 'Sore',
    color: GhinaColors.orange,
  ),
  Prayer.maghrib: (
    icon: Icons.nights_stay_rounded,
    time: 'Senja',
    color: GhinaColors.pink,
  ),
  Prayer.isya: (
    icon: Icons.dark_mode_rounded,
    time: 'Malam',
    color: GhinaColors.blue,
  ),
};

const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Five daily prayers: chunky toggles for the chosen day, a week strip, stats
/// and a month heatmap (tap a day to edit it).
class PrayersPage extends ConsumerStatefulWidget {
  const PrayersPage({super.key});

  @override
  ConsumerState<PrayersPage> createState() => _PrayersPageState();
}

class _PrayersPageState extends ConsumerState<PrayersPage> {
  DateTime? _selected;
  YearMonth? _month;
  final _busy = <Prayer>{};
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

  Future<void> _toggle(DateTime day, Prayer p, Set<Prayer> doneBefore) async {
    if (_busy.contains(p)) return;
    setState(() => _busy.add(p));
    final rewards = RewardTracker.start(ref);
    final r = await ref.read(togglePrayerProvider)(day, p);
    if (!mounted) return;
    setState(() => _busy.remove(p));
    switch (r) {
      case Ok(:final value):
        if (!value) {
          HapticFeedback.selectionClick();
          return;
        }
        HapticFeedback.mediumImpact();
        final nowAll = {...doneBefore, p}.length == Prayer.values.length;
        if (nowAll) {
          await showCelebration(
            context,
            title: 'Lima waktu lengkap! 🕌',
            subtitle: isSameDay(day, _today)
                ? 'Semua salat hari ini sudah tercatat. MasyaAllah, keren!'
                : 'Semua salat ${Fmt.dateLong(day)} sudah tercatat.',
            stats: const [
              CelebrationStat(
                label: 'Bonus',
                value: '+${XpRules.allPrayersBonus} XP',
                icon: Icons.bolt_rounded,
                color: GhinaColors.yellow,
              ),
            ],
          );
        }
        if (mounted) await rewards.finish(context);
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

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

    final byDate = <String, Set<Prayer>>{
      ...prayersByDate(monthAsync.value ?? const []),
      ...prayersByDate(recent.value ?? const []),
    };

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Salat')),
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
                done: byDate[dateKey(selected)]?.length ?? 0,
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
              else
                for (final p in Prayer.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PrayerTile(
                      key: ValueKey('prayer-${p.wire}'),
                      prayer: p,
                      done: byDate[dateKey(selected)]?.contains(p) ?? false,
                      busy: _busy.contains(p),
                      onTap: () => _toggle(
                        selected,
                        p,
                        byDate[dateKey(selected)] ?? const {},
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              _Stats(today: today, month: month, byDate: byDate),
              const SizedBox(height: 28),
              SectionHeader(
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

// ---------------------------------------------------------------- header

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.today,
    required this.done,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime day;
  final DateTime today;
  final int done;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final all = done == Prayer.values.length;
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
                    label: all ? 'Lengkap $done/5' : '$done/5 salat',
                    icon: all
                        ? Icons.check_circle_rounded
                        : Icons.mosque_rounded,
                    color: all ? GhinaColors.green : GhinaColors.blue,
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
  final Map<String, Set<Prayer>> byDate;
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
                final count = byDate[dateKey(d)]?.length ?? 0;
                final isSel = isSameDay(d, selected);
                final full = count == Prayer.values.length;
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
                            value: count / Prayer.values.length,
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

// ---------------------------------------------------------------- tile

class _PrayerTile extends StatefulWidget {
  const _PrayerTile({
    super.key,
    required this.prayer,
    required this.done,
    required this.busy,
    required this.onTap,
  });

  final Prayer prayer;
  final bool done;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_PrayerTile> createState() => _PrayerTileState();
}

class _PrayerTileState extends State<_PrayerTile> {
  int _pops = 0;

  @override
  void didUpdateWidget(covariant _PrayerTile old) {
    super.didUpdateWidget(old);
    if (widget.done && !old.done) _pops++;
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final st = _styles[widget.prayer]!;
    final sw = st.color;
    final done = widget.done;
    final fg = done ? sw.on : g.textPrimary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChunkySurface(
          color: done ? sw.base : g.surface,
          edgeColor: done ? sw.edge : g.borderEdge,
          borderColor: done ? null : g.border,
          depth: GhinaDepth.lg,
          borderRadius: GhinaRadii.rXl,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: widget.busy ? null : widget.onTap,
          semanticLabel: '${widget.prayer.label}, ${done ? 'sudah' : 'belum'}',
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: done ? sw.edge : sw.tint(g.brightness),
                  borderRadius: GhinaRadii.rLg,
                ),
                child: Icon(st.icon, color: done ? sw.on : sw.base, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.prayer.label,
                      style: GhinaType.h3.w(900).copyWith(color: fg),
                    ),
                    Text(
                      done ? 'Sudah, alhamdulillah' : st.time,
                      style: GhinaType.bodyS.copyWith(
                        color: done
                            ? sw.on.withValues(alpha: 0.9)
                            : g.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: GhinaMotion.fast,
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: done
                    ? Container(
                        key: const ValueKey('done'),
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: sw.base,
                          size: 24,
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
            ],
          ),
        ),
        if (_pops > 0)
          Positioned(
            right: 56,
            top: 6,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_pops),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(
                  opacity: (t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3).clamp(
                    0.0,
                    1.0,
                  ),
                  child: Transform.translate(
                    offset: Offset(0, -26 * t),
                    child: Transform.scale(
                      scale: 0.8 + 0.4 * (t < 0.3 ? t / 0.3 : 1),
                      child: child,
                    ),
                  ),
                ),
                child: const XpBadge(xp: XpRules.prayer, plus: true),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- stats

class _Stats extends StatelessWidget {
  const _Stats({
    required this.today,
    required this.month,
    required this.byDate,
  });

  final DateTime today;
  final YearMonth month;
  final Map<String, Set<Prayer>> byDate;

  @override
  Widget build(BuildContext context) {
    // Streak of full (5/5) days; today still counts as "in progress".
    var cursor = today;
    if ((byDate[dateKey(cursor)]?.length ?? 0) < 5) {
      cursor = addDays(cursor, -1);
    }
    var streak = 0;
    while ((byDate[dateKey(cursor)]?.length ?? 0) >= 5) {
      streak++;
      cursor = addDays(cursor, -1);
    }
    // Month completion.
    final isCurrent = month.contains(today);
    final isPast = month.compareTo(YearMonth.of(today)) < 0;
    final elapsed = isCurrent
        ? today.day
        : (isPast ? daysInMonth(month.year, month.month) : 0);
    var doneCount = 0;
    for (var d = 1; d <= elapsed; d++) {
      doneCount +=
          byDate[dateKey(DateTime(month.year, month.month, d))]?.length ?? 0;
    }
    final pct = elapsed == 0 ? 0 : (doneCount / (elapsed * 5) * 100).round();
    final todayCount = byDate[dateKey(today)]?.length ?? 0;

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
              icon: Icons.percent_rounded,
              value: '$pct%',
              label: Fmt.monthName(month.month),
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
  final Map<String, Set<Prayer>> byDate;
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
                  count:
                      byDate[dateKey(DateTime(month.year, month.month, d))]
                          ?.length ??
                      0,
                  today: today,
                  selected: selected,
                  onTap: onTap,
                ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _legend(context, GhinaColors.green.base, 'Lengkap'),
            _legend(
              context,
              GhinaColors.orange.base.withValues(alpha: 0.7),
              'Sebagian',
            ),
            _legend(context, GhinaColors.red.tint(g.brightness), 'Terlewat'),
          ],
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: c, borderRadius: GhinaRadii.rSm),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
      ),
    ],
  );
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.day,
    required this.count,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final int count;
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final future = day.isAfter(today);
    final isToday = isSameDay(day, today);
    final isSel = isSameDay(day, selected);
    final Color? bg;
    final Color fg;
    if (future) {
      bg = null;
      fg = g.textMuted;
    } else if (count >= 5) {
      bg = GhinaColors.green.base;
      fg = Colors.white;
    } else if (count > 0) {
      bg = GhinaColors.orange.base.withValues(alpha: 0.3 + 0.12 * count);
      fg = Colors.white;
    } else if (isToday) {
      bg = null;
      fg = g.textPrimary;
    } else {
      bg = GhinaColors.red.tint(g.brightness);
      fg = g.textMuted;
    }
    return GestureDetector(
      onTap: future ? null : () => onTap(day),
      child: Semantics(
        button: !future,
        label: '${day.day}: $count dari 5 salat',
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: GhinaRadii.rMd,
            border: isSel
                ? Border.all(color: GhinaColors.blue.base, width: 3)
                : isToday
                ? Border.all(color: GhinaColors.green.base, width: 2)
                : future
                ? Border.all(color: g.border, width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${day.day}',
              style: GhinaType.bodyS.w(900).copyWith(color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
