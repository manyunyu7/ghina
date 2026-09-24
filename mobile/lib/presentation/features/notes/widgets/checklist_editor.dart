import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ids.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import 'note_visuals.dart';

/// Editable checklist: toggle, edit inline (Enter adds the next row), drag to
/// reorder, remove, "Hapus yang selesai". Every change goes to [onChanged].
class ChecklistEditor extends StatefulWidget {
  const ChecklistEditor({
    super.key,
    required this.items,
    required this.onChanged,
    required this.tone,
  });

  final List<ChecklistItem> items;
  final ValueChanged<List<ChecklistItem>> onChanged;
  final NoteTone tone;

  @override
  State<ChecklistEditor> createState() => ChecklistEditorState();
}

class ChecklistEditorState extends State<ChecklistEditor> {
  /// Latest list (updated synchronously; the parent's copy may lag a frame).
  late List<ChecklistItem> _items = widget.items;
  final _ctrls = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};

  TextEditingController _ctrl(ChecklistItem c) =>
      _ctrls.putIfAbsent(c.id, () => TextEditingController(text: c.text));
  FocusNode _node(String id) => _focus.putIfAbsent(id, FocusNode.new);

  @override
  void didUpdateWidget(ChecklistEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _items = widget.items;
    final ids = {for (final c in widget.items) c.id};
    for (final id in [..._ctrls.keys]) {
      if (!ids.contains(id)) {
        final c = _ctrls.remove(id);
        final f = _focus.remove(id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          c?.dispose();
          f?.dispose();
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Focuses the row [id] after the next frame (a row just added outside).
  void focusItem(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(id).requestFocus();
    });
  }

  void _emit(List<ChecklistItem> next) {
    _items = next;
    widget.onChanged(next);
  }

  /// Adds an empty row (after [afterId], or at the end) and focuses it.
  void addItem({String? afterId}) {
    final items = _items;
    if (items.length >= maxChecklistItems) {
      showToastBadge(
        context,
        message: 'Maksimal $maxChecklistItems item, ya',
        icon: Icons.info_rounded,
        color: GhinaColors.orange,
      );
      return;
    }
    final id = newId();
    final at = afterId == null
        ? items.length
        : items.indexWhere((c) => c.id == afterId) + 1;
    _emit(checklistAdd(items, '', id: id, index: at));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(id).requestFocus();
    });
  }

  void _remove(ChecklistItem c) {
    final items = _items;
    final i = items.indexWhere((x) => x.id == c.id);
    _emit(checklistRemove(items, c.id));
    if (i > 0) {
      final prev = items[i - 1].id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node(prev).requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final tone = widget.tone;
    final items = _items;
    final done = items.where((c) => c.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          proxyDecorator: (child, _, _) => Material(
            color: tone.face,
            elevation: 4,
            borderRadius: GhinaRadii.rMd,
            child: child,
          ),
          onReorderItem: (from, to) => _emit(checklistMove(_items, from, to)),
          itemBuilder: (context, i) {
            final c = items[i];
            return Row(
              key: ValueKey('check-row-${c.id}'),
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: tone.subtle.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                InkResponse(
                  key: ValueKey('check-toggle-$i'),
                  radius: 20,
                  onTap: () => _emit(checklistToggle(_items, c.id)),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AnimatedContainer(
                      duration: GhinaMotion.fast,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c.done
                            ? GhinaColors.green.base
                            : Colors.transparent,
                        borderRadius: GhinaRadii.rSm,
                        border: Border.all(
                          color: c.done ? GhinaColors.green.edge : tone.subtle,
                          width: 2,
                        ),
                      ),
                      child: c.done
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: ValueKey('check-text-$i'),
                    controller: _ctrl(c),
                    focusNode: _node(c.id),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(checklistTextMax),
                      FilteringTextInputFormatter.deny(RegExp(r'[\n\t]')),
                    ],
                    style: GhinaType.body.copyWith(
                      color: c.done ? tone.subtle : tone.text,
                      decoration: c.done ? TextDecoration.lineThrough : null,
                      decorationColor: tone.subtle,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Item',
                      hintStyle: GhinaType.body.copyWith(
                        color: tone.subtle.withValues(alpha: 0.6),
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (t) => _emit(checklistSetText(_items, c.id, t)),
                    onSubmitted: (_) => addItem(afterId: c.id),
                  ),
                ),
                IconButton(
                  key: ValueKey('check-remove-$i'),
                  tooltip: 'Hapus item',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: tone.subtle),
                  onPressed: () => _remove(c),
                ),
              ],
            );
          },
        ),
        Row(
          children: [
            TextButton.icon(
              key: const ValueKey('check-add'),
              onPressed: addItem,
              icon: Icon(Icons.add_rounded, color: GhinaColors.green.base),
              label: Text(
                'Item',
                style: GhinaType.body
                    .w(800)
                    .copyWith(color: GhinaColors.green.base),
              ),
            ),
            const Spacer(),
            if (done > 0)
              Flexible(
                flex: 1000,
                child: TextButton(
                  key: const ValueKey('check-clear-done'),
                  onPressed: () => _emit(checklistClearDone(_items)),
                  child: Text(
                    'Hapus $done yang selesai',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
