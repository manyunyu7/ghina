import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/widgets/widgets.dart';
import '../forecast_state.dart';

/// Add or edit a planned (expected) income/expense.
class PlannedFormPage extends ConsumerWidget {
  const PlannedFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return const _PlannedForm(existing: null);
    final item = ref.watch(watchPlannedProvider(id));
    Scaffold frame(Widget body) => Scaffold(
      appBar: AppBar(title: const Text('Ubah rencana')),
      body: body,
    );
    return item.when(
      skipLoadingOnReload: true,
      loading: () => frame(const LoadingListView(tiles: 3)),
      error: (_, _) => frame(
        ErrorRetry(onRetry: () => ref.invalidate(watchPlannedProvider(id))),
      ),
      data: (p) => p == null
          ? frame(
              EmptyState(
                mood: MascotMood.thinking,
                title: 'Rencana nggak ketemu',
                message: 'Mungkin sudah dihapus atau dijadikan transaksi.',
                actionLabel: 'Kembali',
                onAction: () => context.pop(),
              ),
            )
          : _PlannedForm(existing: p),
    );
  }
}

class _PlannedForm extends ConsumerStatefulWidget {
  const _PlannedForm({required this.existing});
  final PlannedTransaction? existing;

  @override
  ConsumerState<_PlannedForm> createState() => _PlannedFormState();
}

class _PlannedFormState extends ConsumerState<_PlannedForm> {
  PlannedTransaction? get e => widget.existing;
  bool get _isEdit => e != null;

  late final String _currency = ref.read(currencyProvider);
  late TxType _type = e?.type ?? TxType.expense;
  late final _note = TextEditingController(text: e?.note ?? '');
  late final _amount = TextEditingController(
    text: amountToInput(e?.amount, _currency),
  );
  late DateTime _date = e?.date ?? _defaultDate();
  late String? _categoryId = e?.categoryId;
  late String? _walletId = e?.walletId;
  String? _noteError;
  String? _amountError;
  bool _saving = false;

  DateTime _defaultDate() {
    final now = ref.read(clockProvider).now();
    final m = ref.read(forecastMonthProvider);
    return m.contains(now) ? startOfDay(now) : m.start;
  }

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmountInput(_amount.text) ?? 0;
    setState(() {
      _noteError = _note.text.trim().isEmpty
          ? 'Tulis dulu ini rencana apa, ya'
          : null;
      _amountError = amount <= 0 ? 'Isi nominalnya dulu, ya' : null;
    });
    if (_noteError != null || _amountError != null) return;
    setState(() => _saving = true);
    final input = PlannedInput(
      type: _type,
      amount: amount,
      note: _note.text.trim(),
      date: _date,
      categoryId: _categoryId,
      walletId: _walletId,
    );
    final r = _isEdit
        ? await ref.read(updatePlannedProvider)(e!.id, input)
        : await ref.read(createPlannedProvider)(input);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: _isEdit
              ? 'Rencana diperbarui 👍'
              : 'Rencana dicatat! Masuk ke perkiraan 📅',
          icon: Icons.event_available_rounded,
          color: GhinaColors.green,
        );
        ref.read(forecastMonthProvider.notifier).set(YearMonth.of(_date));
        context.pop();
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus rencana ini?',
      message: '"${e!.note ?? 'Rencana ini'}" bakal hilang dari perkiraan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deletePlannedProvider)(e!.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Rencana dihapus',
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
    final catType = _type == TxType.income
        ? CategoryType.income
        : CategoryType.expense;
    final cats =
        ref.watch(watchCategoriesProvider(catType)).value ??
        const <TxCategory>[];
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final expense = _type == TxType.expense;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah rencana' : 'Rencana baru'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Hapus',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: GhinaColors.red.base,
              ),
              onPressed: _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ChunkyButton(
          label: _isEdit ? 'Perbarui' : 'Simpan',
          loading: _saving,
          onPressed: _save,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (!_isEdit) ...[
            const MascotSpeech(
              mood: MascotMood.thinking,
              mascotSize: 64,
              message:
                  'Catat yang bakal datang: tagihan, gajian, atau sekali bayar. Saldo dompet nggak berubah kok.',
            ),
            const SizedBox(height: 20),
          ],
          ChunkySegmented<TxType>(
            segments: const [
              ChunkySegment(
                value: TxType.expense,
                label: 'Uang keluar',
                icon: Icons.north_east_rounded,
                color: GhinaColors.red,
              ),
              ChunkySegment(
                value: TxType.income,
                label: 'Uang masuk',
                icon: Icons.south_west_rounded,
                color: GhinaColors.green,
              ),
            ],
            value: _type,
            onChanged: (t) => setState(() {
              _type = t;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 18),
          ChunkyTextField(
            label: 'Ini rencana apa?',
            hint: expense ? 'mis. Pajak motor' : 'mis. Gajian',
            controller: _note,
            errorText: _noteError,
            maxLength: 200,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_noteError != null) setState(() => _noteError = null);
            },
          ),
          const SizedBox(height: 10),
          AmountField(
            controller: _amount,
            currency: _currency,
            errorText: _amountError,
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
          const SizedBox(height: 18),
          DateField(
            label: 'Perkiraan tanggal',
            value: _date,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 18),
          PickerField(
            label: 'Kategori',
            placeholder: 'Tanpa kategori',
            value: cat?.name,
            leading: cat == null
                ? null
                : CategoryAvatar(
                    iconName: cat.icon,
                    colorHex: cat.color,
                    size: 34,
                  ),
            onTap: () async {
              final id = await showCategoryPickerSheet(
                context,
                categories: cats,
                selectedId: _categoryId,
                noneLabel: 'Tanpa kategori',
              );
              if (id != null) {
                setState(() => _categoryId = id.isEmpty ? null : id);
              }
            },
          ),
          const SizedBox(height: 18),
          PickerField(
            label: 'Dompet',
            placeholder: 'Tanpa dompet',
            value: wallet?.name,
            leading: wallet == null
                ? null
                : WalletAvatar(wallet: wallet, size: 34),
            onTap: () async {
              final id = await showWalletPickerSheet(
                context,
                wallets: wallets,
                currency: _currency,
                selectedId: _walletId,
                noneLabel: 'Tanpa dompet',
              );
              if (id != null) {
                setState(() => _walletId = id.isEmpty ? null : id);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              'Dipakai waktu rencana ini dijadikan transaksi beneran.',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
