import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/tasks/complete_task_flow.dart';
import '../../../shared/widgets/widgets.dart';

/// Max FIRE tasks listed on the home card.
const homeFireLimit = 5;

/// Max SHOULD tasks listed on the Sunday "Sapu bersih" card.
const homeSapuBersihLimit = 5;

/// Beranda's task block (`docs/tasks.md` → Home): the "Tugas FIRE" card for the
/// focus areas (one-tap complete, "Lihat semua" → `/tasks`) and, on Sunday
/// mornings, "Sapu bersih SHOULD 🧹".
class HomeTasksSection extends ConsumerWidget {
  const HomeTasksSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(watchTaskHomeProvider);
    final home = async.value;
    if (home == null) {
      if (async.hasError) {
        return ChunkyCard(
          child: ErrorRetry(
            compact: true,
            onRetry: () => ref.invalidate(watchTaskHomeProvider),
          ),
        );
      }
      return const Skeleton(height: 150, radius: 20);
    }
    // Shared with the Tugas tab: "Catat pengeluaran?" (+ wallet pick), XP
    // toast with the daily goal progress, celebrations.
    Future<bool> complete(TaskView v) =>
        completeTaskFlow(context, ref, v.task, goalHint: true);
    final meta = HomeTaskMeta(
      now: ref.watch(clockProvider).now(),
      currency: ref.watch(currencyProvider),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Tugas FIRE',
          subtitle: _focusLabel(home.focus),
          actionLabel: 'Lihat semua',
          onAction: () => context.go('/tasks'),
        ),
        FireTasksCard(home: home, meta: meta, onComplete: complete),
        if (home.showSapuBersih && home.sapuBersih.isNotEmpty) ...[
          GhinaSpace.gapLg,
          SapuBersihCard(
            tasks: home.sapuBersih,
            meta: meta,
            onComplete: complete,
          ),
        ],
      ],
    );
  }

  static String? _focusLabel(FocusAreas f) {
    if (f.areas.isEmpty) return null;
    final names = f.areas.map((a) => a.name).join(', ');
    return f.bySchedule ? 'Fokus sekarang: $names' : 'Area fokus: $names';
  }
}

/// Up to [homeFireLimit] undone FIRE tasks of the focus areas, or the
/// "FIRE kosong" empty state.
class FireTasksCard extends StatelessWidget {
  const FireTasksCard({
    super.key,
    required this.home,
    required this.meta,
    required this.onComplete,
  });

