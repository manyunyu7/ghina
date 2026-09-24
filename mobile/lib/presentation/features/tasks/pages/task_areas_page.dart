import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../task_format.dart';

/// `/tasks/areas`: reorder (drag), archive, delete, open the form.
class TaskAreasPage extends ConsumerStatefulWidget {
  const TaskAreasPage({super.key});

  @override
  ConsumerState<TaskAreasPage> createState() => _TaskAreasPageState();
}

class _TaskAreasPageState extends ConsumerState<TaskAreasPage> {
  List<TaskArea>? _optimistic;

  Future<void> _reorder(List<TaskArea> areas, int from, int to) async {
    if (from == to) return;
    final list = [...areas];
    list.insert(to, list.removeAt(from));
    setState(() => _optimistic = list);
    final r = await ref.read(reorderTaskAreasProvider)([
      for (final a in list) a.id,
    ]);
    if (!mounted) return;
    if (r case Err(:final failure)) showFailureToast(context, failure);
  }

  Future<void> _archive(TaskArea a) async {
    final r = await ref.read(setTaskAreaArchivedProvider)(a.id, !a.archived);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: a.archived ? '${a.name} aktif lagi' : '${a.name} diarsipkan',
          icon: a.archived ? Icons.unarchive_rounded : Icons.archive_rounded,
          color: GhinaColors.blue,
        );
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _delete(TaskArea a) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus area ${a.name}?',
      message:
          'Semua tugas di area ini ikut terhapus, termasuk yang sudah selesai. '
          'Kalau cuma mau disembunyikan, arsipkan saja.',
      confirmLabel: 'Hapus area',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteTaskAreaProvider)(a.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Area ${a.name} dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(watchAllTaskAreasProvider);
    ref.listen(watchAllTaskAreasProvider, (_, _) => _optimistic = null);
    return Scaffold(
      appBar: AppBar(title: const Text('Area tugas')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ChunkyButton(
          key: const ValueKey('area-new'),
          label: 'Area baru',
          icon: Icons.add_rounded,
          onPressed: () => context.push('/tasks/areas/new'),
        ),
      ),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingListView(hero: false),
        error: (_, _) => ErrorRetry(
          onRetry: () => ref.invalidate(watchAllTaskAreasProvider),
        ),
        data: (data) {
          final areas = _optimistic ?? data;
          if (areas.isEmpty) {
            return EmptyState(
              title: 'Belum ada area',
              message:
                  'Bikin area buat misahin tugas, misalnya Kerjaan & Kuliah.',
              actionLabel: 'Area baru',
              onAction: () => context.push('/tasks/areas/new'),
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            buildDefaultDragHandles: false,
            header: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Tahan & geser pegangan di kiri untuk atur urutan chip di tab Tugas.',
                style: GhinaType.bodyS.copyWith(
                  color: context.ghina.textSecondary,
                ),
              ),
            ),
            itemCount: areas.length,
            onReorderItem: (from, to) => _reorder(areas, from, to),
            proxyDecorator: (child, _, _) =>
                Material(type: MaterialType.transparency, child: child),
            itemBuilder: (_, i) {
              final a = areas[i];
              return Padding(
                key: ValueKey('area-row-${a.id}'),
                padding: const EdgeInsets.only(bottom: 10),
                child: _AreaRow(
                  area: a,
                  index: i,
                  onTap: () => context.push('/tasks/areas/${a.id}'),
                  onArchive: () => _archive(a),
                  onDelete: () => _delete(a),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.area,
    required this.index,
    required this.onTap,
    required this.onArchive,
    required this.onDelete,
  });

  final TaskArea area;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = CategoryColors.swatch(area.color);
    return Opacity(
      opacity: area.archived ? 0.6 : 1,
      child: ChunkyCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
        borderRadius: GhinaRadii.rLg,
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: g.textMuted,
                  semanticLabel: 'Geser untuk urutkan',
                ),
              ),
            ),
            CategoryAvatar(iconName: area.icon, colorHex: area.color, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          area.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.h3.copyWith(color: g.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ChunkyPill(label: area.code, color: sw, soft: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    area.archived
                        ? 'Diarsipkan'
                        : scheduleSummary(area.schedule),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('area-menu-${area.id}'),
              tooltip: 'Menu area',
              icon: Icon(Icons.more_vert_rounded, color: g.textSecondary),
              onSelected: (v) => switch (v) {
                'edit' => onTap(),
                'archive' => onArchive(),
                _ => onDelete(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Ubah')),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(area.archived ? 'Aktifkan lagi' : 'Arsipkan'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Hapus',
                    style: TextStyle(color: GhinaColors.red.base),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
