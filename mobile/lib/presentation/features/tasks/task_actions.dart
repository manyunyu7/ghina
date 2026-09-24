/// Task flows shared by the Tugas tab and the task page: complete (with the
/// money-link expense question + XP toast), delete with undo, move menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'widgets/task_visuals.dart';

export '../../shared/tasks/complete_task_flow.dart';

/// Hides the task at once and deletes it when the "BATAL" snackbar closes
/// without undo. [setHidden] toggles the local hide.
void deleteTaskWithUndo(
  BuildContext context,
  WidgetRef ref,
  Task task, {
  required void Function(String id, bool hidden) setHidden,
}) {
  final delete = ref.read(deleteTaskProvider);
  setHidden(task.id, true);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final c = messenger.showSnackBar(
    SnackBar(
      content: Text('"${task.title}" dihapus'),
      duration: const Duration(seconds: 4),
      persist: false,
      action: SnackBarAction(label: 'BATAL', onPressed: () {}),
    ),
  );
  c.closed.then((reason) async {
    if (reason == SnackBarClosedReason.action) {
      setHidden(task.id, false);
      return;
    }
    final r = await delete(task.id);
    if (r is Err) setHidden(task.id, false);
  });
}

/// Actions of the long-press menu.
sealed class TaskMenuAction {
  const TaskMenuAction();
}

final class MoveToBucket extends TaskMenuAction {
  const MoveToBucket(this.bucket);
  final TaskBucket bucket;
}

final class MoveToArea extends TaskMenuAction {
  const MoveToArea(this.areaId);
  final String areaId;
}

final class ShiftTask extends TaskMenuAction {
  const ShiftTask(this.up);
  final bool up;
}

final class EditTask extends TaskMenuAction {
  const EditTask();
}

final class CompleteTaskAction extends TaskMenuAction {
  const CompleteTaskAction();
}

final class DeleteTaskAction extends TaskMenuAction {
  const DeleteTaskAction();
}

/// Long-press menu: move bucket / area, shift up/down, edit, complete, delete.
Future<TaskMenuAction?> showTaskMenu(
  BuildContext context, {
  required TaskView view,
  required List<TaskArea> areas,
  bool canShiftUp = false,
  bool canShiftDown = false,
}) => showChunkyBottomSheet<TaskMenuAction>(
  context,
  title: view.title,
  showClose: true,
  builder: (c) {
    void pop(TaskMenuAction a) => Navigator.of(c).pop(a);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Pindah ke'),
        Row(
          children: [
            for (final b in TaskBucket.values) ...[
              if (b.index > 0) const SizedBox(width: 8),
              Expanded(
                child: ChunkyButton(
                  key: ValueKey('move-${b.wire}'),
                  label: b.display,
                  size: ChunkyButtonSize.small,
                  uppercase: false,
                  variant: b == view.bucket
                      ? ChunkyButtonVariant.primary
                      : ChunkyButtonVariant.outline,
                  color: bucketSwatch(b),
                  onPressed: b == view.bucket
                      ? null
                      : () => pop(MoveToBucket(b)),
                ),
              ),
            ],
          ],
        ),
        if (areas.length > 1) ...[
          const SizedBox(height: 16),
          const FieldLabel('Pindah area'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in areas)
                ChunkyChip(
                  label: a.name,
                  icon: GhinaIcons.of(a.icon),
                  color: areaSwatch(a),
                  selected: a.id == view.task.areaId,
                  onTap: a.id == view.task.areaId
                      ? null
                      : () => pop(MoveToArea(a.id)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (canShiftUp || canShiftDown)
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  label: 'Naikkan',
                  icon: Icons.arrow_upward_rounded,
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.outline,
                  color: GhinaColors.blue,
                  onPressed: canShiftUp
                      ? () => pop(const ShiftTask(true))
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyButton(
                  label: 'Turunkan',
                  icon: Icons.arrow_downward_rounded,
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.outline,
                  color: GhinaColors.blue,
                  onPressed: canShiftDown
                      ? () => pop(const ShiftTask(false))
                      : null,
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        ChunkyTile(
          framed: false,
          dense: true,
          leading: Icon(Icons.edit_rounded, color: GhinaColors.blue.base),
          title: 'Ubah detail',
          onTap: () => pop(const EditTask()),
        ),
        if (!view.done)
          ChunkyTile(
            framed: false,
            dense: true,
            leading: Icon(
              Icons.check_circle_rounded,
              color: GhinaColors.green.base,
            ),
            title: 'Tandai selesai',
            onTap: () => pop(const CompleteTaskAction()),
          ),
        ChunkyTile(
          framed: false,
          dense: true,
          leading: Icon(
            Icons.delete_outline_rounded,
            color: GhinaColors.red.base,
          ),
          titleWidget: Text(
            'Hapus',
            style: GhinaType.h3.copyWith(color: GhinaColors.red.base),
          ),
          title: 'Hapus',
          onTap: () => pop(const DeleteTaskAction()),
        ),
      ],
    );
  },
);

/// Applies a move from the menu with a friendly toast.
Future<void> moveTaskFlow(
  BuildContext context,
  WidgetRef ref,
  TaskView view, {
  TaskBucket? bucket,
  String? areaId,
  double? sortOrder,
  String? toast,
}) async {
  final r = await ref.read(moveTaskProvider)(
    view.id,
    bucket: bucket,
    areaId: areaId,
    sortOrder: sortOrder,
  );
  if (!context.mounted) return;
  switch (r) {
    case Ok():
      if (toast != null) {
        showToastBadge(
          context,
          message: toast,
          icon: Icons.swap_vert_rounded,
          color: bucket == null ? GhinaColors.blue : bucketSwatch(bucket),
        );
      }
    case Err(:final failure):
      showFailureToast(context, failure);
  }
}
