import 'enums.dart';

/// A transaction category. Named `TxCategory` to avoid clashing with Flutter's
/// `Category` annotation exported by `package:flutter/foundation.dart`.
final class TxCategory {
  const TxCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.icon,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String color;
  final String icon;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is TxCategory &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.color == color &&
      other.icon == icon &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, name, type, color, icon, createdAt, updatedAt);

  @override
  String toString() => 'TxCategory($id, $name, ${type.wire})';
}
