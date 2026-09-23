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

/// Icons offered for subscriptions: the category set plus the preset ones.
final _subscriptionIcons = <String>{
  'tv',
  'music',
  'cloud',
  'sparkles',
  ...GhinaIcons.categoryNames,
}.toList();

/// Add or edit a subscription (with the web's quick-pick presets).
class SubscriptionFormPage extends ConsumerWidget {
  const SubscriptionFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return const _SubscriptionForm(existing: null);
    final sub = ref.watch(watchSubscriptionProvider(id));
    Scaffold frame(Widget body) => Scaffold(
      appBar: AppBar(title: const Text('Ubah langganan')),
      body: body,
    );
    return sub.when(
      skipLoadingOnReload: true,
      loading: () => frame(const LoadingListView(tiles: 3)),
      error: (_, _) => frame(
        ErrorRetry(
          onRetry: () => ref.invalidate(watchSubscriptionProvider(id)),
        ),
      ),
      data: (s) => s == null
          ? frame(
              EmptyState(
                mood: MascotMood.thinking,
                title: 'Langganan nggak ketemu',
                message: 'Mungkin sudah dihapus.',
                actionLabel: 'Kembali',
                onAction: () => context.pop(),
              ),
            )
          : _SubscriptionForm(existing: s),
    );
  }
}

class _SubscriptionForm extends ConsumerStatefulWidget {
  const _SubscriptionForm({required this.existing});
  final Subscription? existing;

  @override
  ConsumerState<_SubscriptionForm> createState() => _SubscriptionFormState();
}

class _SubscriptionFormState extends ConsumerState<_SubscriptionForm> {
  Subscription? get e => widget.existing;
  bool get _isEdit => e != null;

  late final String _currency = e?.currency ?? ref.read(currencyProvider);
  late final _name = TextEditingController(text: e?.name ?? '');
  late final _amount = TextEditingController(
    text: amountToInput(e?.amount, _currency),
  );
  late final _note = TextEditingController(text: e?.note ?? '');
  late BillingCycle _cycle = e?.cycle ?? BillingCycle.monthly;
  late DateTime _next =
      e?.nextBilling ?? startOfDay(ref.read(clockProvider).now());
  late String? _walletId = e?.walletId;
  late String? _categoryId = e?.categoryId;
  late String _color = e?.color ?? '#6366f1';
  late String _icon = e?.icon ?? 'credit-card';
  late bool _active = e?.active ?? true;
  String? _nameError;
  String? _amountError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _applyPreset(
    ({String name, String color, String icon, BillingCycle cycle}) p,
  ) => setState(() {
    _name.text = p.name;
    _cycle = p.cycle;
    _color = p.color.toLowerCase();
    _icon = p.icon;
    _nameError = null;
  });

  Future<void> _save() async {
    final amount = parseAmountInput(_amount.text) ?? 0;
    setState(() {
      _nameError = _name.text.trim().isEmpty
          ? 'Kasih nama langganannya dulu, ya'
          : null;
      _amountError = amount <= 0 ? 'Isi nominal tagihannya dulu, ya' : null;
    });
    if (_nameError != null || _amountError != null) return;
    setState(() => _saving = true);
    final input = SubscriptionInput(
      name: _name.text.trim(),
      amount: amount,
      currency: _currency,
      cycle: _cycle,
      nextBilling: _next,
      categoryId: _categoryId,
      walletId: _walletId,
      color: _color,
      icon: _icon,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      active: _active,
    );
    final r = _isEdit
        ? await ref.read(updateSubscriptionProvider)(e!.id, input)
        : await ref.read(createSubscriptionProvider)(input);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        showToastBadge(
          context,
          message: _isEdit
              ? 'Langganan diperbarui 👍'
              : '${value.name} tercatat! Ghina ingetin tagihannya 🔔',
          icon: Icons.event_repeat_rounded,
          color: GhinaColors.green,
        );
        context.pop();
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus ${e!.name}?',
      message:
          'Cuma pengingatnya yang dihapus. Transaksi yang sudah tercatat tetap aman.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteSubscriptionProvider)(e!.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Langganan dihapus',
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
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final cats =
        ref.watch(watchCategoriesProvider(CategoryType.expense)).value ??
        const <TxCategory>[];
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final amount = parseAmountInput(_amount.text) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah langganan' : 'Langganan baru'),
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
          // Live preview.
          ChunkyCard(
            tinted: CategoryColors.swatch(_color),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CategoryAvatar(iconName: _icon, colorHex: _color, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name.text.trim().isEmpty
                            ? 'Nama langganan'
                            : _name.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.h3.copyWith(color: g.textPrimary),
                      ),
                      Text(
                        '${GhinaMoney.format(amount, currency: _currency)}${_cycle.per}'
                        '${_cycle == BillingCycle.monthly || amount == 0 ? '' : ' · ≈ ${GhinaMoney.format(_cycle.monthlyAmount(amount), currency: _currency)}/bln'}',
                        maxLines: 2,
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 18),
            const FieldLabel('Pilih cepat'),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: subscriptionPresets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = subscriptionPresets[i];
                  return Center(
                    child: ChunkyChip(
                      label: p.name,
                      icon: GhinaIcons.of(p.icon),
                      color: CategoryColors.swatch(p.color),
                      selected: _name.text == p.name,
                      onTap: () => _applyPreset(p),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          ChunkyTextField(
            label: 'Nama',
            hint: 'mis. Netflix',
            controller: _name,
            errorText: _nameError,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _nameError = null),
          ),
          const SizedBox(height: 10),
          AmountField(
            controller: _amount,
            currency: _currency,
            label: 'Nominal tagihan',
            errorText: _amountError,
            onChanged: (_) => setState(() => _amountError = null),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Siklus tagihan'),
          ChunkySegmented<BillingCycle>(
            segments: [
              for (final c in BillingCycle.values)
                ChunkySegment(
                  value: c,
                  label: c.label,
                  color: GhinaColors.purple,
                ),
            ],
            value: _cycle,
            onChanged: (c) => setState(() => _cycle = c),
          ),
          const SizedBox(height: 18),
          DateField(
            label: 'Tagihan berikutnya',
            value: _next,
            onChanged: (d) => setState(() => _next = d),
          ),
          const SizedBox(height: 18),
          PickerField(
            label: 'Dibayar pakai',
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
                title: 'Dibayar pakai',
                noneLabel: 'Tanpa dompet',
              );
              if (id != null) {
                setState(() => _walletId = id.isEmpty ? null : id);
              }
            },
          ),
          if (wallets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                'Tips: bikin dompet "GoPay" atau kartumu dulu biar bisa dipilih di sini.',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
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
          const FieldLabel('Warna'),
          ChunkyColorPicker(
            selected: _color,
            size: 40,
            onChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Ikon'),
          IconGridPicker(
            selected: _icon,
            icons: _subscriptionIcons,
            color: CategoryColors.parse(_color),
            onChanged: (i) => setState(() => _icon = i),
          ),
          const SizedBox(height: 18),
          ChunkyTextField(
            label: 'Catatan',
            hint: 'Opsional',
            controller: _note,
            maxLength: 200,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 8),
            ChunkyCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: Text(
                  'Aktif',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                subtitle: Text(
                  _active ? 'Dihitung ke total bulanan' : 'Lagi dijeda',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
