import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'subscription_usecases.dart' show firstActiveWalletId;
import 'validation.dart';

final class PlannedInput {
  const PlannedInput({
    this.type = TxType.expense,
    required this.amount,
    this.note,
    required this.date,
    this.categoryId,
    this.walletId,
  });

  /// [TxType.expense] or [TxType.income].
  final TxType type;
  final double amount;
  final String? note;
  final DateTime date;
  final String? categoryId;
  final String? walletId;
}

Future<PlannedTransaction> _build(
  String id,
  PlannedInput i,
  bool done,
  DateTime createdAt,
  DateTime now,
  WalletRepository wallets,
  CategoryRepository categories,
) async {
  if (i.type == TxType.transfer) {
    throw const ValidationFailure(
      'Rencana hanya bisa pemasukan atau pengeluaran',
      field: 'type',
    );
  }
  final categoryId = optionalId(i.categoryId);
  final walletId = optionalId(i.walletId);
  if (categoryId != null && await categories.getById(categoryId) == null) {
    throw const NotFoundFailure('Kategori tidak ditemukan');
  }
  if (walletId != null && await wallets.getById(walletId) == null) {
    throw const NotFoundFailure('Dompet tidak ditemukan');
  }
  return PlannedTransaction(
    id: id,
    type: i.type,
    amount: requirePositiveAmount(i.amount),
    note: optionalText(i.note, max: 200),
    categoryId: categoryId,
    walletId: walletId,
    date: i.date,
    done: done,
    createdAt: createdAt,
    updatedAt: now,
  );
}

final class WatchPlanned {
  const WatchPlanned(this._repo);
  final PlannedRepository _repo;

  Stream<PlannedTransaction?> call(String id) => _repo.watchById(id);
}

final class CreatePlanned {
  const CreatePlanned(this._repo, this._wallets, this._categories, this._clock);
  final PlannedRepository _repo;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<PlannedTransaction>> call(PlannedInput input) =>
      guard(() async {
        final now = _clock.now();
        final p = await _build(
          newId(),
          input,
          false,
          now,
          now,
          _wallets,
          _categories,
        );
        await _repo.save(p);
        return p;
      });
}

final class UpdatePlanned {
  const UpdatePlanned(this._repo, this._wallets, this._categories, this._clock);
  final PlannedRepository _repo;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<PlannedTransaction>> call(String id, PlannedInput input) =>
      guard(() async {
        final e = await _repo.getById(id);
        if (e == null) throw const NotFoundFailure('Rencana tidak ditemukan');
        final p = await _build(
          id,
          input,
          e.done,
          e.createdAt,
          _clock.now(),
          _wallets,
          _categories,
        );
        await _repo.save(p);
        return p;
      });
}

final class DeletePlanned {
  const DeletePlanned(this._repo);
  final PlannedRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

/// Ticks a planned item off (or back on). Returns the new `done` value.
final class TogglePlannedDone {
  const TogglePlannedDone(this._repo, this._clock);
  final PlannedRepository _repo;
  final Clock _clock;

  Future<Result<bool>> call(String id) => guard(() async {
    final e = await _repo.getById(id);
    if (e == null) throw const NotFoundFailure('Rencana tidak ditemukan');
    await _repo.save(e.copyWith(done: !e.done, updatedAt: _clock.now()));
    return !e.done;
  });
}

/// Turns a planned item into a real transaction (web `convertPlanned`): creates the
/// transaction on the item's wallet (else the first wallet) at the planned date and
/// deletes the plan. Atomic.
final class ConvertPlanned {
  const ConvertPlanned(
    this._repo,
    this._tx,
    this._wallets,
    this._uow,
    this._clock,
  );
  final PlannedRepository _repo;
  final TransactionRepository _tx;
  final WalletRepository _wallets;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<Transaction>> call(String id) => guard(
    () => _uow.run(() async {
      final item = await _repo.getById(id);
      if (item == null) throw const NotFoundFailure('Rencana tidak ditemukan');
      var walletId = item.walletId;
      if (walletId != null && await _wallets.getById(walletId) == null) {
        walletId = null;
      }
      walletId ??= await firstActiveWalletId(_wallets);
      if (walletId == null) {
        throw const ValidationFailure(
          'Buat dompet dulu, atau pilih dompet untuk rencana ini.',
          field: 'walletId',
        );
      }
      final now = _clock.now();
      final t = Transaction(
        id: newId(),
        walletId: walletId,
        categoryId: item.categoryId,
        type: item.type,
        amount: item.amount,
        note: item.note,
        date: item.date,
        createdAt: now,
        updatedAt: now,
      );
      await _tx.save(t);
      await _repo.delete(item.id);
      return t;
    }),
  );
}
