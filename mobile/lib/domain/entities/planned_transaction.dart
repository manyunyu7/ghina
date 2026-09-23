import 'enums.dart';

/// A user-entered expectation of a future income/expense (forecast note).
/// Never touches wallet balances until converted to a real transaction.
final class PlannedTransaction {
  const PlannedTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.note,
    this.categoryId,
    this.walletId,
    required this.date,
    required this.done,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// [TxType.expense] or [TxType.income].
  final TxType type;
  final double amount;
  final String? note;
  final String? categoryId;
  final String? walletId;
  final DateTime date;
  final bool done;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlannedTransaction copyWith({bool? done, DateTime? updatedAt}) =>
      PlannedTransaction(
        id: id,
        type: type,
        amount: amount,
        note: note,
        categoryId: categoryId,
        walletId: walletId,
        date: date,
        done: done ?? this.done,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is PlannedTransaction &&
      other.id == id &&
      other.type == type &&
      other.amount == amount &&
      other.note == note &&
      other.categoryId == categoryId &&
      other.walletId == walletId &&
      other.date == date &&
      other.done == done &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amount,
    note,
    categoryId,
    walletId,
    date,
    done,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'PlannedTransaction($id, ${type.wire} $amount, done: $done)';
}
