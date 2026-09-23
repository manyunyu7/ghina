/// A calendar day in the user's local time zone, independent of DST.
///
/// Internally stored as days since the Unix epoch computed from a UTC date with
/// the same year/month/day, so day arithmetic never drifts across DST changes.
class GameDate implements Comparable<GameDate> {
  const GameDate._(this.epochDay);

  factory GameDate(int year, int month, int day) => GameDate._(
    DateTime.utc(year, month, day).millisecondsSinceEpoch ~/ _msPerDay,
  );

  /// The local calendar day of [dateTime]. UTC instants are converted to the
  /// device's local time first; local DateTimes are taken as-is.
  factory GameDate.fromDateTime(DateTime dateTime) {
    final local = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    return GameDate(local.year, local.month, local.day);
  }

  /// Parses `YYYY-MM-DD` (e.g. `PrayerEntry.date`). Returns null if invalid.
  static GameDate? tryParse(String key) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!),
        mo = int.parse(m.group(2)!),
        d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final date = GameDate(y, mo, d);
    // Reject overflowing dates like 2024-02-31.
    if (date.month != mo || date.day != d) return null;
    return date;
  }

  static const _msPerDay = Duration.millisecondsPerDay;

  /// Days since 1970-01-01.
  final int epochDay;

  DateTime get _utc =>
      DateTime.fromMillisecondsSinceEpoch(epochDay * _msPerDay, isUtc: true);

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;

  /// 1 = Monday … 7 = Sunday.
  int get weekday => _utc.weekday;

  /// Local midnight at the start of this day.
  DateTime toLocalDateTime() => DateTime(year, month, day);

  GameDate addDays(int days) => GameDate._(epochDay + days);

  /// Whole days from [other] to this (positive if this is later).
  int difference(GameDate other) => epochDay - other.epochDay;

  bool isBefore(GameDate other) => epochDay < other.epochDay;
  bool isAfter(GameDate other) => epochDay > other.epochDay;

  /// Same calendar month (year + month).
  bool isSameMonth(GameDate other) =>
      year == other.year && month == other.month;

  /// `YYYY-MM-DD`.
  String toKey() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(GameDate other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      other is GameDate && other.epochDay == epochDay;

  @override
  int get hashCode => epochDay.hashCode;

  @override
  String toString() => toKey();
}

/// A calendar month.
class GameMonth implements Comparable<GameMonth> {
  const GameMonth(this.year, this.month);

  factory GameMonth.of(GameDate date) => GameMonth(date.year, date.month);

  final int year;
  final int month;

  GameDate get firstDay => GameDate(year, month, 1);
  GameDate get lastDay => GameDate(year, month + 1, 1).addDays(-1);
  int get dayCount => lastDay.day;

  GameMonth get next =>
      month == 12 ? GameMonth(year + 1, 1) : GameMonth(year, month + 1);
  GameMonth get previous =>
      month == 1 ? GameMonth(year - 1, 12) : GameMonth(year, month - 1);

  bool contains(GameDate d) => d.year == year && d.month == month;

  @override
  int compareTo(GameMonth other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  @override
  bool operator ==(Object other) =>
      other is GameMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
