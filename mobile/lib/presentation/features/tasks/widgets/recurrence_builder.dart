import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../task_format.dart';

enum _Kind { none, daily, weekly, monthly }

/// Repeat rule editor: Tidak berulang / Harian / Mingguan (weekday toggles) /
/// Bulanan (day of month) + interval stepper and a human summary.
class RecurrenceBuilder extends StatelessWidget {
  const RecurrenceBuilder({
    super.key,
    required this.value,
    required this.onChanged,
    this.dueDay,
    this.errorText,
  });

  final Recurrence? value;
  final ValueChanged<Recurrence?> onChanged;

  /// Fills the defaults (weekday / day of month) like the use case does.
  final DateTime? dueDay;
  final String? errorText;

  _Kind get _kind => switch (value?.freq) {
    null => _Kind.none,
    RecurrenceFreq.daily => _Kind.daily,
    RecurrenceFreq.weekly => _Kind.weekly,
    RecurrenceFreq.monthly => _Kind.monthly,
  };

  void _setKind(_Kind k) {
    final interval = value?.interval ?? 1;
    onChanged(switch (k) {
      _Kind.none => null,
      _Kind.daily => Recurrence.daily(interval),
      _Kind.weekly => Recurrence.weekly(
        interval: interval,
        weekdays: [dueDay?.weekday ?? DateTime.monday],
      ),
      _Kind.monthly => Recurrence.monthly(
        interval: interval,
        monthDay: dueDay?.day ?? 1,
      ),
    });
  }

  Recurrence _with({int? interval, List<int>? weekdays, int? monthDay}) {
    final r = value!;
    return Recurrence(
      freq: r.freq,
      interval: interval ?? r.interval,
      weekdays: weekdays ?? r.weekdays,
      monthDay: monthDay ?? r.monthDay,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final r = value;
    final weekdays = r?.weekdays ?? [dueDay?.weekday ?? DateTime.monday];
    final monthDay = r?.monthDay ?? dueDay?.day ?? 1;
    return Shake(
      trigger: errorText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FieldLabel('Berulang', error: errorText != null),
          ChunkySegmented<_Kind>(
            segments: const [
              ChunkySegment(
                value: _Kind.none,
                label: 'Tidak',
                color: GhinaColors.gray,
              ),
              ChunkySegment(
                value: _Kind.daily,
                label: 'Harian',
                color: GhinaColors.purple,
              ),
              ChunkySegment(
                value: _Kind.weekly,
                label: 'Mingguan',
                color: GhinaColors.purple,
              ),
              ChunkySegment(
                value: _Kind.monthly,
                label: 'Bulanan',
                color: GhinaColors.purple,
              ),
            ],
            value: _kind,
            onChanged: _setKind,
          ),
          if (r != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Tiap',
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                const SizedBox(width: 10),
                ChunkyIconButton(
                  key: const ValueKey('interval-minus'),
                  icon: Icons.remove_rounded,
                  size: 40,
                  tooltip: 'Kurangi',
                  onPressed: r.interval > 1
                      ? () => onChanged(_with(interval: r.interval - 1))
                      : null,
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${r.interval}',
                    key: const ValueKey('interval-value'),
                    textAlign: TextAlign.center,
                    style: GhinaType.h2.copyWith(color: g.textPrimary),
                  ),
                ),
                ChunkyIconButton(
                  key: const ValueKey('interval-plus'),
                  icon: Icons.add_rounded,
                  size: 40,
                  tooltip: 'Tambah',
                  onPressed: r.interval < 365
                      ? () => onChanged(_with(interval: r.interval + 1))
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.freq.unit,
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
            if (r.freq == RecurrenceFreq.weekly) ...[
              const SizedBox(height: 12),
              DayToggleRow(
                keyPrefix: 'weekday',
                selected: weekdays.toSet(),
                onChanged: (next) {
                  if (next.isEmpty) return;
                  onChanged(_with(weekdays: next.toList()..sort()));
                },
              ),
            ],
            if (r.freq == RecurrenceFreq.monthly) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Tanggal',
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                  const SizedBox(width: 10),
                  ChunkyIconButton(
                    icon: Icons.remove_rounded,
                    size: 40,
                    tooltip: 'Tanggal sebelumnya',
                    onPressed: monthDay > 1
                        ? () => onChanged(_with(monthDay: monthDay - 1))
                        : null,
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '$monthDay',
                      textAlign: TextAlign.center,
                      style: GhinaType.h2.copyWith(color: g.textPrimary),
                    ),
                  ),
                  ChunkyIconButton(
                    icon: Icons.add_rounded,
                    size: 40,
                    tooltip: 'Tanggal berikutnya',
                    onPressed: monthDay < 31
                        ? () => onChanged(_with(monthDay: monthDay + 1))
                        : null,
                  ),
                ],
              ),
              if (monthDay > 28)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Bulan yang lebih pendek pakai tanggal terakhirnya.',
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            ChunkyCard(
              tinted: GhinaColors.purple,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              depth: 0,
              child: Row(
                children: [
                  Icon(Icons.repeat_rounded, color: GhinaColors.purple.base),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      recurrenceSummary(r, dueDay: dueDay),
                      key: const ValueKey('recurrence-summary'),
                      style: GhinaType.body
                          .w(800)
                          .copyWith(color: g.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 6),
            Text(
              errorText!,
              style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
            ),
          ],
        ],
      ),
    );
  }
}

/// Round weekday toggle (`Sen` … `Min`), also used by the area schedule.
class DayToggleRow extends StatelessWidget {
  const DayToggleRow({
    super.key,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'day',
  });

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var d = 1; d <= 7; d++) ...[
        if (d > 1) const SizedBox(width: 5),
        Expanded(
          child: _DayToggle(
            key: ValueKey('$keyPrefix-$d'),
            label: isoWeekdayShort[d - 1],
            selected: selected.contains(d),
            onTap: () {
              final next = {...selected};
              if (!next.remove(d)) next.add(d);
              onChanged(next);
            },
          ),
        ),
      ],
    ],
  );
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    const sw = GhinaColors.purple;
    return ChunkySurface(
      color: selected ? sw.base : g.surface,
      edgeColor: selected ? sw.edge : g.borderEdge,
      borderColor: selected ? sw.base : g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rMd,
      onTap: onTap,
      semanticLabel: label,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: GhinaType.bodyS
                .w(900)
                .copyWith(color: selected ? sw.on : g.textSecondary),
          ),
        ),
      ),
    );
  }
}
