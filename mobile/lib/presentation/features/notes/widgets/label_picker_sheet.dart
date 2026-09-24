import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import 'note_visuals.dart';

/// Label choices for a note, with inline "Buat label baru". [onChanged] fires
/// after every toggle (so a swiped-away sheet keeps the change).
Future<void> showLabelPickerSheet(
  BuildContext context, {
  required List<String> selected,
  required ValueChanged<List<String>> onChanged,
}) => showChunkyBottomSheet<void>(
  context,
  title: 'Label',
  showClose: true,
  builder: (_) => LabelPicker(selected: selected, onChanged: onChanged),
);

/// Default color for a new label (deterministic by name, web palette).
String labelColorFor(String name) =>
    CategoryColors.toHex(CategoryColors.forKey(name.toLowerCase()));

class LabelPicker extends ConsumerStatefulWidget {
  const LabelPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends ConsumerState<LabelPicker> {
  late List<String> _ids = [...widget.selected];
  final _name = TextEditingController();
  String? _error;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      _ids = _ids.contains(id)
          ? [
              for (final x in _ids)
                if (x != id) x,
            ]
          : [..._ids, id];
    });
    widget.onChanged(List.unmodifiable(_ids));
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Tulis nama labelnya dulu');
      return;
    }
    setState(() => _creating = true);
    final r = await ref.read(createNoteLabelProvider)(
      NoteLabelInput(name: name, color: labelColorFor(name)),
    );
    if (!mounted) return;
    setState(() => _creating = false);
    switch (r) {
      case Ok(:final value):
        _name.clear();
        _error = null;
        if (!_ids.contains(value.id)) _toggle(value.id);
      case Err(:final failure):
        setState(
          () => _error = failure is ValidationFailure
              ? failure.message
              : 'Label belum bisa dibuat. Coba lagi, ya',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final labels = ref.watch(watchNoteLabelsProvider).value ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (labels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Belum ada label. Bikin yang pertama di bawah, yuk!',
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
          ),
        for (final l in labels)
          _LabelRow(
            label: l,
            selected: _ids.contains(l.id),
            onTap: () => _toggle(l.id),
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ChunkyTextField(
                key: const ValueKey('label-new-name'),
                hint: 'Label baru, mis. Belanja',
                controller: _name,
                errorText: _error,
                prefixIcon: Icons.label_outline_rounded,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(labelNameMax),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ChunkyIconButton(
                key: const ValueKey('label-new-add'),
                icon: _creating ? Icons.hourglass_top_rounded : Icons.add,
                color: GhinaColors.green,
                tooltip: 'Buat label',
                onPressed: _creating ? null : _create,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final NoteLabel label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = labelSwatch(label);
    return InkWell(
      key: ValueKey('label-pick-${label.id}'),
      onTap: onTap,
      borderRadius: GhinaRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: s.tint(g.brightness),
                borderRadius: GhinaRadii.rSm,
              ),
              child: Icon(Icons.label_rounded, size: 18, color: s.base),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label.name,
                style: GhinaType.h3.w(800).copyWith(color: g.textPrimary),
              ),
            ),
            if (label.pinnedTab)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.tab_rounded, size: 18, color: g.textMuted),
              ),
            AnimatedContainer(
              duration: GhinaMotion.fast,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? GhinaColors.green.base : Colors.transparent,
                borderRadius: GhinaRadii.rSm,
                border: Border.all(
                  color: selected ? GhinaColors.green.edge : g.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
