import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// "Sesuaikan saldo": the user enters the wallet's real balance, sees the
/// difference, and saves it as a balance adjustment (works offline). Returns
/// true when an adjustment was recorded.
Future<bool> showAdjustBalanceSheet(
  BuildContext context,
  WidgetRef ref,
  Wallet wallet,
) async {
  final ok = await showChunkyBottomSheet<bool>(
    context,
    title: 'Sesuaikan saldo',
    showClose: true,
    builder: (c) => AdjustBalanceSheet(wallet: wallet),
  );
  return ok ?? false;
}

class AdjustBalanceSheet extends ConsumerStatefulWidget {
  const AdjustBalanceSheet({super.key, required this.wallet});

  final Wallet wallet;

  @override
  ConsumerState<AdjustBalanceSheet> createState() => _AdjustBalanceSheetState();
}

class _AdjustBalanceSheetState extends ConsumerState<AdjustBalanceSheet> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  late bool _negative;
  bool _saving = false;

  /// Proof photos (e.g. a bank app screenshot), attached after the adjustment
  /// is recorded.
  List<String> _photos = const [];

  @override
  void initState() {
    super.initState();
    final w = widget.wallet;
    _negative = w.balance < 0;
    _amount = TextEditingController(
      text: amountToInput(w.balance.abs(), w.currency),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Live wallet (balance may change while the sheet is open, e.g. a sync).
  Wallet get _wallet =>
      ref.watch(watchWalletProvider(widget.wallet.id)).value ?? widget.wallet;

  double? get _target {
    final v = parseAmountInput(_amount.text);
    if (v == null) return null;
    return _negative ? -v : v;
  }

  Future<void> _save(Wallet w, double target) async {
    if (_saving) return;
    setState(() => _saving = true);
    final r = await ref.read(adjustWalletBalanceProvider)(
      w.id,
      target,
      note: _note.text,
    );
    if (r case Ok(:final value) when _photos.isNotEmpty) {
      final pr = await ref.read(addTransactionPhotosProvider)(
        value.id,
        _photos,
      );
      if (pr case Err(:final failure) when mounted) {
        showFailureToast(context, failure);
      }
    }
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Saldo ${w.name} disesuaikan 👍');
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() => _saving = false);
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final w = _wallet;
    final target = _target;
    final delta = target == null ? 0.0 : adjustmentDelta(w.balance, target);
    final changed = delta != 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTile(
          leading: WalletAvatar(wallet: w, size: 40),
          title: 'Saldo di Ghina',
          subtitle: w.name,
          dense: true,
          trailing: MoneyText(
            key: const ValueKey('adjust-current'),
            amount: w.balance,
            currency: w.currency,
            tone: MoneyTone.neutral,
            style: GhinaType.moneyM,
          ),
        ),
        const SizedBox(height: GhinaSpace.lg),
        AmountField(
          key: const ValueKey('adjust-amount'),
          controller: _amount,
          currency: w.currency,
          label: 'Saldo sebenarnya',
          helperText: 'Cek saldo di rekening / dompetmu, lalu isi di sini.',
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: GhinaSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: ChunkyChip(
            key: const ValueKey('adjust-negative'),
            label: 'Saldo minus',
            icon: Icons.remove_circle_outline_rounded,
            selected: _negative,
            color: GhinaColors.red,
            onTap: () => setState(() => _negative = !_negative),
          ),
        ),
        const SizedBox(height: GhinaSpace.lg),
        AnimatedSwitcher(
          duration: GhinaMotion.fast,
          child: ChunkyCard(
            key: ValueKey('adjust-diff-$changed'),
            tinted: changed ? GhinaColors.blue : null,
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Row(
              children: [
                CategoryAvatar(
                  icon: Icons.tune_rounded,
                  color: changed ? GhinaColors.blue.base : g.textMuted,
                  size: 40,
                  soft: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selisih',
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textSecondary),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: MoneyText(
                          key: const ValueKey('adjust-delta'),
                          text: GhinaMoney.format(
                            delta,
                            currency: w.currency,
                            showSign: true,
                          ),
                          tone: MoneyTone.neutral,
                          style: GhinaType.moneyL,
                        ),
                      ),
                      Text(
                        changed
                            ? 'Dicatat sebagai "Penyesuaian saldo", bukan pemasukan/pengeluaran.'
                            : 'Saldonya sudah sama. Nggak ada yang perlu disesuaikan.',
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: GhinaSpace.md),
        ChunkyTextField(
          key: const ValueKey('adjust-note'),
          controller: _note,
          label: 'Catatan (opsional)',
          hint: 'Contoh: biaya admin bank',
          maxLength: 200,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: GhinaSpace.sm),
        FieldLabel('Foto bukti (opsional)'),
        PhotoStrip(
          key: const ValueKey('adjust-photos'),
          photos: [for (final p in _photos) ViewerPhoto.file(p)],
          size: 56,
          max: maxTransactionPhotos,
          heroScope: 'adjust',
          onRemove: (i) => setState(() => _photos = [..._photos]..removeAt(i)),
          onAdd: () async {
            final picked = await pickPhotos(
              context,
              ref,
              remaining: maxTransactionPhotos - _photos.length,
              max: maxTransactionPhotos,
            );
            if (picked.isEmpty || !mounted) return;
            setState(
              () => _photos = [
                ..._photos,
                for (final p in picked)
                  if (!_photos.contains(p)) p,
              ],
            );
          },
        ),
        const SizedBox(height: GhinaSpace.lg),
        ChunkyButton(
          key: const ValueKey('adjust-save'),
          label: 'Simpan penyesuaian',
          size: ChunkyButtonSize.large,
          loading: _saving,
          onPressed: changed && target != null && !_saving
              ? () => _save(w, target)
              : null,
        ),
      ],
    );
  }
}
