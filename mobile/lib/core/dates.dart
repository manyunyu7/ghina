/// Pure calendar helpers (local time). Mirrors the web's date-fns usage.
library;

/// Local date → `YYYY-MM-DD` (no timezone shift). Same as the web's `dateKey`.
String dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

final _dateKeyRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isDateKey(String s) => _dateKeyRe.hasMatch(s);

/// `YYYY-MM-DD` → local midnight.
DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime endOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// date-fns `addDays`: calendar days, keeps the wall-clock time (DST safe).
DateTime addDays(DateTime d, int days) => DateTime(
  d.year,
  d.month,
  d.day + days,
  d.hour,
  d.minute,
  d.second,
  d.millisecond,
);

/// date-fns `addWeeks`.
DateTime addWeeks(DateTime d, int weeks) => addDays(d, weeks * 7);

/// date-fns `addMonths`: clamps the day to the target month's length
/// (Jan 31 + 1 month = Feb 28/29).
DateTime addMonths(DateTime d, int months) {
  final targetFirst = DateTime(d.year, d.month + months, 1);
  final dim = daysInMonth(targetFirst.year, targetFirst.month);
  final day = d.day > dim ? dim : d.day;
  return DateTime(
    targetFirst.year,
    targetFirst.month,
    day,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
  );
}

/// date-fns `addYears` (= addMonths × 12, so Feb 29 → Feb 28).
DateTime addYears(DateTime d, int years) => addMonths(d, years * 12);

/// Whole-day difference `a − b` ignoring time of day (web `daysUntil`).
int daysBetween(DateTime a, DateTime b) {
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return da.difference(db).inDays;
}

/// A calendar month. `month` is 1–12.
final class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month) : assert(month >= 1 && month <= 12);

  factory YearMonth.of(DateTime d) => YearMonth(d.year, d.month);

  final int year;
  final int month;

  /// First instant of the month (local).
  DateTime get start => DateTime(year, month, 1);

  /// Last millisecond of the month (local) — web `monthRange().end`.
  DateTime get end => DateTime(year, month + 1, 0, 23, 59, 59, 999);

  YearMonth plus(int months) {
    final d = DateTime(year, month + months, 1);
    return YearMonth(d.year, d.month);
  }

  YearMonth get next => plus(1);
  YearMonth get previous => plus(-1);

  bool contains(DateTime d) => d.year == year && d.month == month;

  @override
  int compareTo(YearMonth other) => year != other.year
      ? year.compareTo(other.year)
      : month.compareTo(other.month);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
