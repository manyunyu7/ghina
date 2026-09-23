import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/game/game.dart' hide MascotMood;
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';

const weekdayInitials = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Month calendar of the streak: logged days glow orange, frozen days show
/// ice, missed days are faint red, today (pending) gets an orange ring.
class StreakCalendar extends ConsumerStatefulWidget {
  const StreakCalendar({super.key, required this.today});

  final GameDate today;

  @override
  ConsumerState<StreakCalendar> createState() => _StreakCalendarState();
}

class _StreakCalendarState extends ConsumerState<StreakCalendar> {
  late GameMonth _month = GameMonth.of(widget.today);

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final days = ref.watch(streakCalendarProvider(_month));
    final isCurrent = _month == GameMonth.of(widget.today);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                Fmt.monthYear(DateTime(_month.year, _month.month)),
                style: GhinaType.h3,
              ),
            ),
            ChunkyIconButton(
              icon: Icons.chevron_left_rounded,
              size: 36,
              tooltip: 'Bulan sebelumnya',
              onPressed: () => setState(() => _month = _month.previous),
            ),
            const SizedBox(width: 8),
            ChunkyIconButton(
              icon: Icons.chevron_right_rounded,
              size: 36,
              tooltip: 'Bulan berikutnya',
              onPressed: isCurrent
                  ? null
                  : () => setState(() => _month = _month.next),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final w in weekdayInitials)
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
        switch (days) {
          AsyncData(:final value) => _grid(context, value),
          _ => const Skeleton(height: 220, radius: 16),
        },
        const SizedBox(height: 10),
        const _Legend(),
      ],
    );
  }

  Widget _grid(BuildContext context, List<CalendarDay> days) {
    final lead = _month.firstDay.weekday - 1; // Monday first
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (final d in days) _DayCell(day: d, isToday: d.date == widget.today),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.isToday});

  final CalendarDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final orange = GhinaColors.orange;
    final blue = GhinaColors.blue;
    final (
      Color? bg,
      Color fg,
      Border? border,
      IconData? icon,
    ) = switch (day.status) {
      StreakDayStatus.logged => (orange.base, Colors.white, null, null),
      StreakDayStatus.frozen => (
        blue.tint(g.brightness),
        g.isDark ? blue.base : blue.edge,
        Border.all(color: blue.tintBorder(g.brightness), width: 2),
        Icons.ac_unit_rounded,
      ),
      StreakDayStatus.missed => (
        GhinaColors.red.tint(g.brightness),
        g.textMuted,
        null,
        null,
      ),
      StreakDayStatus.pending => (
        null,
        g.textPrimary,
        Border.all(color: orange.base, width: 2.5),
        null,
      ),
      StreakDayStatus.none => (
        null,
        g.textSecondary,
        isToday ? Border.all(color: g.border, width: 2) : null,
        null,
      ),
    };
    return Semantics(
      label: '${day.date.day}: ${_statusLabel(day.status)}',
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, size: 18, color: fg)
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${day.date.day}',
                  style: GhinaType.bodyS.w(900).copyWith(color: fg),
                ),
              ),
      ),
    );
  }

  static String _statusLabel(StreakDayStatus s) => switch (s) {
    StreakDayStatus.logged => 'tercatat',
    StreakDayStatus.frozen => 'dibekukan',
    StreakDayStatus.missed => 'terlewat',
    StreakDayStatus.pending => 'hari ini, belum dicatat',
    StreakDayStatus.none => 'kosong',
  };
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget item(Color c, String label, {IconData? icon}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: icon == null
              ? null
              : Icon(icon, size: 10, color: Colors.white),
        ),
        const SizedBox(width: 5),
        Text(label, style: GhinaType.caption.copyWith(color: g.textSecondary)),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item(GhinaColors.orange.base, 'Tercatat'),
        item(GhinaColors.blue.base, 'Freeze', icon: Icons.ac_unit_rounded),
        item(GhinaColors.red.tint(g.brightness), 'Terlewat'),
      ],
    );
  }
}
