import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/category_presets.dart';

/// Categories by type (Pengeluaran / Pemasukan) as a colorful grid.
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  CategoryType _type = CategoryType.expense;
  bool _seeding = false;

  void _add() {
    ref.read(categoryTypePresetProvider.notifier).set(_type);
    context.push('/categories/new');
  }

  Future<void> _seed() async {
    setState(() => _seeding = true);
    final r = await ref.read(seedDefaultCategoriesProvider)();
    if (!mounted) return;
    setState(() => _seeding = false);
    switch (r) {
      case Ok(:final value):
        showOkToast(
          context,
          value > 0
              ? '$value kategori bawaan ditambahkan 🎉'
              : 'Kategori bawaan sudah lengkap',
        );
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(watchCategoriesProvider(_type));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori'),
        actions: [
          IconButton(
            key: const ValueKey('category-add'),
            tooltip: 'Tambah kategori',
            icon: const Icon(Icons.add_circle_rounded),
            color: GhinaColors.green.base,
            onPressed: _add,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.md,
              GhinaSpace.page,
              GhinaSpace.sm,
            ),
            child: ChunkySegmented<CategoryType>(
              value: _type,
              onChanged: (t) => setState(() => _type = t),
              segments: const [
                ChunkySegment(
                  value: CategoryType.expense,
                  label: 'Pengeluaran',
                  icon: Icons.north_east_rounded,
                  color: GhinaColors.expense,
                ),
                ChunkySegment(
                  value: CategoryType.income,
                  label: 'Pemasukan',
                  icon: Icons.south_west_rounded,
                  color: GhinaColors.income,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => pullToSync(context, ref),
              child: switch (async) {
                AsyncValue(:final value?) =>
                  value.isEmpty ? _empty() : _grid(value),
                AsyncValue(hasError: true) => ScrollableFill(
                  child: ErrorRetry(
                    onRetry: () =>
                        ref.invalidate(watchCategoriesProvider(_type)),
                  ),
                ),
                _ => ListView(
                  padding: const EdgeInsets.all(GhinaSpace.page),
                  children: const [SkeletonList(count: 5)],
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => ScrollableFill(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyState(
          title: 'Belum ada kategori ${_type.label.toLowerCase()}',
          message:
              'Kategori bikin laporanmu lebih rapi. Mulai dari set bawaan atau bikin sendiri.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              ChunkyButton(
                key: const ValueKey('category-seed'),
                label: 'Pakai kategori bawaan',
                icon: Icons.auto_awesome_rounded,
                loading: _seeding,
                onPressed: _seeding ? null : _seed,
              ),
              const SizedBox(height: GhinaSpace.sm),
              ChunkyButton(
                label: 'Bikin sendiri',
                variant: ChunkyButtonVariant.ghost,
                color: GhinaColors.blue,
                onPressed: _add,
              ),
            ],
          ),
        ),
        const SizedBox(height: GhinaSpace.xl),
      ],
    ),
  );

  Widget _grid(List<TxCategory> items) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 5 : (c.maxWidth >= 340 ? 3 : 2);
        final scale = MediaQuery.textScalerOf(context).scale(1);
        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.md,
            GhinaSpace.page,
            GhinaSpace.xxxl,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: GhinaSpace.md,
            crossAxisSpacing: GhinaSpace.md,
            mainAxisExtent: 122 + 40 * (scale - 1).clamp(0, 1),
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            if (i == items.length) {
              return _AddTile(onTap: _add);
            }
            final cat = items[i];
            return PopIn(
              delay: Duration(milliseconds: 30 * (i < 10 ? i : 10)),
              fromScale: 0.8,
              child: _CategoryTile(
                category: cat,
                onTap: () => context.push('/categories/${cat.id}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final TxCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final style = GhinaType.bodyS
        .w(800)
        .copyWith(color: g.textPrimary, height: 1.15);
    return ChunkyCard(
      key: ValueKey('category-${category.id}'),
      onTap: onTap,
      semanticLabel: category.name,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      borderRadius: GhinaRadii.rLg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CategoryAvatar(
            iconName: category.icon,
            colorHex: category.color,
            size: 48,
          ),
          const SizedBox(height: 8),
          if (category.name.trim().contains(' '))
            Text(
              category.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            )
          else
            // A single long word: shrink instead of breaking mid-word.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(category.name, maxLines: 1, style: style),
            ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkySurface(
      color: g.background,
      edgeColor: g.border,
      borderColor: g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      semanticLabel: 'Tambah kategori',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 34, color: g.textMuted),
            Text(
              'TAMBAH',
              style: GhinaType.caption.w(900).copyWith(color: g.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
