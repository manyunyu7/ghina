import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/label_picker_sheet.dart' show labelColorFor;
import '../widgets/note_visuals.dart';

/// Kelola label: rename, color, "tampilkan sebagai tab", drag to reorder,
/// delete (warns how many notes lose it).
class NoteLabelsPage extends ConsumerWidget {
  const NoteLabelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(watchNoteLabelsProvider);
    final notes =
        ref.watch(watchNotesProvider(const NoteFilter(archived: null))).value ??
        const <NoteView>[];
    final counts = <String, int>{};
    for (final v in notes) {
      for (final id in v.note.labelIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => popOr(context, '/notes')),
        title: const Text('Label'),
      ),
      body: switch (labels) {
        AsyncData(:final value) =>
          value.isEmpty
              ? EmptyState(
                  title: 'Belum ada label',
                  message:
                      'Label bikin catatan gampang dicari. Mis. Belanja, '
                      'Kerjaan, Ide Konten.',
                  mood: MascotMood.waving,
                  actionLabel: 'Buat label',
                  onAction: () => showLabelEditSheet(context),
                )
              : _List(labels: value, counts: counts),
        AsyncError() => ErrorRetry(
          onRetry: () => ref.invalidate(watchNoteLabelsProvider),
        ),
        _ => const LoadingListView(hero: false),
      },
      bottomNavigationBar: labels.value?.isEmpty ?? true
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: ChunkyButton(
                  key: const ValueKey('label-add'),
                  label: 'Label baru',
                  icon: Icons.add_rounded,
                  onPressed: () => showLabelEditSheet(context),
                ),
              ),
            ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.labels, required this.counts});
  final List<NoteLabel> labels;
  final Map<String, int> counts;

  Future<void> _delete(BuildContext context, WidgetRef ref, NoteLabel l) async {
    final n = counts[l.id] ?? 0;
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus label "${l.name}"?',
      message: n == 0
          ? 'Belum ada catatan yang memakai label ini.'
          : 'Label ini dilepas dari $n catatan. Catatannya sendiri tetap aman.',
      confirmLabel: 'Hapus label',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final r = await ref.read(deleteNoteLabelProvider)(l.id);
    if (!context.mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Label dihapus');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      buildDefaultDragHandles: false,
      itemCount: labels.length,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(
          'Nyalakan "Tab" supaya label muncul sebagai tab di Catatan. '
          'Tahan lalu geser pegangan untuk mengurutkan.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      ),
      proxyDecorator: (child, _, _) =>
          Material(color: Colors.transparent, child: child),
      onReorderItem: (from, to) {
        final ids = [for (final l in labels) l.id];
        final x = ids.removeAt(from);
        ids.insert(to, x);
        ref.read(reorderNoteLabelsProvider)(ids);
      },
      itemBuilder: (context, i) {
        final l = labels[i];
        final s = labelSwatch(l);
        final n = counts[l.id] ?? 0;
        return Padding(
          key: ValueKey('label-row-${l.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: ChunkyCard(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            onTap: () => showLabelEditSheet(context, label: l),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle_rounded, color: g.textMuted),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: s.tint(g.brightness),
                    borderRadius: GhinaRadii.rMd,
                  ),
                  child: Icon(Icons.label_rounded, color: s.base, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.h3
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                      Text(
                        n == 0 ? 'Belum dipakai' : '$n catatan',
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      key: ValueKey('label-tab-${l.id}'),
                      value: l.pinnedTab,
                      onChanged: (v) =>
                          ref.read(setNoteLabelPinnedTabProvider)(l.id, v),
                    ),
                    Text(
                      'Tab',
                      style: GhinaType.caption
                          .w(800)
                          .copyWith(color: g.textMuted),
                    ),
                  ],
                ),
                IconButton(
                  key: ValueKey('label-delete-${l.id}'),
                  tooltip: 'Hapus label',
                  icon: Icon(Icons.delete_outline_rounded, color: g.textMuted),
                  onPressed: () => _delete(context, ref, l),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Create (no [label]) or edit a label: name, color, "tampilkan sebagai tab".
Future<void> showLabelEditSheet(BuildContext context, {NoteLabel? label}) =>
    showChunkyBottomSheet<void>(
      context,
      title: label == null ? 'Label baru' : 'Ubah label',
      showClose: true,
      builder: (_) => _LabelForm(label: label),
    );

class _LabelForm extends ConsumerStatefulWidget {
  const _LabelForm({this.label});
  final NoteLabel? label;

  @override
  ConsumerState<_LabelForm> createState() => _LabelFormState();
}

class _LabelFormState extends ConsumerState<_LabelForm> {
  late final _name = TextEditingController(text: widget.label?.name ?? '');
  late String? _color = widget.label?.color;
  late bool _tab = widget.label?.pinnedTab ?? false;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama label wajib diisi');
      return;
    }
    setState(() => _saving = true);
    final input = NoteLabelInput(
      name: name,
      color: _color ?? labelColorFor(name),
      pinnedTab: _tab,
    );
    final l = widget.label;
    final r = l == null
        ? await ref.read(createNoteLabelProvider)(input)
        : await ref.read(updateNoteLabelProvider)(l.id, input);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok():
        Navigator.of(context).pop();
      case Err(:final failure):
        setState(
          () => _error = failure is ValidationFailure
              ? failure.message
              : 'Belum bisa disimpan. Coba lagi, ya',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final color = _color ?? labelColorFor(_name.text.trim());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('label-form-name'),
          label: 'Nama',
          hint: 'Mis. Belanja',
          controller: _name,
          autofocus: widget.label == null,
          errorText: _error,
          inputFormatters: [LengthLimitingTextInputFormatter(labelNameMax)],
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Warna'),
        ChunkyColorPicker(
          selected: color,
          onChanged: (c) => setState(() => _color = c),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          key: const ValueKey('label-form-tab'),
          contentPadding: EdgeInsets.zero,
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
          title: Text(
            'Tampilkan sebagai tab',
            style: GhinaType.h3.w(800).copyWith(color: g.textPrimary),
          ),
          subtitle: Text(
            'Muncul di deretan tab halaman Catatan',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ),
        const SizedBox(height: 12),
        ChunkyButton(
          key: const ValueKey('label-form-save'),
          label: 'Simpan',
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
