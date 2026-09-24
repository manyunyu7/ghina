import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// Chunky time picker sheet (same look as the Tugas one): quick presets, an hour grid and 5-minute steps.
/// Returns `HH:mm`, or null when dismissed.
Future<String?> showContentTimePicker(
  BuildContext context, {
  String? initial,
  String title = 'Pilih jam',
}) => showChunkyBottomSheet<String>(
  context,
  title: title,
  showClose: true,
  builder: (c) => _TimeSheet(initial: isHm(initial) ? initial! : '09:00'),
);

class _TimeSheet extends StatefulWidget {
  const _TimeSheet({required this.initial});
  final String initial;

  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  late int _h = int.parse(widget.initial.substring(0, 2));
  late int _m = int.parse(widget.initial.substring(3, 5));

  static const _presets = [
    '07:00',
    '09:00',
    '12:00',
    '15:00',
    '19:00',
    '21:00',
  ];

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final value = formatHm(_h, _m);
    final minutes = [for (var m = 0; m < 60; m += 5) m, if (_m % 5 != 0) _m]
      ..sort();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Pulse(
            trigger: value,
            child: Text(
              _hm(value),
              key: const ValueKey('time-picker-value'),
              style: GhinaType.moneyXL.copyWith(color: g.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Cepat'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _presets)
              ChunkyChip(
                label: _hm(p),
                selected: p == value,
                color: GhinaColors.blue,
                onTap: () => setState(() {
                  _h = int.parse(p.substring(0, 2));
                  _m = int.parse(p.substring(3, 5));
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const FieldLabel('Jam'),
        _Grid(
          count: 6,
          children: [
            for (var h = 0; h < 24; h++)
              _Cell(
                label: h.toString().padLeft(2, '0'),
                selected: h == _h,
                onTap: () => setState(() => _h = h),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const FieldLabel('Menit'),
        _Grid(
          count: 6,
          children: [
            for (final m in minutes)
              _Cell(
                label: m.toString().padLeft(2, '0'),
                selected: m == _m,
                color: GhinaColors.purple,
                onTap: () => setState(() => _m = m),
              ),
          ],
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          label: 'Pakai ${_hm(value)}',
          onPressed: () => Navigator.of(context).pop(value),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.count, required this.children});
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = 6.0;
      final w = (c.maxWidth - gap * (count - 1)) / count;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final x in children) SizedBox(width: w, child: x)],
      );
    },
  );
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = GhinaColors.blue,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkySurface(
      color: selected ? color.base : g.surface,
      edgeColor: selected ? color.edge : g.borderEdge,
      borderColor: selected ? color.base : g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rMd,
      onTap: onTap,
      semanticLabel: label,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: GhinaType.body
                .w(900)
                .copyWith(color: selected ? color.on : g.textPrimary),
          ),
        ),
      ),
    );
  }
}

String _hm(String hm) => hm.replaceAll(':', '.');
