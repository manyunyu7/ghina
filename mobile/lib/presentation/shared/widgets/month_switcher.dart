import 'package:flutter/material.dart';

import '../../../core/dates.dart';
import '../../../core/formatters.dart';
import '../../design_system/design_system.dart';

/// Month label for headers and copy (`September 2026`).
String monthLabel(YearMonth m) => Fmt.monthYear(m.start);

/// `‹  September 2026  ›` with a relative hint ("Bulan ini", "Bulan lalu");
/// tap the label to pick any month (the sheet has a "Bulan ini" shortcut).
/// Keys: `month-prev`, `month-label`, `month-next`.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.value,
    required this.onChanged,
    required this.current,
  });

  final YearMonth value;
  final ValueChanged<YearMonth> onChanged;

  /// Today's month, for the "Bulan ini" hint.
  final YearMonth current;

  String? get _hint {
    final diff = (value.year - current.year) * 12 + value.month - current.month;
    return switch (diff) {
      0 => 'Bulan ini',
      1 => 'Bulan depan',
      -1 => 'Bulan lalu',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final hint = _hint;
    return Row(
      children: [
        ChunkyIconButton(
          key: const ValueKey('month-prev'),
          icon: Icons.chevron_left_rounded,
          tooltip: 'Bulan sebelumnya',
          onPressed: () => onChanged(value.previous),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            borderRadius: GhinaRadii.rMd,
            depth: GhinaDepth.sm,
            semanticLabel: 'Pilih bulan',
            onTap: () async {
              final picked = await showMonthPickerSheet(
                context,
                value,
                current: current,
              );
              if (picked != null) onChanged(picked);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      monthLabel(value),
                      key: const ValueKey('month-label'),
                      maxLines: 1,
                      style: GhinaType.body
                          .w(900)
                          .copyWith(color: g.textPrimary, height: 1.1),
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint.toUpperCase(),
                      maxLines: 1,
                      style: GhinaType.caption
                          .w(900)
                          .copyWith(
                            color: GhinaColors.blue.base,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            height: 1.1,
                          ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ChunkyIconButton(
          key: const ValueKey('month-next'),
          icon: Icons.chevron_right_rounded,
          tooltip: 'Bulan berikutnya',
          onPressed: () => onChanged(value.next),
        ),
      ],
    );
  }
}

/// Month grid with year arrows in a bottom sheet. With [current], a
/// "Bulan ini" button jumps straight to it.
Future<YearMonth?> showMonthPickerSheet(
  BuildContext context,
  YearMonth initial, {
  YearMonth? current,
}) => showChunkyBottomSheet<YearMonth>(
  context,
  title: 'Pilih bulan',
  showClose: true,
  builder: (c) => _MonthGrid(initial: initial, current: current),
);

class _MonthGrid extends StatefulWidget {
  const _MonthGrid({required this.initial, this.current});
  final YearMonth initial;
  final YearMonth? current;

  @override
  State<_MonthGrid> createState() => _MonthGridState();
}

class _MonthGridState extends State<_MonthGrid> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ChunkyIconButton(
              icon: Icons.chevron_left_rounded,
              size: 40,
              tooltip: 'Tahun sebelumnya',
              onPressed: () => setState(() => _year--),
            ),
            Expanded(
              child: Text(
                '$_year',
                textAlign: TextAlign.center,
                style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
              ),
            ),
            ChunkyIconButton(
              icon: Icons.chevron_right_rounded,
              size: 40,
              tooltip: 'Tahun berikutnya',
              onPressed: () => setState(() => _year++),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            for (var m = 1; m <= 12; m++)
              Builder(
                builder: (context) {
                  final sel =
                      widget.initial.year == _year && widget.initial.month == m;
                  final sw = GhinaColors.blue;
                  return ChunkySurface(
                    color: sel ? sw.base : g.surface,
                    edgeColor: sel ? sw.edge : g.borderEdge,
                    borderColor: sel ? null : g.border,
                    depth: GhinaDepth.sm,
                    borderRadius: GhinaRadii.rMd,
                    semanticLabel: Fmt.monthName(m),
                    onTap: () => Navigator.of(context).pop(YearMonth(_year, m)),
                    child: Center(
                      child: Text(
                        Fmt.monthShort(m),
                        style: GhinaType.body
                            .w(900)
                            .copyWith(color: sel ? sw.on : g.textPrimary),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        if (widget.current case final now?) ...[
          const SizedBox(height: 14),
          ChunkyButton(
            label: 'Bulan ini',
            variant: ChunkyButtonVariant.outline,
            size: ChunkyButtonSize.medium,
            expand: true,
            onPressed: () => Navigator.of(context).pop(now),
          ),
        ],
      ],
    );
  }
}
