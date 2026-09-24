import 'enums.dart';
import 'transaction_photo.dart';

/// A money movement. Transfers move [amount] from [walletId] to [toWalletId].
final class Transaction {
  const Transaction({
    required this.id,
    required this.walletId,
    this.toWalletId,
    this.categoryId,
    required this.type,
    required this.amount,
    this.note,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.photos = const [],
  });

  final String id;
  final String walletId;
  final String? toWalletId;
  final String? categoryId;
  final TxType type;

  /// Positive, except for [TxType.adjustment] where it is signed and non-zero
  /// (new balance − old balance).
  final double amount;
  final String? note;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Receipts/proofs, display order, at most [maxTransactionPhotos]. Pending
  /// (offline) photos have `isPending` and upload on the next sync.
  final List<TransactionPhoto> photos;

  bool get hasPhotos => photos.isNotEmpty;

  /// Copy with other [photos] (and [updatedAt]).
  Transaction withPhotos(
    List<TransactionPhoto> photos, {
    DateTime? updatedAt,
  }) => Transaction(
    id: id,
    walletId: walletId,
    toWalletId: toWalletId,
    categoryId: categoryId,
    type: type,
    amount: amount,
    note: note,
    date: date,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    photos: List.unmodifiable(photos),
  );

  bool get isTransfer => type == TxType.transfer;
  bool get isAdjustment => type == TxType.adjustment;

  /// Counts as income or expense (reports, budgets, dashboards, gamification).
  bool get isIncomeOrExpense => type == TxType.income || type == TxType.expense;

  /// Net effect on wallet balances, keyed by wallet id (contract "Wallet balances"):
  /// income `+amount` to wallet; expense `−amount`; transfer `−amount` from source and
  /// `+amount` to destination.
  Map<String, double> get balanceEffects => ledgerEffects(
    type: type,
    amount: amount,
    walletId: walletId,
    toWalletId: toWalletId,
  );

  @override
  bool operator ==(Object other) =>
      other is Transaction &&
      other.id == id &&
      other.walletId == walletId &&
      other.toWalletId == toWalletId &&
      other.categoryId == categoryId &&
      other.type == type &&
      other.amount == amount &&
      other.note == note &&
      other.date == date &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      _photosEq(other.photos, photos);

  static bool _photosEq(List<TransactionPhoto> a, List<TransactionPhoto> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    walletId,
    toWalletId,
    categoryId,
    type,
    amount,
    note,
    date,
    createdAt,
    updatedAt,
    Object.hashAll(photos),
  );

  @override
  String toString() =>
      'Transaction($id, ${type.wire} $amount, $walletId→$toWalletId)';
}

/// The ledger rule shared with the server's `src/lib/ledger.ts`: income
/// `+amount`, expense `−amount`, transfer `−amount`/`+amount`, adjustment
/// `+amount` (signed) to [walletId].
Map<String, double> ledgerEffects({
  required TxType type,
  required double amount,
  required String walletId,
  String? toWalletId,
}) {
  final e = <String, double>{};
  void add(String id, double d) => e[id] = (e[id] ?? 0) + d;
  switch (type) {
    case TxType.income:
      add(walletId, amount);
    case TxType.expense:
      add(walletId, -amount);
    case TxType.transfer:
      if (toWalletId != null) {
        add(walletId, -amount);
        add(toWalletId, amount);
      }
    case TxType.adjustment:
      add(walletId, amount);
  }
  return e;
}

/// Sums per-wallet delta maps.
Map<String, double> mergeEffects(Iterable<Map<String, double>> maps) {
  final out = <String, double>{};
  for (final m in maps) {
    m.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
  }
  return out;
}

/// `after − before` per wallet: what changing a transaction from [before] to [after]
/// does to balances (either may be null for create/delete).
Map<String, double> effectDelta(Transaction? before, Transaction? after) {
  final neg = (before?.balanceEffects ?? const {}).map(
    (k, v) => MapEntry(k, -v),
  );
  return mergeEffects([neg, after?.balanceEffects ?? const {}]);
}
