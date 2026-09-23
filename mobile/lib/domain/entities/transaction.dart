import 'enums.dart';

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
  });

  final String id;
  final String walletId;
  final String? toWalletId;
  final String? categoryId;
  final TxType type;

  /// Always positive.
  final double amount;
  final String? note;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTransfer => type == TxType.transfer;

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
      other.updatedAt == updatedAt;

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
  );

  @override
  String toString() =>
      'Transaction($id, ${type.wire} $amount, $walletId→$toWalletId)';
}

/// The ledger rule shared with the server's `src/lib/ledger.ts`.
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
