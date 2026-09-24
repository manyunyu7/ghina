import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

/// Note color picker sheet (default + the 11 palette ids). [onChanged] fires
/// right away so the editor recolors live.
Future<void> showNoteColorSheet(
  BuildContext context, {
  required String? selected,
  required ValueChanged<String?> onChanged,
}) => showChunkyBottomSheet<void>(
  context,
  title: 'Warna catatan',
  showClose: true,
  builder: (_) => NoteColorPalette(selected: selected, onChanged: onChanged),
);

class NoteColorPalette extends StatefulWidget {
  const NoteColorPalette({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  State<NoteColorPalette> createState() => _NoteColorPaletteState();
}

class _NoteColorPaletteState extends State<NoteColorPalette> {
  late String? _sel = widget.selected;

  void _pick(String? id) {
    setState(() => _sel = id);
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget dot({
      required String? id,
      required Color color,
      required String label,
    }) {
      final selected = _sel == id;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          key: ValueKey('note-color-${id ?? 'none'}'),
          onTap: () => _pick(id),
          child: AnimatedContainer(
            duration: GhinaMotion.fast,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? GhinaColors.green.base : g.border,
                width: selected ? 3 : 2,
              ),
            ),
            child: id == null
                ? Icon(
                    selected ? Icons.check_rounded : Icons.format_color_reset,
                    color: selected ? GhinaColors.green.base : g.textMuted,
                  )
                : selected
                ? Icon(Icons.check_rounded, color: g.textPrimary)
                : null,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        dot(id: null, color: g.surface, label: 'Tanpa warna'),
        for (final c in noteColors)
          dot(
            id: c.id,
            color: CategoryColors.parse(g.isDark ? c.dark : c.light),
            label: c.label,
          ),
      ],
    );
  }
}
