import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/wallet_visuals.dart';
import 'wallets_page.dart' show WalletCard;

/// Create / edit a wallet with a live preview card.
class WalletFormPage extends ConsumerStatefulWidget {
  const WalletFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  ConsumerState<WalletFormPage> createState() => _WalletFormPageState();
}

class _WalletFormPageState extends ConsumerState<WalletFormPage> {
  bool get _isEdit => widget.id != null;

  final _name = TextEditingController();
  final _balance = TextEditingController();
  WalletType _type = WalletType.cash;
  String _color = colorPalette.first;
  String? _icon;
  late String _currency;
  bool _archived = false;
  Wallet? _original;

  bool _loaded = false;
  bool _saving = false;
  bool _deleted = false;
  String? _nameError;
  String? _balanceError;

  @override
  void initState() {
    super.initState();
    _currency = ref.read(currencyProvider);
    _loaded = !_isEdit;
    _name.addListener(_refresh);
    _balance.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _loadFrom(Wallet w) {
    _original = w;
    _name.text = w.name;
    _type = w.type;
    _color = w.color;
    _icon = (w.icon == w.type.wire || !GhinaIcons.byName.containsKey(w.icon))
        ? null
        : w.icon;
    _currency = w.currency;
    _archived = w.archived;
    _loaded = true;
  }

  double? get _parsedBalance {
    final t = _balance.text.trim();
    if (t.isEmpty) return 0;
    if (GhinaMoney.decimalsFor(_currency) == 0) return Fmt.parseAmount(t);
    // e.g. USD "1,234.50"
    return double.tryParse(t.replaceAll(',', ''));
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final bal = _parsedBalance;
    setState(() {
      _nameError = name.isEmpty
          ? 'Kasih nama dulu, ya'
          : (name.length > 60 ? 'Maksimal 60 karakter' : null);
      _balanceError = !_isEdit && bal == null ? 'Angkanya belum pas' : null;
    });
    if (_nameError != null || _balanceError != null) return;
    final input = WalletInput(
      name: name,
      type: _type,
      currency: _currency,
      color: _color,
      icon: _icon,
      initialBalance: bal ?? 0,
      archived: _archived,
    );
    setState(() => _saving = true);
    final r = _isEdit
        ? await ref.read(updateWalletProvider)(widget.id!, input)
        : await ref.read(createWalletProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          _isEdit ? 'Dompet diperbarui 👍' : 'Dompet $name siap dipakai! 🎉',
        );
        popOr(context, '/wallets');
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
      title: 'Hapus dompet ini?',
      message:
          'Semua transaksi di "${_name.text.trim()}" (termasuk transfer dari/ke dompet ini) ikut terhapus permanen. '
          'Kalau cuma mau disembunyikan, arsipkan saja.',
      confirmLabel: 'Hapus permanen',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleted = true);
    final r = await ref.read(deleteWalletProvider)(widget.id!);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Dompet dihapus', icon: Icons.delete_rounded);
        popOr(context, '/wallets');
      case Err(:final failure):
        setState(() => _deleted = false);
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEdit && !_loaded) {
      final async = ref.watch(watchWalletProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _loadFrom(value);
        case AsyncData():
          return _scaffold(
            const EmptyState(
              mood: MascotMood.thinking,
              title: 'Dompetnya nggak ketemu',
              message: 'Mungkin sudah dihapus di perangkat lain.',
            ),
          );
        case AsyncError():
          return _scaffold(
            ErrorRetry(
              onRetry: () => ref.invalidate(watchWalletProvider(widget.id!)),
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
    // Live balance in edit mode (read-only).
    final live = _isEdit && !_deleted
        ? ref.watch(watchWalletProvider(widget.id!)).value ?? _original
        : null;
    final g = context.ghina;
    final now = DateTime.now();
    final preview = Wallet(
      id: widget.id ?? 'preview',
      name: _name.text.trim().isEmpty ? 'Dompet baru' : _name.text.trim(),
      type: _type,
      balance: live?.balance ?? (_parsedBalance ?? 0),
      syncedBalance: live?.syncedBalance ?? (_parsedBalance ?? 0),
      currency: _currency,
      color: _color,
      icon: _icon ?? _type.wire,
      archived: _archived,
      createdAt: now,
      updatedAt: now,
    );

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
                WalletCard(wallet: preview),
                const SizedBox(height: GhinaSpace.xl),
                ChunkyTextField(
                  key: const ValueKey('wallet-name'),
                  controller: _name,
                  label: 'Nama dompet',
                  hint: 'Contoh: BCA, GoPay, Dompet harian',
                  errorText: _nameError,
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                const SizedBox(height: GhinaSpace.lg),
                const FieldLabel('Jenis'),
                ChunkyChoiceChips<WalletType>(
                  options: [
                    for (final t in WalletType.values)
                      ChunkyChoice(
                        value: t,
                        label: t.label,
                        icon: GhinaIcons.walletType(t.wire),
                      ),
                  ],
                  selected: {_type},
                  onChanged: (s) {
                    if (s.isNotEmpty) setState(() => _type = s.first);
                  },
                ),
                const SizedBox(height: GhinaSpace.lg),
                if (!_isEdit) ...[
                  ChunkyTextField(
                    key: const ValueKey('wallet-balance'),
                    controller: _balance,
                    label: 'Saldo awal',
                    hint: '0',
                    helperText: 'Isi saldo yang ada sekarang. Boleh 0.',
                    errorText: _balanceError,
                    prefixIcon: Icons.payments_rounded,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                    ],
                    onChanged: (_) {
                      if (_balanceError != null) {
                        setState(() => _balanceError = null);
                      }
                    },
                  ),
                  const SizedBox(height: GhinaSpace.lg),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
                    child: ChunkyCard(
                      tinted: GhinaColors.blue,
                      padding: const EdgeInsets.all(GhinaSpace.md),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_rounded,
                            color: GhinaColors.blue.base,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Saldo berubah lewat transaksi. Mau koreksi? Catat pemasukan/pengeluaran penyesuaian.',
                              style: GhinaType.bodyS.copyWith(
                                color: g.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const FieldLabel('Mata uang'),
                ChunkyChoiceChips<String>(
                  scrollable: true,
                  options: [
                    for (final c in supportedCurrencies)
                      ChunkyChoice(value: c, label: c),
                  ],
                  selected: {_currency},
                  onChanged: (s) {
                    if (s.isNotEmpty) setState(() => _currency = s.first);
                  },
                ),
                const SizedBox(height: GhinaSpace.xl),
                const FieldLabel('Warna'),
                ChunkyColorPicker(
                  selected: _color,
                  palette: colorPalette,
                  onChanged: (c) => setState(() => _color = c),
                ),
                const SizedBox(height: GhinaSpace.xl),
                FieldLabel(
                  'Ikon',
                  trailing: _icon == null
                      ? null
                      : GestureDetector(
                          onTap: () => setState(() => _icon = null),
                          child: Text(
                            'IKUTI JENIS',
                            style: GhinaType.caption
                                .w(900)
                                .copyWith(color: GhinaColors.blue.base),
                          ),
                        ),
                ),
                IconGridPicker(
                  selected: _icon,
                  icons: walletIconChoices,
                  color: CategoryColors.parse(_color),
                  onChanged: (i) =>
                      setState(() => _icon = _icon == i ? null : i),
                ),
                if (_isEdit) ...[
                  const SizedBox(height: GhinaSpace.xl),
                  ChunkyCard(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Arsipkan dompet',
                                style: GhinaType.h3.copyWith(
                                  color: g.textPrimary,
                                ),
                              ),
                              Text(
                                'Disembunyikan dari daftar & total saldo, transaksinya tetap aman.',
                                style: GhinaType.bodyS.copyWith(
                                  color: g.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          key: const ValueKey('wallet-archive'),
                          value: _archived,
                          onChanged: (v) => setState(() => _archived = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: GhinaSpace.lg),
                  ChunkyButton(
                    key: const ValueKey('wallet-delete'),
                    label: 'Hapus dompet',
                    icon: Icons.delete_rounded,
                    variant: ChunkyButtonVariant.ghost,
                    color: GhinaColors.red,
                    onPressed: _deleted ? null : _delete,
                  ),
                ],
              ],
            ),
          ),
          _BottomBar(
            child: ChunkyButton(
              key: const ValueKey('wallet-save'),
              label: _isEdit ? 'Simpan perubahan' : 'Simpan dompet',
              loading: _saving,
              onPressed: _saving || _deleted ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scaffold(Widget body) => Scaffold(
    appBar: AppBar(
      title: Text(_isEdit ? 'Edit dompet' : 'Dompet baru'),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Tutup',
        onPressed: () => popOr(context, '/wallets'),
      ),
    ),
    body: body,
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return DecoratedBox(
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
          child: child,
        ),
      ),
    );
  }
}
