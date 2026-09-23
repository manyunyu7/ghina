import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../budgets_state.dart';
import '../../../shared/widgets/widgets.dart';

/// Create a monthly budget for an expense category, or edit its amount.
class BudgetFormPage extends ConsumerWidget {
  const BudgetFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return const _BudgetForm(existing: null);
    final budget = ref.watch(watchBudgetProvider(id));
    return budget.when(
      skipLoadingOnReload: true,
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Ubah budget')),
        body: const LoadingListView(tiles: 2),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Ubah budget')),
        body: ErrorRetry(
          onRetry: () => ref.invalidate(watchBudgetProvider(id)),
        ),
      ),
      data: (b) => b == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Ubah budget')),
              body: EmptyState(
                mood: MascotMood.thinking,
                title: 'Budget nggak ketemu',
                message: 'Mungkin sudah dihapus. Balik ke daftar budget, yuk.',
                actionLabel: 'Kembali',
                onAction: () => context.pop(),
              ),
            )
          : _BudgetForm(existing: b),
    );
  }
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({required this.existing});

  final Budget? existing;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  late final String _currency = ref.read(currencyProvider);
  late final _amount = TextEditingController(
    text: amountToInput(widget.existing?.amount, _currency),
  );
  late YearMonth _month =
      widget.existing?.period ?? ref.read(budgetsMonthProvider);
  String? _categoryId;
  String? _amountError;
  String? _categoryError;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?.categoryId;
    if (!_isEdit) {
      _categoryId = ref.read(budgetDraftCategoryProvider);
      // Consume the draft after this frame (can't modify providers during build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(budgetDraftCategoryProvider.notifier).set(null);
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickCategory(List<TxCategory> cats, BudgetMonth? bm) async {
    final byCat = {
      for (final b in bm?.items ?? const <BudgetView>[]) b.budget.categoryId: b,
    };
    final picked = await showCategoryPickerSheet(
      context,
      categories: cats,
      selectedId: _categoryId,
      title: 'Kategori pengeluaran',
      subtitleOf: (c) => byCat[c.id] == null
          ? 'Belum ada budget'
          : 'Sudah ada: ${GhinaMoney.format(byCat[c.id]!.budget.amount, currency: _currency)}',
      onCreateNew: () => context.push('/categories/new'),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _categoryId = picked;
        _categoryError = null;
      });
    }
  }

  Future<void> _save(BudgetView? existingForCategory) async {
    final amount = parseAmountInput(_amount.text) ?? 0;
    setState(() {
      _amountError = amount <= 0 ? 'Isi nominal budget-nya dulu, ya' : null;
      _categoryError = !_isEdit && _categoryId == null
          ? 'Pilih kategori dulu, ya'
          : null;
    });
    if (_amountError != null || _categoryError != null) return;

    setState(() => _saving = true);
    final Result<Budget> r = _isEdit
        ? await ref.read(updateBudgetAmountProvider)(
            widget.existing!.id,
            amount,
          )
        : await ref.read(setBudgetProvider)(
            categoryId: _categoryId!,
            amount: amount,
            month: _month,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: _isEdit || existingForCategory != null
              ? 'Budget diperbarui 👍'
              : 'Budget terpasang! Ghina jagain ya 🎯',
          icon: Icons.savings_rounded,
          color: GhinaColors.green,
        );
        ref.read(budgetsMonthProvider.notifier).set(_month);
        context.pop();
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  Future<void> _delete(String name) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus budget $name?',
      message: 'Transaksinya tetap aman, cuma batas budget-nya yang dihapus.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteBudgetProvider)(widget.existing!.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Budget dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        context.pop();
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final now = ref.watch(clockProvider).now();
    final cats =
        ref.watch(watchCategoriesProvider(CategoryType.expense)).value ??
        const <TxCategory>[];
    final bm = ref.watch(watchBudgetMonthProvider(_month)).value;
    final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final existingForCategory = bm?.items
        .where((b) => b.budget.categoryId == _categoryId)
        .firstOrNull;
    final duplicate = !_isEdit ? existingForCategory : null;
    final usage = _isEdit ? existingForCategory : null;
    final name = cat?.name ?? 'ini';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah budget' : 'Pasang budget'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Hapus',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: GhinaColors.red.base,
              ),
              onPressed: () => _delete(name),
            ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ChunkyButton(
          label: _isEdit || duplicate != null ? 'Perbarui' : 'Simpan',
          loading: _saving,
          onPressed: () => _save(existingForCategory),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          MascotSpeech(
            mood: MascotMood.thinking,
            mascotSize: 64,
            message: _isEdit
                ? 'Mau longgarin atau ketatin? Atur sesuai kebutuhanmu.'
                : 'Tentuin batas belanja sebulan. Kalau kelewat, 1 hati hilang lho!',
          ),
          const SizedBox(height: 20),
          if (_isEdit) ...[
            ChunkyCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CategoryAvatar(
                    iconName: cat?.icon ?? 'circle',
                    colorHex: cat?.color ?? CategoryTotal.uncategorizedColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat?.name ?? 'Kategori',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.h3.copyWith(color: g.textPrimary),
                        ),
                        Text(
                          monthLabel(_month),
                          style: GhinaType.bodyS.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (usage != null) ...[
              const SizedBox(height: 12),
              ChunkyProgressBar.budget(used: usage.pct / 100, height: 12),
              const SizedBox(height: 6),
              Text(
                'Sudah terpakai ${GhinaMoney.format(usage.spent, currency: _currency)} (${usage.pct.round()}%)',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ],
          ] else ...[
            const FieldLabel('Bulan'),
            MonthSwitcher(
              value: _month,
              current: YearMonth.of(now),
              onChanged: (m) => setState(() => _month = m),
            ),
            const SizedBox(height: 18),
            PickerField(
              label: 'Kategori',
              placeholder: 'Pilih kategori pengeluaran',
              value: cat?.name,
              errorText: _categoryError,
              leading: cat == null
                  ? null
                  : CategoryAvatar(
                      iconName: cat.icon,
                      colorHex: cat.color,
                      size: 36,
                    ),
              onTap: () => _pickCategory(cats, bm),
            ),
            if (duplicate != null) ...[
              const SizedBox(height: 10),
              ChunkyCard(
                tinted: GhinaColors.blue,
                depth: 0,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_rounded, color: GhinaColors.blue.base),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$name sudah punya budget ${GhinaMoney.format(duplicate.budget.amount, currency: _currency)} di ${monthLabel(_month)}. Nominal barunya bakal gantiin yang lama.',
                        style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          AmountField(
            controller: _amount,
            currency: _currency,
            label: 'Batas sebulan',
            errorText: _amountError,
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
          if (_currency == 'IDR') ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (q, l) in const [
                  (250000, '250rb'),
                  (500000, '500rb'),
                  (1000000, '1jt'),
                  (2000000, '2jt'),
                ])
                  ChunkyChip(
                    label: l,
                    selected: parseAmountInput(_amount.text) == q,
                    color: GhinaColors.green,
                    onTap: () => setState(() {
                      _amount.text = amountToInput(q, _currency);
                      _amountError = null;
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
