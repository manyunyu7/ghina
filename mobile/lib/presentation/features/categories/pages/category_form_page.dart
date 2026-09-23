import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/category_presets.dart';

/// Create / edit a category: name, type, icon (server-valid set) and color.
class CategoryFormPage extends ConsumerStatefulWidget {
  const CategoryFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage> {
  bool get _isEdit => widget.id != null;

  final _name = TextEditingController();
  CategoryType _type = CategoryType.expense;
  String _icon = categoryIcons.first;
  String _color = colorPalette[4];

  bool _loaded = false;
  bool _saving = false;
  bool _deleted = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _loaded = !_isEdit;
    if (!_isEdit) {
      final preset = ref.read(categoryTypePresetProvider);
      if (preset != null) {
        _type = preset;
        if (preset == CategoryType.income) {
          _icon = 'briefcase';
          _color = '#22c55e';
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(categoryTypePresetProvider.notifier).set(null);
        });
      }
    }
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _loadFrom(TxCategory c) {
    _name.text = c.name;
    _type = c.type;
    _icon = categoryIcons.contains(c.icon) ? c.icon : categoryIcons.last;
    _color = c.color;
    _loaded = true;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    setState(() {
      _nameError = name.isEmpty
          ? 'Kasih nama dulu, ya'
          : (name.length > 60 ? 'Maksimal 60 karakter' : null);
    });
    if (_nameError != null) return;
    final input = CategoryInput(
      name: name,
      type: _type,
      color: _color,
      icon: _icon,
    );
    setState(() => _saving = true);
    final r = _isEdit
        ? await ref.read(updateCategoryProvider)(widget.id!, input)
        : await ref.read(createCategoryProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          _isEdit ? 'Kategori diperbarui 👍' : 'Kategori $name siap! 🎉',
        );
        popOr(context, '/categories');
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure is ValidationFailure && failure.field == 'name') {
            _nameError = failure.message;
          }
        });
        showFailureToast(context, failure);
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus kategori?',
      message:
          'Budget untuk "${_name.text.trim()}" ikut terhapus, dan transaksinya jadi tanpa kategori (transaksinya sendiri tetap aman).',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleted = true);
    final r = await ref.read(deleteCategoryProvider)(widget.id!);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Kategori dihapus', icon: Icons.delete_rounded);
        popOr(context, '/categories');
      case Err(:final failure):
        setState(() => _deleted = false);
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEdit && !_loaded) {
      final async = ref.watch(watchCategoryProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _loadFrom(value);
        case AsyncData():
          return _scaffold(
            const EmptyState(
              mood: MascotMood.thinking,
              title: 'Kategorinya nggak ketemu',
              message: 'Mungkin sudah dihapus di perangkat lain.',
            ),
          );
        case AsyncError():
          return _scaffold(
            ErrorRetry(
              onRetry: () => ref.invalidate(watchCategoryProvider(widget.id!)),
            ),
          );
        default:
          return _scaffold(
            const Padding(
              padding: EdgeInsets.all(GhinaSpace.page),
              child: SkeletonList(count: 4),
            ),
          );
      }
    }
    final g = context.ghina;
    final color = CategoryColors.parse(_color);
    final name = _name.text.trim();
    final width = MediaQuery.sizeOf(context).width;

    return _scaffold(
      Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.lg,
                GhinaSpace.page,
                GhinaSpace.xl,
              ),
              children: [
                Center(
                  child: PopIn(
                    key: ValueKey('preview-$_icon-$_color'),
                    fromScale: 0.85,
                    duration: GhinaMotion.medium,
                    child: CategoryAvatar(
                      iconName: _icon,
                      colorHex: _color,
                      size: 84,
                    ),
                  ),
                ),
                const SizedBox(height: GhinaSpace.sm),
                Text(
                  name.isEmpty ? 'Kategori baru' : name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h2
                      .w(900)
                      .copyWith(
                        color: name.isEmpty ? g.textMuted : g.textPrimary,
                      ),
                ),
                const SizedBox(height: GhinaSpace.xl),
                ChunkyTextField(
                  key: const ValueKey('category-name'),
                  controller: _name,
                  label: 'Nama kategori',
                  hint: 'Contoh: Jajan, Bensin, Gaji',
                  errorText: _nameError,
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                const SizedBox(height: GhinaSpace.lg),
                const FieldLabel('Jenis'),
                ChunkySegmented<CategoryType>(
                  value: _type,
                  onChanged: (t) => setState(() => _type = t),
                  segments: const [
                    ChunkySegment(
                      value: CategoryType.expense,
                      label: 'Pengeluaran',
                      color: GhinaColors.expense,
                    ),
                    ChunkySegment(
                      value: CategoryType.income,
                      label: 'Pemasukan',
                      color: GhinaColors.income,
                    ),
                  ],
                ),
                const SizedBox(height: GhinaSpace.xl),
                const FieldLabel('Ikon'),
                IconGridPicker(
                  selected: _icon,
                  icons: categoryIcons,
                  color: color,
                  crossAxisCount: width < 380 ? 5 : 6,
                  onChanged: (i) => setState(() => _icon = i),
                ),
                const SizedBox(height: GhinaSpace.xl),
                const FieldLabel('Warna'),
                ChunkyColorPicker(
                  selected: _color,
                  palette: colorPalette,
                  onChanged: (c) => setState(() => _color = c),
                ),
                if (_isEdit) ...[
                  const SizedBox(height: GhinaSpace.xl),
                  ChunkyButton(
                    key: const ValueKey('category-delete'),
                    label: 'Hapus kategori',
                    icon: Icons.delete_rounded,
                    variant: ChunkyButtonVariant.ghost,
                    color: GhinaColors.red,
                    onPressed: _deleted ? null : _delete,
                  ),
                ],
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: g.background,
              border: Border(
                top: BorderSide(color: g.border, width: GhinaDepth.border),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  GhinaSpace.md,
                  GhinaSpace.page,
                  GhinaSpace.md,
                ),
                child: ChunkyButton(
                  key: const ValueKey('category-save'),
                  label: _isEdit ? 'Simpan perubahan' : 'Simpan kategori',
                  loading: _saving,
                  color: ChunkySwatch.fromColor(color),
                  onPressed: _saving || _deleted ? null : _save,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scaffold(Widget body) => Scaffold(
    appBar: AppBar(
      title: Text(_isEdit ? 'Edit kategori' : 'Kategori baru'),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Tutup',
        onPressed: () => popOr(context, '/categories'),
      ),
    ),
    body: body,
  );
}
