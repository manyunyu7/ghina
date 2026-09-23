import '../../core/dates.dart';

/// Monthly spending limit for one expense category. Unique per (category, month, year).
final class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.month,
    required this.year,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String categoryId;
  final double amount;

  /// 1–12
  final int month;
  final int year;
  final DateTime createdAt;
  final DateTime updatedAt;

  YearMonth get period => YearMonth(year, month);

  @override
  bool operator ==(Object other) =>
      other is Budget &&
      other.id == id &&
      other.categoryId == categoryId &&
      other.amount == amount &&
      other.month == month &&
      other.year == year &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, categoryId, amount, month, year, createdAt, updatedAt);

  @override
  String toString() => 'Budget($id, $categoryId $year-$month: $amount)';
}
