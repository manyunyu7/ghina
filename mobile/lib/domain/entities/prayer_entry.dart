import 'enums.dart';

/// One recorded prayer (spec `docs/prayer-quality.md`). A row means "the user
/// recorded something for that prayer that day"; no row = not filled in yet.
/// Unique per ([date], [prayer]).
///
/// Fardhu rows carry a [status] (masjid … excused) and optional rawatib
/// ([qobliyah]/[badiyah]); sunnah rows (dhuha/tahajud/witir) are always
/// [PrayerStatus.done] with an optional [rakaat].
final class PrayerEntry {
  const PrayerEntry({
    required this.id,
    required this.date,
    required this.prayer,
    PrayerStatus? status,
    this.qobliyah = false,
    this.badiyah = false,
    this.rakaat,
    this.prayedAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  }) : status =
           status ??
           (prayer == Prayer.dhuha ||
                   prayer == Prayer.tahajud ||
                   prayer == Prayer.witir
               ? PrayerStatus.done
               : PrayerStatus.ontime);

  final String id;

  /// Local date `YYYY-MM-DD`.
  final String date;
  final Prayer prayer;
  final PrayerStatus status;

  /// Rawatib before (fardhu only, where it exists).
  final bool qobliyah;

  /// Rawatib after (fardhu only, where it exists).
  final bool badiyah;

  /// Sunnah only, optional.
  final int? rakaat;

  /// Optional: when it was prayed.
  final DateTime? prayedAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Fardhu with a prayed status, or any sunnah row.
  bool get isPrayed => prayer.isSunnah || status.isPrayed;

  /// Rawatib ticked on this row (0–2).
  int get rawatibCount => (qobliyah ? 1 : 0) + (badiyah ? 1 : 0);

  PrayerEntry copyWith({
    PrayerStatus? status,
    bool? qobliyah,
    bool? badiyah,
    int? Function()? rakaat,
    DateTime? Function()? prayedAt,
    String? Function()? note,
    DateTime? updatedAt,
  }) => PrayerEntry(
    id: id,
    date: date,
    prayer: prayer,
    status: status ?? this.status,
    qobliyah: qobliyah ?? this.qobliyah,
    badiyah: badiyah ?? this.badiyah,
    rakaat: rakaat == null ? this.rakaat : rakaat(),
    prayedAt: prayedAt == null ? this.prayedAt : prayedAt(),
    note: note == null ? this.note : note(),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is PrayerEntry &&
      other.id == id &&
      other.date == date &&
      other.prayer == prayer &&
      other.status == status &&
      other.qobliyah == qobliyah &&
      other.badiyah == badiyah &&
      other.rakaat == rakaat &&
      other.prayedAt == prayedAt &&
      other.note == note &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    date,
    prayer,
    status,
    qobliyah,
    badiyah,
    rakaat,
    prayedAt,
    note,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'PrayerEntry($date ${prayer.wire} ${status.wire})';
}
