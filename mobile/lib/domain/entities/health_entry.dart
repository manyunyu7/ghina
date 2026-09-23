/// A health measurement: weight and/or blood pressure (+ pulse).
final class HealthEntry {
  const HealthEntry({
    required this.id,
    required this.date,
    this.weight,
    this.systolic,
    this.diastolic,
    this.pulse,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime date;

  /// kg
  final double? weight;

  /// mmHg
  final int? systolic;

  /// mmHg
  final int? diastolic;

  /// bpm
  final int? pulse;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// AHA category of this reading, or null without blood pressure.
  BpCategory? get bpCategory => classifyBp(systolic, diastolic);

  @override
  bool operator ==(Object other) =>
      other is HealthEntry &&
      other.id == id &&
      other.date == date &&
      other.weight == weight &&
      other.systolic == systolic &&
      other.diastolic == diastolic &&
      other.pulse == pulse &&
      other.note == note &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    date,
    weight,
    systolic,
    diastolic,
    pulse,
    note,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'HealthEntry($id, $date, w: $weight, bp: $systolic/$diastolic)';
}

enum BpLevel { normal, elevated, stage1, stage2, crisis }

/// Blood-pressure category (port of the web's `health/bp.ts`).
final class BpCategory {
  const BpCategory(this.level, this.label, this.color);

  final BpLevel level;

  /// Indonesian label.
  final String label;

  /// ARGB color, e.g. `0xFF16A34A`.
  final int color;
}

/// Classify blood pressure using the common AHA categories.
BpCategory? classifyBp(int? systolic, int? diastolic) {
  if (systolic == null || diastolic == null) return null;
  if (systolic >= 180 || diastolic >= 120) {
    return const BpCategory(BpLevel.crisis, 'Krisis hipertensi', 0xFFDC2626);
  }
  if (systolic >= 140 || diastolic >= 90) {
    return const BpCategory(BpLevel.stage2, 'Tinggi · Tahap 2', 0xFFEF4444);
  }
  if (systolic >= 130 || diastolic >= 80) {
    return const BpCategory(BpLevel.stage1, 'Tinggi · Tahap 1', 0xFFF59E0B);
  }
  if (systolic >= 120) {
    return const BpCategory(BpLevel.elevated, 'Meningkat', 0xFFF59E0B);
  }
  return const BpCategory(BpLevel.normal, 'Normal', 0xFF16A34A);
}
