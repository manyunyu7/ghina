import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../../shell/sync_indicator.dart';
import '../task_actions.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/reminder_settings.dart';
import '../widgets/task_tile.dart';
import '../widgets/task_visuals.dart';

/// Which areas the tab shows.
sealed class _Scope {
  const _Scope();
}

class _Focus extends _Scope {
  const _Focus();
}

class _All extends _Scope {
  const _All();
}

class _Area extends _Scope {
  const _Area(this.id);
  final String id;
}

const _statuses = [
  (TaskStatusFilter.open, 'Aktif', Icons.radio_button_unchecked_rounded),
  (TaskStatusFilter.today, 'Hari ini', Icons.today_rounded),
  (TaskStatusFilter.mepet, 'Mepet', Icons.local_fire_department_rounded),
  (TaskStatusFilter.overdue, 'Terlambat', Icons.alarm_rounded),
  (TaskStatusFilter.done, 'Selesai', Icons.check_circle_rounded),
];

/// The Tugas tab: area chips, status filters, FIRE / WANT / SHOULD sections.
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  _Scope _scope = const _Focus();
  TaskStatusFilter _status = TaskStatusFilter.open;
  final _hidden = <String>{};

  TaskFilter get _filter => switch (_scope) {
    _Focus() => TaskFilter(focusAreasOnly: true, status: _status),
    _All() => TaskFilter(status: _status),
    _Area(:final id) => TaskFilter(areaIds: [id], status: _status),
  };

  String? get _selectedAreaId => switch (_scope) {
    _Area(:final id) => id,
    _ => null,
  };

  void _setHidden(String id, bool hidden) {
    if (!mounted) return;
    setState(() => hidden ? _hidden.add(id) : _hidden.remove(id));
  }

  void _quickAdd([TaskBucket bucket = TaskBucket.want]) =>
      showQuickAddTask(context, bucket: bucket, areaId: _selectedAreaId);

  Future<bool> _toggle(TaskView v) => v.done
      ? uncompleteTaskFlow(context, ref, v.task)
      : completeTaskFlow(context, ref, v.task);

  void _delete(TaskView v) =>
      deleteTaskWithUndo(context, ref, v.task, setHidden: _setHidden);

  Future<void> _menu(TaskView v, List<TaskView> section, int index) async {
    final areas = ref.read(watchTaskAreasProvider).value ?? const <TaskArea>[];
    final reorderable = _status == TaskStatusFilter.open && !v.done;
    final a = await showTaskMenu(
      context,
      view: v,
      areas: areas,
      canShiftUp: reorderable && index > 0,
      canShiftDown: reorderable && index < section.length - 1,
    );
    if (a == null || !mounted) return;
    switch (a) {
      case MoveToBucket(:final bucket):
        await moveTaskFlow(
          context,
          ref,
          v,
          bucket: bucket,
          toast: 'Pindah ke ${bucket.display}',
        );
      case MoveToArea(:final areaId):
        final name = areas.where((x) => x.id == areaId).firstOrNull?.name;
        await moveTaskFlow(
          context,
          ref,
          v,
          areaId: areaId,
          toast: 'Pindah ke ${name ?? 'area lain'}',
        );
      case ShiftTask(:final up):
        final j = up ? index - 1 : index + 1;
        final list = [...section]..removeAt(index);
        list.insert(j, v);
        await _placeAt(list, j);
      case EditTask():
        context.push('/tasks/${v.id}');
      case CompleteTaskAction():
        await completeTaskFlow(context, ref, v.task);
      case DeleteTaskAction():
        _delete(v);
    }
  }

  /// [list] is a section in its new order; saves the sortOrder of item [i].
  Future<void> _placeAt(List<TaskView> list, int i) async {
    final prev = i > 0 ? list[i - 1].task.sortOrder : null;
    final next = i < list.length - 1 ? list[i + 1].task.sortOrder : null;
    final r = await ref.read(moveTaskProvider)(
      list[i].id,
      sortOrder: sortOrderBetween(prev, next),
    );
    if (r case Err(:final failure) when mounted) {
      showFailureToast(context, failure);
    }
  }

  Future<void> _seedAreas() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final r = await ref.read(seedDefaultTaskAreasProvider)(user.id);
    if (r case Err(:final failure) when mounted) {
      showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(watchTaskAreasProvider);
    final areas = areasAsync.value ?? const <TaskArea>[];
    final focus = ref.watch(watchFocusAreasProvider).value;
    if (_scope case _Area(:final id) when areasAsync.hasValue) {
      if (!areas.any((a) => a.id == id)) _scope = const _Focus();
    }

    return Scaffold(
      floatingActionButton: areas.isEmpty
          ? null
          : _AddButton(onPressed: () => _quickAdd()),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              focus: focus,
              scope: _scope,
              onAreas: () => context.push('/tasks/areas'),
              onReminders: () => showReminderSettingsSheet(context),
            ),
            _AreaChips(
              areas: areas,
              scope: _scope,
              onChanged: (s) => setState(() => _scope = s),
            ),
            const SizedBox(height: 8),
            _ChipBar(
              children: [
                for (final (s, label, icon) in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: ChunkyChip(
                        key: ValueKey('status-${s.name}'),
                        label: label,
                        icon: icon,
                        selected: _status == s,
                        color: switch (s) {
                          TaskStatusFilter.mepet ||
                          TaskStatusFilter.overdue => GhinaColors.red,
                          TaskStatusFilter.done => GhinaColors.green,
                          TaskStatusFilter.today => GhinaColors.orange,
                          _ => GhinaColors.blue,
                        },
                        onTap: () => setState(() => _status = s),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => pullToSync(context, ref),
                child: areasAsync.when(
                  skipLoadingOnReload: true,
                  loading: () => const LoadingListView(hero: false),
                  error: (_, _) => ScrollableFill(
                    child: ErrorRetry(
                      onRetry: () => ref.invalidate(watchTaskAreasProvider),
                    ),
                  ),
                  data: (areas) => areas.isEmpty
                      ? ScrollableFill(
                          child: EmptyState(
                            title: 'Belum ada area',
                            message:
                                'Area itu konteks tugasmu, misalnya Kerjaan dan Keseharian.',
                            actionLabel: 'Buat area default',
                            onAction: _seedAreas,
                          ),
                        )
                      : _status == TaskStatusFilter.done
                      ? _doneList()
                      : _board(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _showArea => _scope is! _Area;

  Widget _board() {
    final board = ref.watch(watchTaskBoardProvider(_filter));
    final now = ref.read(clockProvider).now();
    final currency = ref.watch(currencyProvider);
    return board.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingListView(hero: false),
      error: (_, _) => ScrollableFill(
        child: ErrorRetry(
          onRetry: () => ref.invalidate(watchTaskBoardProvider(_filter)),
        ),
      ),
      data: (b) {
        final multiArea = _showArea && b.areas.length > 1;
        if (b.isEmpty) {
          return ScrollableFill(child: _emptyBoard());
        }
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            for (final s in b.sections)
              ..._section(
                s,
                visible: [
                  for (final v in s.tasks)
                    if (!_hidden.contains(v.id)) v,
                ],
                now: now,
                currency: currency,
                showArea: multiArea,
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }

  Widget _emptyBoard() {
    final (title, message) = switch (_status) {
      TaskStatusFilter.today => (
        'Hari ini kosong',
        'Nggak ada tugas yang jatuh tempo hari ini. Santai dulu ☕',
      ),
      TaskStatusFilter.mepet => (
        'Nggak ada yang mepet',
        'Semua WANT masih aman waktunya 👍',
      ),
      TaskStatusFilter.overdue => (
        'Nggak ada yang telat',
        'Keren, semua tugas masih on track! 🎉',
      ),
      _ => (
        'Belum ada tugas',
        'Tambah tugas pertamamu, yuk. Cukup judul, sisanya nanti.',
      ),
    };
    return EmptyState(
      mood: _status == TaskStatusFilter.open
          ? MascotMood.sleeping
          : MascotMood.happy,
      title: title,
      message: message,
      actionLabel: 'Tambah tugas',
      onAction: _quickAdd,
    );
  }

  List<Widget> _section(
    TaskSection s, {
    required List<TaskView> visible,
    required DateTime now,
    required String currency,
    required bool showArea,
  }) {
    final reorderable = _status == TaskStatusFilter.open;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          14,
          GhinaSpace.page,
          8,
        ),
        sliver: SliverToBoxAdapter(
          child: _SectionHeader(
            bucket: s.bucket,
            count: visible.length,
            onAdd: () => _quickAdd(s.bucket),
          ),
        ),
      ),
      if (visible.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
          sliver: SliverToBoxAdapter(
            child: _EmptySection(
              bucket: s.bucket,
              onAdd: () => _quickAdd(s.bucket),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
          sliver: _SectionList(
            key: ValueKey('section-${s.bucket.wire}'),
            items: visible,
            reorderable: reorderable,
            onReorder: _placeAt,
            itemBuilder: (context, v, i, items) => Padding(
              key: ValueKey('task-${v.id}'),
              padding: const EdgeInsets.only(bottom: 10),
              child: TaskTile(
                view: v,
                now: now,
                currency: currency,
                showArea: showArea,
                dragIndex: reorderable ? i : null,
                onToggle: () => _toggle(v),
                onDelete: () => _delete(v),
                onTap: () => context.push('/tasks/${v.id}'),
                onLongPress: () => _menu(v, items, i),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _doneList() {
    final list = ref.watch(watchTasksProvider(_filter));
    final now = ref.read(clockProvider).now();
    final currency = ref.watch(currencyProvider);
    return list.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingListView(hero: false),
      error: (_, _) => ScrollableFill(
        child: ErrorRetry(
          onRetry: () => ref.invalidate(watchTasksProvider(_filter)),
        ),
      ),
      data: (all) {
        final items = [
          for (final v in all)
            if (!_hidden.contains(v.id)) v,
        ];
        if (items.isEmpty) {
          return ScrollableFill(
            child: EmptyState(
              title: 'Belum ada yang selesai',
              message: 'Centang tugas pertamamu dan rasakan puasnya ✅',
              mood: MascotMood.thinking,
              actionLabel: 'Lihat tugas aktif',
              onAction: () => setState(() => _status = TaskStatusFilter.open),
            ),
          );
        }
        final multiArea =
            _showArea && items.map((v) => v.task.areaId).toSet().length > 1;
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            10,
            GhinaSpace.page,
            120,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final v = items[i];
            return Padding(
              key: ValueKey('done-${v.id}'),
              padding: const EdgeInsets.only(bottom: 10),
              child: TaskTile(
                view: v,
                now: now,
                currency: currency,
                showArea: multiArea,
                onToggle: () => _toggle(v),
                onDelete: () => _delete(v),
                onTap: () => context.push('/tasks/${v.id}'),
                onLongPress: () => _menu(v, items, i),
              ),
            );
          },
        );
      },
    );
  }
}

/// A bucket's tiles; drag handles reorder within the bucket (optimistic).
class _SectionList extends StatefulWidget {
  const _SectionList({
    super.key,
    required this.items,
    required this.reorderable,
    required this.onReorder,
    required this.itemBuilder,
  });

  final List<TaskView> items;
  final bool reorderable;
  final Future<void> Function(List<TaskView> list, int index) onReorder;
  final Widget Function(
    BuildContext context,
    TaskView v,
    int index,
    List<TaskView> items,
  )
  itemBuilder;

  @override
  State<_SectionList> createState() => _SectionListState();
}

class _SectionListState extends State<_SectionList> {
  late List<TaskView> _items = widget.items;

  @override
  void didUpdateWidget(_SectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) _items = widget.items;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.reorderable) {
      return SliverList.builder(
        itemCount: _items.length,
        itemBuilder: (c, i) => widget.itemBuilder(c, _items[i], i, _items),
      );
    }
    return SliverReorderableList(
      itemCount: _items.length,
      itemBuilder: (c, i) => widget.itemBuilder(c, _items[i], i, _items),
      proxyDecorator: (child, _, anim) => AnimatedBuilder(
        animation: anim,
        builder: (_, c) => Transform.scale(
          scale: 1 + 0.03 * Curves.easeOut.transform(anim.value),
          child: Material(type: MaterialType.transparency, child: c),
        ),
        child: child,
      ),
      onReorderItem: (from, to) {
        if (from == to) return;
        final list = [..._items];
        final moved = list.removeAt(from);
        list.insert(to, moved);
        setState(() => _items = list);
        widget.onReorder(list, to);
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.focus,
    required this.scope,
    required this.onAreas,
    required this.onReminders,
  });

  final FocusAreas? focus;
  final _Scope scope;
  final VoidCallback onAreas;
  final VoidCallback onReminders;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final f = focus;
    final String? sub;
    if (scope is _Focus && f != null && f.areas.isNotEmpty) {
      final names = f.areas.map((a) => a.name).join(' & ');
      sub = f.bySchedule ? 'Fokus: $names · lagi jam aktif' : 'Fokus: $names';
    } else {
      sub = null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(GhinaSpace.page, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tugas',
                  style: GhinaType.h1.copyWith(color: g.textPrimary),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption
                        .w(700)
                        .copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
          const LiveSyncBadge(compact: true),
          PopupMenuButton<String>(
            key: const ValueKey('tasks-menu'),
            tooltip: 'Menu',
            icon: Icon(Icons.more_vert_rounded, color: g.textSecondary),
            onSelected: (v) => v == 'areas' ? onAreas() : onReminders(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'areas',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.category_rounded),
                  title: Text('Kelola area'),
                ),
              ),
              PopupMenuItem(
                value: 'reminders',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notifications_rounded),
                  title: Text('Pengingat'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AreaChips extends StatelessWidget {
  const _AreaChips({
    required this.areas,
    required this.scope,
    required this.onChanged,
  });

  final List<TaskArea> areas;
  final _Scope scope;
  final ValueChanged<_Scope> onChanged;

  @override
  Widget build(BuildContext context) {
    if (areas.isEmpty) return const SizedBox.shrink();
    Widget chip(
      Key key,
      String label,
      IconData icon,
      ChunkySwatch color,
      bool selected,
      _Scope s,
    ) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ChunkyChip(
          key: key,
          label: label,
          icon: icon,
          color: color,
          selected: selected,
          onTap: () => onChanged(s),
        ),
      ),
    );
    return _ChipBar(
      children: [
        chip(
          const ValueKey('area-focus'),
          'Fokus',
          Icons.center_focus_strong_rounded,
          GhinaColors.green,
          scope is _Focus,
          const _Focus(),
        ),
        for (final a in areas)
          chip(
            ValueKey('area-${a.id}'),
            a.name,
            GhinaIcons.of(a.icon),
            areaSwatch(a),
            scope is _Area && (scope as _Area).id == a.id,
            _Area(a.id),
          ),
        chip(
          const ValueKey('area-all'),
          'Semua',
          Icons.apps_rounded,
          GhinaColors.blue,
          scope is _All,
          const _All(),
        ),
      ],
    );
  }
}

/// Horizontally scrolling chip row (all chips built, so few items only).
class _ChipBar extends StatelessWidget {
  const _ChipBar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(GhinaSpace.page, 2, GhinaSpace.page, 4),
    child: Row(children: children),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.bucket,
    required this.count,
    required this.onAdd,
  });

  final TaskBucket bucket;
  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = bucketSwatch(bucket);
    return Row(
      children: [
        Text(bucket.emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 6),
        Text(
          bucket.label,
          style: GhinaType.h3
              .w(900)
              .copyWith(color: sw.base, letterSpacing: 0.8),
        ),
        const SizedBox(width: 8),
        Container(
          key: ValueKey('count-${bucket.wire}'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: sw.base,
            borderRadius: GhinaRadii.rPill,
          ),
          child: Text(
            '$count',
            style: GhinaType.caption.w(900).copyWith(color: sw.on),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            bucket.meaning,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ),
        IconButton(
          key: ValueKey('add-${bucket.wire}'),
          tooltip: 'Tambah ${bucket.label}',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.add_circle_rounded, color: sw.base),
          onPressed: onAdd,
        ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.bucket, required this.onAdd});

  final TaskBucket bucket;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final msg = switch (bucket) {
      TaskBucket.fire => 'Nggak ada yang kebakaran. Mantap! 🎉',
      TaskBucket.want => 'Belum ada target minggu ini.',
      TaskBucket.should => 'Rutinitas masih kosong.',
    };
    return InkWell(
      onTap: onAdd,
      borderRadius: GhinaRadii.rLg,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: GhinaRadii.rLg,
          border: Border.all(color: g.border, width: 2),
        ),
        child: Text(
          msg,
          style: GhinaType.bodyS.w(700).copyWith(color: g.textMuted),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ChunkyButton(
    key: const ValueKey('task-add'),
    label: 'Tugas',
    icon: Icons.add_rounded,
    size: ChunkyButtonSize.medium,
    expand: false,
    color: GhinaColors.green,
    onPressed: onPressed,
  );
}
