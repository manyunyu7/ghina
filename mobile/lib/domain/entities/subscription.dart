import '../../core/dates.dart';
import 'enums.dart';

/// A recurring subscription (tracking only — paying it creates a transaction).
final class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.currency,
    required this.cycle,
    required this.nextBilling,
    this.categoryId,
    this.walletId,
    required this.color,
    required this.icon,
    this.note,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final double amount;
  final String currency;
  final BillingCycle cycle;

  /// Billing anchor. May lie in the past; use [nextOccurrence] for display.
  final DateTime nextBilling;
  final String? categoryId;

  /// Payment wallet.
  final String? walletId;
  final String color;
  final String icon;
  final String? note;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get monthlyAmount => cycle.monthlyAmount(amount);
  double get yearlyAmount => cycle.yearlyAmount(amount);

  /// The anchor rolled forward to the first occurrence on/after the start of [from]'s day
  /// (web `nextOccurrence`).
  DateTime nextOccurrence(DateTime from) =>
      nextBillingOccurrence(nextBilling, cycle, from);

  /// Days from [from] until [nextOccurrence] (0 = today).
  int daysUntilNext(DateTime from) => daysBetween(nextOccurrence(from), from);

  Subscription copyWith({
    DateTime? nextBilling,
    bool? active,
    DateTime? updatedAt,
  }) => Subscription(
    id: id,
    name: name,
    amount: amount,
    currency: currency,
    cycle: cycle,
    nextBilling: nextBilling ?? this.nextBilling,
    categoryId: categoryId,
    walletId: walletId,
    color: color,
    icon: icon,
    note: note,
    active: active ?? this.active,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Subscription &&
      other.id == id &&
      other.name == name &&
      other.amount == amount &&
      other.currency == currency &&
      other.cycle == cycle &&
      other.nextBilling == nextBilling &&
      other.categoryId == categoryId &&
      other.walletId == walletId &&
      other.color == color &&
      other.icon == icon &&
      other.note == note &&
      other.active == active &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    amount,
    currency,
    cycle,
    nextBilling,
    categoryId,
    walletId,
    color,
    icon,
    note,
    active,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Subscription($id, $name, $amount ${cycle.wire})';
}

/// Web `nextOccurrence(anchor, cycle, from)`: roll [anchor] forward by whole cycles
/// until it is on/after local midnight of [from].
DateTime nextBillingOccurrence(
  DateTime anchor,
  BillingCycle cycle,
  DateTime from,
) {
  var d = anchor;
  final start = DateTime(from.year, from.month, from.day);
  var guard = 0;
  while (d.isBefore(start) && guard < 1000) {
    d = cycle.advance(d);
    guard++;
  }
  return d;
}
