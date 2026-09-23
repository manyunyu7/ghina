import 'enums.dart';

/// A performed prayer. Existence of the row = done. Unique per ([date], [prayer]).
final class PrayerEntry {
  const PrayerEntry({
    required this.id,
    required this.date,
    required this.prayer,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Local date `YYYY-MM-DD`.
  final String date;
  final Prayer prayer;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is PrayerEntry &&
      other.id == id &&
      other.date == date &&
      other.prayer == prayer &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, date, prayer, createdAt, updatedAt);

  @override
  String toString() => 'PrayerEntry($date ${prayer.wire})';
}
