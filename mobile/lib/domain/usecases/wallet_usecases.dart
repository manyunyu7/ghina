import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

/// Form data for creating/updating a wallet.
final class WalletInput {
  const WalletInput({
    required this.name,
    this.type = WalletType.cash,
    this.currency = 'IDR',
    this.color = '#6366f1',
    this.icon,
    this.initialBalance = 0,
    this.archived = false,
  });

  final String name;
  final WalletType type;
  final String currency;
  final String color;

  /// Icon id; null/blank defaults to the wallet type's id (as on the web).
  final String? icon;

  String get effectiveIcon {
    final i = icon?.trim();
    return (i == null || i.isEmpty) ? type.wire : i;
  }

  /// Only used on create — afterwards the balance changes only through transactions.
  final double initialBalance;
  final bool archived;
}

/// Wallets, sorted by creation. Archived ones excluded unless [includeArchived].
final class WatchWallets {
  const WatchWallets(this._repo);
  final WalletRepository _repo;

  Stream<List<Wallet>> call({bool includeArchived = false}) =>
      _repo.watchAll(includeArchived: includeArchived);
}

final class WatchWallet {
  const WatchWallet(this._repo);
  final WalletRepository _repo;

  Stream<Wallet?> call(String id) => _repo.watchById(id);
}

final class CreateWallet {
  const CreateWallet(this._repo, this._clock);
  final WalletRepository _repo;
  final Clock _clock;

  Future<Result<Wallet>> call(WalletInput input) => guard(() async {
    final balance = input.initialBalance;
    if (!balance.isFinite) {
      throw const ValidationFailure(
        'Saldo awal tidak valid',
        field: 'initialBalance',
      );
    }
    final now = _clock.now();
    final wallet = Wallet(
      id: newId(),
      name: requireName(input.name),
      type: input.type,
      balance: balance,
      syncedBalance: balance,
      currency: requireCurrency(input.currency),
      color: requireColor(input.color),
      icon: requireName(input.effectiveIcon, max: 40, field: 'icon'),
      archived: input.archived,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.save(wallet);
    return wallet;
  });
}

/// Updates everything but the balance (`initialBalance` is ignored).
final class UpdateWallet {
  const UpdateWallet(this._repo, this._clock);
  final WalletRepository _repo;
  final Clock _clock;

  Future<Result<Wallet>> call(String id, WalletInput input) => guard(() async {
    final existing = await _repo.getById(id);
    if (existing == null) throw const NotFoundFailure('Dompet tidak ditemukan');
    final wallet = existing.copyWith(
      name: requireName(input.name),
      type: input.type,
      currency: requireCurrency(input.currency),
      color: requireColor(input.color),
      icon: requireName(input.effectiveIcon, max: 40, field: 'icon'),
      archived: input.archived,
      updatedAt: _clock.now(),
    );
    await _repo.save(wallet);
    return wallet;
  });
}

final class SetWalletArchived {
  const SetWalletArchived(this._repo, this._clock);
  final WalletRepository _repo;
  final Clock _clock;

  Future<Result<void>> call(String id, bool archived) => guard(() async {
    final existing = await _repo.getById(id);
    if (existing == null) throw const NotFoundFailure('Dompet tidak ditemukan');
    await _repo.save(
      existing.copyWith(archived: archived, updatedAt: _clock.now()),
    );
  });
}

/// Deletes the wallet **and all its transactions** (either side of transfers).
final class DeleteWallet {
  const DeleteWallet(this._repo);
  final WalletRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

/// Note of a balance adjustment (`docs/balance-adjustment.md`):
/// `Penyesuaian saldo: Rp X → Rp Y`, formatted in the **wallet's** currency; a
/// user note is appended as ` — <note>`.
String adjustmentNote(
  double from,
  double to, {
  String currency = 'IDR',
  String? userNote,
}) {
  final base =
      'Penyesuaian saldo: ${Fmt.money(from, currency: currency)} → '
      '${Fmt.money(to, currency: currency)}';
  final extra = optionalText(userNote);
  return extra == null ? base : '$base — $extra';
}

/// Rounds a money delta to 2 decimals (kills float noise like 0.30000000000000004).
double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Difference an adjustment to [target] would record against the displayed
/// balance [current], rounded to 2 decimals (0 = nothing to adjust).
double adjustmentDelta(double current, double target) =>
    _round2(target - current);

/// "Sesuaikan saldo" (`docs/balance-adjustment.md`): the user enters the real
/// balance; an `adjustment` transaction with the signed difference against the
/// **displayed** balance (server balance + pending local changes) is recorded.
/// A relative delta is safe offline. Returns the new transaction.
final class AdjustWalletBalance {
  const AdjustWalletBalance(this._wallets, this._tx, this._clock);
  final WalletRepository _wallets;
  final TransactionRepository _tx;
  final Clock _clock;

  /// [note] is appended to the default note. [date] defaults to now.
  Future<Result<Transaction>> call(
    String walletId,
    double targetBalance, {
    String? note,
    DateTime? date,
  }) => guard(() async {
    if (!targetBalance.isFinite) {
      throw const ValidationFailure('Saldo tidak valid', field: 'balance');
    }
    final wallet = await _wallets.getById(walletId);
    if (wallet == null) throw const NotFoundFailure('Dompet tidak ditemukan');
    final delta = adjustmentDelta(wallet.balance, targetBalance);
    if (delta == 0) {
      throw const ValidationFailure(
        'Saldonya sudah sama, nggak ada yang perlu disesuaikan',
        field: 'balance',
      );
    }
    final now = _clock.now();
    final t = Transaction(
      id: newId(),
      walletId: walletId,
      type: TxType.adjustment,
      amount: delta,
      note: adjustmentNote(
        wallet.balance,
        targetBalance,
        currency: wallet.currency,
        userNote: note,
      ),
      date: date ?? now,
      createdAt: now,
      updatedAt: now,
    );
    await _tx.save(t);
    return t;
  });
}
