import 'package:flutter/material.dart';

import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../design_system/design_system.dart';
import 'form_fields.dart';
import 'month_switcher.dart';

/// Tappable date field that opens [showGhinaDatePicker].
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.firstDate,
    this.lastDate,
    this.today,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String? helper;

  /// Earliest / latest pickable day (inclusive). Null = unbounded.
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// "Today" for highlighting and the "Hari ini" button (defaults to now).
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PickerField(
          label: label,
          value: Fmt.dateFull(value),
          trailingIcon: Icons.calendar_month_rounded,
          leading: Icon(Icons.event_rounded, color: GhinaColors.blue.base),
          onTap: () async {
            final d = await showGhinaDatePicker(
              context,
              initial: value,
              title: label,
              firstDate: firstDate,
              lastDate: lastDate,
              today: today,
            );
            if (d != null) onChanged(d);
          },
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              helper!,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

/// Chunky Indonesian calendar in a bottom sheet — the app's one date picker
/// (used instead of Material's `showDatePicker` so every form looks and
/// behaves the same: bottom sheet, Monday-first weeks, "Hari ini" shortcut).
///
/// Returns the picked day keeping [initial]'s time of day, or null when
/// dismissed. Days outside [firstDate]..[lastDate] are disabled.
Future<DateTime?> showGhinaDatePicker(
  BuildContext context, {
  required DateTime initial,
  String title = 'Pilih tanggal',
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? today,
}) => showChunkyBottomSheet<DateTime>(
  context,
  title: title,
  showClose: true,
  builder: (c) => _CalendarSheet(
    initial: initial,
    first: firstDate == null ? null : startOfDay(firstDate),
    last: lastDate == null ? null : startOfDay(lastDate),
    today: startOfDay(today ?? DateTime.now()),
  ),
);

class _CalendarSheet extends StatefulWidget {
  const _CalendarSheet({
    required this.initial,
    required this.today,
    this.first,
    this.last,
  });
  final DateTime initial;
  final DateTime today;
  final DateTime? first;
  final DateTime? last;

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late YearMonth _month = YearMonth.of(_clamp(widget.initial));
  static const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  DateTime _clamp(DateTime d) {
    final f = widget.first, l = widget.last;
    if (f != null && d.isBefore(f)) return f;
    if (l != null && startOfDay(d).isAfter(l)) return l;
    return d;
  }

  bool _allowed(DateTime day) =>
      (widget.first == null || !day.isBefore(widget.first!)) &&
      (widget.last == null || !day.isAfter(widget.last!));

  bool get _canPrev =>
      widget.first == null ||
      _month.start.isAfter(YearMonth.of(widget.first!).start);
  bool get _canNext =>
      widget.last == null ||
      _month.start.isBefore(YearMonth.of(widget.last!).start);

  DateTime _withTime(DateTime d) => DateTime(
    d.year,
    d.month,
    d.day,
    widget.initial.hour,
    widget.initial.minute,
  );

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final today = widget.today;
    final first = _month.start;
    final lead = (first.weekday + 6) % 7; // Monday first
    final days = daysInMonth(_month.year, _month.month);
    final rows = ((lead + days) / 7).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ChunkyIconButton(
              icon: Icons.chevron_left_rounded,
              size: 40,
              tooltip: 'Bulan sebelumnya',
              onPressed: _canPrev
                  ? () => setState(() => _month = _month.previous)
                  : null,
            ),
            Expanded(
              child: Text(
                monthLabel(_month),
                textAlign: TextAlign.center,
                style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
              ),
            ),
            ChunkyIconButton(
              icon: Icons.chevron_right_rounded,
              size: 40,
              tooltip: 'Bulan berikutnya',
              onPressed: _canNext
                  ? () => setState(() => _month = _month.next)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: GhinaType.caption.w(900).copyWith(color: g.textMuted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(context, r * 7 + col - lead + 1, days)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        ChunkyButton(
          label: 'Hari ini',
          variant: ChunkyButtonVariant.outline,
          size: ChunkyButtonSize.medium,
          expand: true,
          onPressed: _allowed(today)
              ? () => Navigator.of(context).pop(_withTime(today))
              : null,
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, int day, int days) {
    if (day < 1 || day > days) return const SizedBox(height: 42);
    final g = context.ghina;
    final d = DateTime(_month.year, _month.month, day);
    final enabled = _allowed(d);
    final sel = isSameDay(d, widget.initial);
    final isToday = isSameDay(d, widget.today);
    final sw = GhinaColors.blue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChunkySurface(
        color: sel ? sw.base : (isToday ? sw.tint(g.brightness) : g.surface),
        edgeColor: sel
            ? sw.edge
            : (isToday ? sw.tintBorder(g.brightness) : Colors.transparent),
        borderColor: isToday && !sel ? sw.tintBorder(g.brightness) : null,
        depth: sel || isToday ? GhinaDepth.sm : 0,
        borderRadius: GhinaRadii.rMd,
        semanticLabel: Fmt.dateLong(d),
        enabled: enabled,
        onTap: enabled ? () => Navigator.of(context).pop(_withTime(d)) : null,
        child: SizedBox(
          height: 38,
          child: Center(
            child: Text(
              '$day',
              style: GhinaType.body
                  .w(sel || isToday ? 900 : 700)
                  .copyWith(
                    color: !enabled
                        ? g.textMuted.withValues(alpha: 0.45)
                        : sel
                        ? sw.on
                        : (isToday ? sw.base : g.textPrimary),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
