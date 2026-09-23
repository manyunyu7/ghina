import '../../core/clock.dart';
import '../../core/failure.dart';
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
