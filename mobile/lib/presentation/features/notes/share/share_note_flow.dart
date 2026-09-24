/// Android share target → note (docs/notes.md "Capture paths"): creates the
/// note (`source = share`) from a [SharedPayload] and opens the "Catatan dari
/// share" sheet (preview, labels, → Tugas / → Konten, open the editor).
/// Called by the signed-in shell (`features/shell/share_intake_listener.dart`).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/services/services.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../note_actions.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/note_card.dart';
import '../widgets/note_visuals.dart';

/// The body text for a share: the shared text plus every link that isn't in
/// it yet (one per line), so they all become note links.
String sharedBody(SharedPayload p) {
  final text = p.text?.trim() ?? '';
  final extra = [
    for (final u in p.urls)
      if (!text.contains(u)) u,
  ];
  return [if (text.isNotEmpty) text, ...extra].join('\n');
}

enum _ShareNext { done, open, task, content }

/// Creates the note from [payload] and runs the sheet. Returns the note id
/// (null when nothing could be saved).
Future<String?> handleSharedPayload(
  BuildContext context,
  WidgetRef ref,
  SharedPayload payload,
) async {
  if (payload.isEmpty) return null;
  final r = await ref.read(createNoteFromShareProvider)(
    SharedNoteInput(
      text: sharedBody(payload),
      subject: payload.title,
      imagePaths: payload.imagePaths,
    ),
  );
  // The note keeps its own copies; the intake files are no longer needed.
  _deleteQuietly(payload.imagePaths);
  if (!context.mounted) return null;
  final Note note;
  switch (r) {
    case Ok(:final value):
      note = value;
    case Err(:final failure):
      showFailureToast(context, failure);
      return null;
  }

  final next = await showChunkyBottomSheet<_ShareNext>(
    context,
    title: 'Catatan dari share',
    showClose: true,
    builder: (_) => _ShareSheet(noteId: note.id, fallback: note),
  );
  if (!context.mounted) return note.id;
  final live = await _latest(ref, note);
  if (!context.mounted) return note.id;
  switch (next) {
    case _ShareNext.open:
      context.push(noteRoute(note.id));
    case _ShareNext.task:
      await convertToTaskFlow(context, ref, live);
    case _ShareNext.content:
      await convertToContentFlow(context, ref, live);
    case _ShareNext.done:
    case null:
      showOkToast(
        context,
        'Tersimpan di Catatan 📥',
        icon: Icons.notes_rounded,
      );
  }
  return note.id;
}

Future<Note> _latest(WidgetRef ref, Note fallback) async {
  final v = ref.read(watchNoteProvider(fallback.id)).value;
  return v?.note ?? fallback;
}

void _deleteQuietly(List<String> paths) {
  for (final p in paths) {
    // Only the intake's own copies (`<app documents>/shared_images/`).
    if (!p.contains('shared_images')) continue;
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

class _ShareSheet extends ConsumerWidget {
  const _ShareSheet({required this.noteId, required this.fallback});

  final String noteId;
  final Note fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final view =
        ref.watch(watchNoteProvider(noteId)).value ??
        NoteView(note: fallback, labels: const []);
    final note = view.note;
    final labels =
        ref.watch(watchNoteLabelsProvider).value ?? const <NoteLabel>[];

    return Column(
      key: const ValueKey('share-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const MascotView(mood: MascotMood.happy, size: 52, animate: false),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sudah tersimpan! Mau dikasih label atau langsung dijadikan '
                'sesuatu?',
                style: GhinaType.body.w(700).copyWith(color: g.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        NoteCard(
          view: view,
          compact: true,
          onTap: () => Navigator.of(context).pop(_ShareNext.open),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Label'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in labels)
              ChunkyChip(
                key: ValueKey('share-label-${l.id}'),
                label: l.name,
                color: labelSwatch(l),
                selected: note.hasLabel(l.id),
                onTap: () => ref.read(toggleNoteLabelProvider)(noteId, l.id),
              ),
            ChunkyChip(
              key: const ValueKey('share-label-new'),
              label: 'Label',
              icon: Icons.add_rounded,
              selected: false,
              color: GhinaColors.gray,
              onTap: () => showLabelPickerSheet(
                context,
                selected: note.labelIds,
                onChanged: (ids) =>
                    ref.read(setNoteLabelsProvider)(noteId, ids),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('share-task'),
                label: 'Tugas',
                variant: ChunkyButtonVariant.outline,
                color: GhinaColors.red,
                size: ChunkyButtonSize.medium,
                onPressed: note.linkedTaskId != null
                    ? null
                    : () => Navigator.of(context).pop(_ShareNext.task),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('share-content'),
                label: 'Konten',
                variant: ChunkyButtonVariant.outline,
                color: GhinaColors.purple,
                size: ChunkyButtonSize.medium,
                onPressed: note.linkedContentId != null
                    ? null
                    : () => Navigator.of(context).pop(_ShareNext.content),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('share-open'),
                label: 'Buka',
                icon: Icons.edit_rounded,
                variant: ChunkyButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(_ShareNext.open),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('share-done'),
                label: 'Selesai',
                onPressed: () => Navigator.of(context).pop(_ShareNext.done),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
