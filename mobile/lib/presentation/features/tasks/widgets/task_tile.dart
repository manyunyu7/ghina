import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../task_format.dart';
import 'task_visuals.dart';

/// One task row: check circle, title, due / badges, and swipe actions
/// (right = complete / reopen, left = delete).
///
/// [onToggle] completes (or reopens a done task) and resolves to whether it
/// happened; the tile plays its check animation first.
class TaskTile extends StatefulWidget {
  const TaskTile({
    super.key,
    required this.view,
    required this.now,
    required this.onToggle,
    required this.onDelete,
    this.onTap,
    this.onLongPress,
    this.showArea = false,
    this.currency = 'IDR',
    this.dragIndex,
  });

  final TaskView view;
  final DateTime now;
  final Future<bool> Function() onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Show the area dot + name (when several areas are listed).
  final bool showArea;
  final String currency;

  /// Index in a reorderable list → shows a drag handle.
  final int? dragIndex;

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool _checking = false;

  bool get _checked => widget.view.done || _checking;

  Future<bool> _toggle() async {
    if (_checking) return false;
    if (widget.view.done) return widget.onToggle();
    setState(() => _checking = true);
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 380));
    final ok = await widget.onToggle();
    if (!ok && mounted) setState(() => _checking = false);
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final v = widget.view;
    final t = v.task;
    final bucket = bucketSwatch(t.bucket);
    final accent = v.isOverdue
        ? GhinaColors.red
        : v.isMepet
        ? GhinaColors.red
        : null;
    final due = dueLabel(t, widget.now);

    final meta = <Widget>[
      if (widget.showArea && v.area != null)
        _Meta(
          leading: AreaDot(area: v.area),
          label: v.area!.name,
          color: g.textSecondary,
        ),
      if (due != null)
        _Meta(
          icon: t.dueTime != null
              ? Icons.schedule_rounded
              : Icons.event_rounded,
          label: due,
          color: v.isOverdue && !t.done
              ? GhinaColors.red.base
              : v.isDueToday
              ? (g.isDark ? GhinaColors.orange.base : GhinaColors.orange.edge)
              : g.textSecondary,
        ),
      if (t.isRecurring)
        Icon(
          Icons.repeat_rounded,
          size: 16,
          color: g.textSecondary,
          semanticLabel: 'Berulang',
        ),
      if (t.hasReminder && !t.done)
        Icon(
          Icons.notifications_active_rounded,
          size: 15,
          color: g.textSecondary,
          semanticLabel: 'Ada pengingat',
        ),
      if (t.hasMoneyLink)
        ChunkyPill(
          label: GhinaMoney.format(t.amount!, currency: widget.currency),
          color: t.transactionId != null
              ? GhinaColors.green
              : GhinaColors.yellow,
          soft: true,
          icon: t.transactionId != null
              ? Icons.check_rounded
              : Icons.payments_rounded,
          uppercase: false,
        ),
      if (v.isOverdue && !t.done)
        const ChunkyPill(label: overdueLabel, color: GhinaColors.red)
      else if (v.isMepet && !t.done)
        const ChunkyPill(
          label: mepetLabel,
          color: GhinaColors.red,
          soft: true,
          icon: Icons.local_fire_department_rounded,
        ),
    ];

    final card = ChunkySurface(
      color: g.surface,
      edgeColor: accent?.base.withValues(alpha: 0.55) ?? g.borderEdge,
      borderColor: accent?.base.withValues(alpha: 0.55) ?? g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      semanticLabel: t.title,
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      child: Row(
        children: [
          _CheckCircle(
            key: ValueKey('task-check-${t.id}'),
            checked: _checked,
            color: bucket,
            onTap: _toggle,
            label: t.done ? 'Buka lagi' : 'Tandai selesai',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedOpacity(
              duration: GhinaMotion.medium,
              opacity: _checked ? 0.55 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body
                        .w(800)
                        .copyWith(
                          color: g.textPrimary,
                          decoration: _checked
                              ? TextDecoration.lineThrough
                              : null,
                          decorationThickness: 2,
                        ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: meta,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.dragIndex != null)
            ReorderableDragStartListener(
              index: widget.dragIndex!,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: g.textMuted,
                  semanticLabel: 'Geser untuk urutkan',
                ),
              ),
            ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss-${t.id}'),
      background: _SwipeBg(
        color: t.done ? GhinaColors.blue : GhinaColors.green,
        icon: t.done ? Icons.undo_rounded : Icons.check_rounded,
        label: t.done ? 'Buka lagi' : 'Selesai',
        alignLeft: true,
      ),
      secondaryBackground: const _SwipeBg(
        color: GhinaColors.red,
        icon: Icons.delete_rounded,
        label: 'Hapus',
        alignLeft: false,
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await _toggle();
          return false;
        }
        return true;
      },
      onDismissed: (_) => widget.onDelete(),
      child: card,
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.label,
    required this.color,
    this.icon,
    this.leading,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: 4)],
      if (icon != null) ...[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 3),
      ],
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GhinaType.caption.w(800).copyWith(color: color),
        ),
      ),
    ],
  );
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({
    super.key,
    required this.checked,
    required this.color,
    required this.onTap,
    required this.label,
  });

  final bool checked;
  final ChunkySwatch color;
  final Future<bool> Function() onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      checked: checked,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: GhinaMotion.fast,
              curve: GhinaMotion.standard,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? GhinaColors.green.base : g.surface,
                border: Border.all(
                  color: checked ? GhinaColors.green.edge : color.base,
                  width: 3,
                ),
              ),
              child: checked
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.3, end: 1),
                      duration: GhinaMotion.slow,
                      curve: GhinaMotion.bounce,
                      builder: (_, s, child) =>
                          Transform.scale(scale: s, child: child),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignLeft,
  });

  final ChunkySwatch color;
  final IconData icon;
  final String label;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: color.on),
      const SizedBox(width: 6),
      Text(label, style: GhinaType.body.w(900).copyWith(color: color.on)),
    ];
    return Container(
      decoration: BoxDecoration(
        color: color.base,
        borderRadius: GhinaRadii.rLg,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignLeft ? children : children.reversed.toList(),
      ),
    );
  }
}