  final TaskHome home;
  final HomeTaskMeta meta;
  final Future<bool> Function(TaskView) onComplete;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final tasks = home.fireTasks;
    if (tasks.isEmpty) {
      return ChunkyCard(
        key: const ValueKey('home-fire-empty'),
        tinted: GhinaColors.green,
        child: Row(
          children: [
            const MascotView(mood: MascotMood.excited, size: 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FIRE kosong 🔥 mantap!', style: GhinaType.h3.w(900)),
                  const SizedBox(height: 2),
                  Text(
                    home.openCount == 0
                        ? 'Belum ada tugas. Tulis yang penting biar nggak lupa.'
                        : 'Yang mendesak udah beres. Cicil yang lain pelan-pelan.',
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  ChunkyButton(
                    label: home.openCount == 0 ? 'Tambah tugas' : 'Lihat tugas',
                    size: ChunkyButtonSize.small,
                    variant: ChunkyButtonVariant.outline,
                    icon: home.openCount == 0
                        ? Icons.add_rounded
                        : Icons.checklist_rounded,
                    onPressed: () => context.go('/tasks'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final more = tasks.length - homeFireLimit;
    return ChunkyCard(
      key: const ValueKey('home-fire-card'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final v in tasks.take(homeFireLimit))
            HomeTaskRow(
              key: ValueKey('home-task-${v.id}'),
              view: v,
              meta: meta,
              onComplete: () => onComplete(v),
            ),
          if (more > 0 || home.overdueCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                children: [
                  if (more > 0)
                    Expanded(
                      child: Text(
                        '+$more tugas FIRE lainnya',
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textSecondary),
                      ),
                    )
                  else
                    const Spacer(),
                  if (home.overdueCount > 0)
                    ChunkyPill(
                      label: '${home.overdueCount} terlambat',
                      color: GhinaColors.red,
                      soft: true,
                      uppercase: false,
                      icon: Icons.schedule_rounded,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sunday before noon: undone SHOULD tasks of the unscheduled areas.
class SapuBersihCard extends StatelessWidget {
  const SapuBersihCard({
    super.key,
    required this.tasks,
    required this.meta,
    required this.onComplete,
  });

  final List<TaskView> tasks;
  final HomeTaskMeta meta;
  final Future<bool> Function(TaskView) onComplete;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final more = tasks.length - homeSapuBersihLimit;
    return ChunkyCard(
      key: const ValueKey('home-sapu-bersih'),
      tinted: GhinaColors.blue,
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sapu bersih SHOULD 🧹', style: GhinaType.h3.w(900)),
                Text(
                  'Minggu pagi, waktunya beresin tugas kecil yang numpuk.',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final v in tasks.take(homeSapuBersihLimit))
            HomeTaskRow(
              key: ValueKey('home-task-${v.id}'),
              view: v,
              meta: meta,
              onComplete: () => onComplete(v),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '+$more lainnya',
                style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Now" and the user's currency for the task rows.
class HomeTaskMeta {
  const HomeTaskMeta({required this.now, required this.currency});
  final DateTime now;
  final String currency;
}

/// One task with a one-tap complete checkbox; tapping the row opens the task.
class HomeTaskRow extends StatefulWidget {
  const HomeTaskRow({
    super.key,
    required this.view,
    required this.meta,
    required this.onComplete,
  });

  final TaskView view;
  final HomeTaskMeta meta;

  /// Runs the completion flow; false = cancelled or failed (unticks the box).
  final Future<bool> Function() onComplete;

  @override
  State<HomeTaskRow> createState() => _HomeTaskRowState();
}

class _HomeTaskRowState extends State<HomeTaskRow> {
  bool _checked = false;

  Future<void> _tick() async {
    if (_checked) return;
    setState(() => _checked = true);
    final ok = await widget.onComplete();
    if (!ok && mounted) setState(() => _checked = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final v = widget.view;
    final t = v.task;
    final bucket = ChunkySwatch.fromColor(Color(t.bucket.color));
    final now = widget.meta.now;
    final due = t.dueDay;
    final dueText = due == null
        ? null
        : [
            Fmt.relativeDay(due, now: now),
            if (t.dueTime != null) t.dueTime!.replaceAll(':', '.'),
          ].join(' ');
    return InkWell(
      onTap: () => context.push(taskRoute(t.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _CheckCircle(
              key: ValueKey('home-task-check-${t.id}'),
              checked: _checked,
              color: bucket,
              label: 'Selesaikan ${t.title}',
              onTap: _tick,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: GhinaMotion.fast,
                    style: GhinaType.body
                        .w(800)
                        .copyWith(
                          color: _checked ? g.textMuted : g.textPrimary,
                          decoration: _checked
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                    child: Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        v.area?.name ?? v.tag,
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                      if (v.isOverdue)
                        Text(
                          overdueLabel,
                          style: GhinaType.caption
                              .w(900)
                              .copyWith(color: const Color(overdueColor)),
                        )
                      else if (dueText != null)
                        Text(
                          '· $dueText',
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                      if (t.hasMoneyLink)
                        Text(
                          '· ${Fmt.money(t.amount!, currency: widget.meta.currency)}',
                          style: GhinaType.caption
                              .w(800)
                              .copyWith(color: GhinaColors.expense.base),
                        ),
                      if (t.isRecurring)
                        Icon(
                          Icons.repeat_rounded,
                          size: 14,
                          color: g.textMuted,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ChunkyPill(
              label: '+${t.bucket.xp} XP',
              color: GhinaColors.yellow,
              soft: true,
              uppercase: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({
    super.key,
    required this.checked,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final bool checked;
  final ChunkySwatch color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final green = GhinaColors.green;
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
              curve: GhinaMotion.pop,
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: checked ? green.base : g.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: checked ? green.edge : color.base,
                  width: 3,
                ),
              ),
              child: AnimatedScale(
                duration: GhinaMotion.fast,
                curve: GhinaMotion.pop,
                scale: checked ? 1 : 0,
                child: Icon(Icons.check_rounded, size: 20, color: green.on),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
