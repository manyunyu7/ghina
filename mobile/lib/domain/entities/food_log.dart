import 'enums.dart';

/// A logged meal/food item.
final class FoodLog {
  const FoodLog({
    required this.id,
    required this.date,
    required this.name,
    this.meal,
    this.calories,
    this.photoUrl,
    this.localPhotoPath,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime date;
  final String name;
  final MealType? meal;
  final int? calories;

  /// Server path such as `/uploads/abc.jpg` (resolve with `AppConfig.resolveUrl`).
  final String? photoUrl;

  /// Local file of a photo taken offline and not uploaded yet. Prefer it over
  /// [photoUrl] for display when non-null.
  final String? localPhotoPath;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasPhoto => photoUrl != null || localPhotoPath != null;

  @override
  bool operator ==(Object other) =>
      other is FoodLog &&
      other.id == id &&
      other.date == date &&
      other.name == name &&
      other.meal == meal &&
      other.calories == calories &&
      other.photoUrl == photoUrl &&
      other.localPhotoPath == localPhotoPath &&
      other.note == note &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    date,
    name,
    meal,
    calories,
    photoUrl,
    localPhotoPath,
    note,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'FoodLog($id, $name)';
}
