import 'enums.dart';

/// A wallet / account holding money.
final class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.syncedBalance,
    required this.currency,
    required this.color,
    required this.icon,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final WalletType type;

  /// Balance to display: last server balance + effects of pending (unsynced) transactions.
  final double balance;

  /// Last balance received from the server (or the initial balance of an unsynced wallet).
  final double syncedBalance;

  final String currency;

  /// `#rrggbb`
  final String color;

  /// Icon name (lucide-style id, e.g. `wallet`, `cash`, `bank`).
  final String icon;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when some of this wallet's balance change hasn't reached the server yet.
  bool get hasPendingChanges => balance != syncedBalance;

  Wallet copyWith({
    String? name,
    WalletType? type,
    double? balance,
    double? syncedBalance,
    String? currency,
    String? color,
    String? icon,
    bool? archived,
    DateTime? updatedAt,
  }) => Wallet(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    balance: balance ?? this.balance,
    syncedBalance: syncedBalance ?? this.syncedBalance,
    currency: currency ?? this.currency,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Wallet &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.balance == balance &&
      other.syncedBalance == syncedBalance &&
      other.currency == currency &&
      other.color == color &&
      other.icon == icon &&
      other.archived == archived &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    balance,
    syncedBalance,
    currency,
    color,
    icon,
    archived,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Wallet($id, $name, balance: $balance)';
}
