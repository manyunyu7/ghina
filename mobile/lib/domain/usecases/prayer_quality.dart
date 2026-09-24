/// Pure prayer-quality scoring (spec `docs/prayer-quality.md` "Scoring" and
/// "Report"). No I/O: feed it entries and a date range.
library;

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../entities/entities.dart';

/// Max points of one fardhu slot (masjid).
const prayerMaxPoints = 10;

/// Allowed rakaat per daily sunnah: dhuha 2–12 even, tahajud 2–12 even,
/// witir 1–11 odd.
({int min, int max, int step}) rakaatRule(Prayer p) => switch (p) {
  Prayer.witir => (min: 1, max: 11, step: 2),
  _ => (min: 2, max: 12, step: 2),
};

/// Every valid rakaat count for a daily sunnah.
List<int> rakaatOptions(Prayer p) {
  final r = rakaatRule(p);
  return [for (var i = r.min; i <= r.max; i += r.step) i];
}

bool isValidRakaat(Prayer p, int rakaat) {
  if (!p.isSunnah) return false;
  final r = rakaatRule(p);
  return rakaat >= r.min && rakaat <= r.max && (rakaat - r.min) % r.step == 0;
}

/// Max length of a prayer note (web `PRAYER_NOTE_MAX`).
const prayerNoteMax = 500;

/// Real calendar date in `YYYY-MM-DD` form (web `isValidDateKey`).
bool isValidPrayerDateKey(String v) {
  if (!isDateKey(v)) return false;
  final p = v.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

/// Web `prayerEntryError`: an Indonesian message, or null when valid. Same checks
/// as the server, so a row that passes here is never rejected on push.
String? prayerEntryError(PrayerEntry e) {
  if (!isValidPrayerDateKey(e.date)) return 'Tanggal tidak valid';
  final note = e.note;
  if (note != null && note.length > prayerNoteMax) {
    return 'Catatan maksimal $prayerNoteMax karakter';
  }
  final p = e.prayer;
  if (p.isFardhu) {
    if (!PrayerStatus.fardhu.contains(e.status)) return 'Status tidak valid';
    if (e.qobliyah && !p.hasQobliyah) {
      return 'Tidak ada qobliyah untuk ${p.label}';
    }
    if (e.badiyah && !p.hasBadiyah) {
      return "Tidak ada ba'diyah untuk ${p.label}";
    }
    if ((e.qobliyah || e.badiyah) && !e.status.isPrayed) {
      return 'Rawatib hanya untuk shalat yang dikerjakan';
    }
    if (e.rakaat != null) return 'Rakaat hanya untuk shalat sunnah';
    return null;
  }
  if (e.status != PrayerStatus.done) {
    return 'Status shalat sunnah harus "done"';
  }
  if (e.qobliyah || e.badiyah) return 'Rawatib hanya untuk shalat fardhu';
  final r = e.rakaat;
  if (r != null && !isValidRakaat(p, r)) {
    final rule = rakaatRule(p);
    return 'Rakaat ${p.label} harus ${rule.min.isOdd ? 'ganjil' : 'genap'} '
        '${rule.min}–${rule.max}';
  }
  return null;
}

/// Throws a [ValidationFailure] with [prayerEntryError]'s message.
void validatePrayerEntry(PrayerEntry e) {
  final err = prayerEntryError(e);
  if (err != null) throw ValidationFailure(err);
}

// ---------------------------------------------------------------- day level

/// Day state for streaks / complete days (web `dayState`).
enum PrayerDayState {
  /// All 5 fardhu recorded with a prayed status.
  complete,

  /// ≥1 fardhu excused and every other fardhu prayed: neither breaks nor counts.
  neutral,

  /// Anything else.
  broken,
}

/// [fardhu] = the day's rows keyed by prayer (missing = not filled in).
PrayerDayState prayerDayState(Map<Prayer, PrayerEntry>? day) {
  var excused = 0;
  for (final p in Prayer.fardhu) {
    final s = day?[p]?.status;
    if (s == PrayerStatus.excused) {
      excused++;
    } else if (s == null || !s.isPrayed) {
      return PrayerDayState.broken;
    }
  }
  return excused > 0 ? PrayerDayState.neutral : PrayerDayState.complete;
}

/// `YYYY-MM-DD` → prayer → row.
Map<String, Map<Prayer, PrayerEntry>> _index(Iterable<PrayerEntry> entries) {
  final out = <String, Map<Prayer, PrayerEntry>>{};
  for (final e in entries) {
    out.putIfAbsent(e.date, () => {})[e.prayer] = e;
  }
  return out;
}

/// Web `currentStreak`: consecutive complete days ending today (today counts
/// only once complete; an incomplete today doesn't break it). Neutral days are
/// skipped. Looks back at most [maxDays].
int completeDayStreak(
  List<PrayerEntry> entries,
  DateTime today, {
  int maxDays = 400,
}) {
  final idx = _index(entries);
  var k = startOfDay(today);
  var streak = 0;
  if (prayerDayState(idx[dateKey(k)]) != PrayerDayState.complete) {
    k = addDays(k, -1);
  }
  for (var i = 0; i < maxDays; i++, k = addDays(k, -1)) {
    switch (prayerDayState(idx[dateKey(k)])) {
      case PrayerDayState.complete:
        streak++;
      case PrayerDayState.neutral:
        continue;
      case PrayerDayState.broken:
        return streak;
    }
  }
  return streak;
}

/// One fardhu cell of the color map.
final class PrayerCell {
  const PrayerCell(this.prayer, this.entry);

  final Prayer prayer;

  /// Null = not filled in ("Belum diisi").
  final PrayerEntry? entry;

  PrayerStatus? get status => entry?.status;

  /// Rawatib marks (only on a prayed status, where the rawatib exists).
  bool get qobliyah =>
      prayer.hasQobliyah &&
      (entry?.qobliyah ?? false) &&
      (entry?.status.isPrayed ?? false);
  bool get badiyah =>
      prayer.hasBadiyah &&
      (entry?.badiyah ?? false) &&
      (entry?.status.isPrayed ?? false);
}

/// One day (row) of the report's color map.
final class PrayerDay {
  const PrayerDay({
    required this.day,
    required this.cells,
    required this.sunnah,
    required this.isToday,
    required this.isFuture,
  });

  /// Local midnight.
  final DateTime day;

  /// The 5 fardhu in order.
  final List<PrayerCell> cells;

  /// Daily sunnah rows done that day.
  final Map<Prayer, PrayerEntry> sunnah;
  final bool isToday;

  /// After today: shown faded, not counted, not editable.
  final bool isFuture;

  String get key => dateKey(day);
  PrayerCell cell(Prayer p) => cells[Prayer.fardhu.indexOf(p)];

  /// Every row of the day keyed by prayer (fardhu + sunnah).
  Map<Prayer, PrayerEntry> get entries => {
    for (final c in cells) c.prayer: ?c.entry,
    ...sunnah,
  };
  PrayerDayState get state => prayerDayState(entries);
  bool get isComplete => state == PrayerDayState.complete;
}

/// Per-fardhu breakdown (web `PrayerBreakdown`).
final class PrayerBreakdown {
  const PrayerBreakdown({
    required this.prayer,
    required this.counts,
    required this.unfilled,
    required this.counted,
    required this.points,
  });

  final Prayer prayer;

  /// Rows per fardhu status (all 7 keys).
  final Map<PrayerStatus, int> counts;

  /// Counted slots without a row (past days only).
  final int unfilled;

  /// Counted slots for this prayer (excused excluded).
  final int counted;
  final int points;

  int count(PrayerStatus s) => counts[s] ?? 0;

  /// 0–100 rounded; null when nothing counted.
  int? get score =>
      counted > 0 ? (points / (prayerMaxPoints * counted) * 100).round() : null;

  /// Late + missed ("bad").
  int get lateOrMissed => count(PrayerStatus.late) + count(PrayerStatus.missed);
  int get congregation =>
      count(PrayerStatus.masjid) + count(PrayerStatus.jamaah);
}

double _round1(double n) => (n * 10).roundToDouble() / 10;

/// Web `QualityReport`: everything the report screen shows for a range.
final class PrayerReport {
  const PrayerReport({
    required this.from,
    required this.to,
    required this.days,
    required this.daysElapsed,
    required this.counted,
    required this.points,
    required this.counts,
    required this.unfilled,
    required this.completeDays,
    required this.neutralDays,
    required this.rawatibQobliyah,
    required this.rawatibBadiyah,
    required this.sunnahCounts,
    required this.breakdown,
    required this.weakest,
    required this.strongest,
  });

  /// Range (local midnights, inclusive; [to] may be after today).
  final DateTime from;
  final DateTime to;

  /// Color-map rows for the whole range, newest first (future days flagged).
  final List<PrayerDay> days;

  /// Days in range up to today.
  final int daysElapsed;

  /// (day, fardhu) slots counted in the score — excused excluded.
  final int counted;
  final int points;

  /// Rows per fardhu status (all 7 keys; excused included).
  final Map<PrayerStatus, int> counts;

  /// Counted slots without a row ("Belum diisi").
  final int unfilled;
  final int completeDays;
  final int neutralDays;
  final int rawatibQobliyah;
  final int rawatibBadiyah;

  /// Rows per daily sunnah (all 3 keys), up to today.
  final Map<Prayer, int> sunnahCounts;

  /// The 5 fardhu in order.
  final List<PrayerBreakdown> breakdown;
  final Prayer? weakest;
  final Prayer? strongest;

  int count(PrayerStatus s) => counts[s] ?? 0;
  int get rawatibCount => rawatibQobliyah + rawatibBadiyah;

  /// Quality score 0–100 rounded (null when nothing counted).
  int? get score =>
      counted > 0 ? (points / (prayerMaxPoints * counted) * 100).round() : null;

  double _pctOf(int n) => counted > 0 ? _round1(n / counted * 100) : 0;

  /// Percent (1 decimal) of counted slots with status [s]; excused → 0 (it's
  /// not part of the counted slots, show its raw count instead).
  double pct(PrayerStatus s) =>
      s == PrayerStatus.excused ? 0 : _pctOf(count(s));

  /// "Jamaah %" = masjid + jamaah.
  double get jamaahPct =>
      _pctOf(count(PrayerStatus.masjid) + count(PrayerStatus.jamaah));
  double get unfilledPct => _pctOf(unfilled);

  PrayerBreakdown breakdownOf(Prayer p) => breakdown[Prayer.fardhu.indexOf(p)];
}

/// Web `weakestStrongest`. Weakest = most (late + missed); ties → lower score,
/// then fardhu order. Strongest = highest score; ties → fewer (late + missed),
/// then fardhu order. Only prayers with counted slots take part; both null
/// when fewer than 2 take part or all have the same score and (late + missed);
/// weakest is null when it's the strongest.
({Prayer? weakest, Prayer? strongest}) weakestStrongest(
  List<PrayerBreakdown> perPrayer,
) {
  final cand = perPrayer
      .where((b) => b.counted > 0 && b.score != null)
      .toList();
  if (cand.length < 2) return (weakest: null, strongest: null);
  int order(PrayerBreakdown b) => Prayer.fardhu.indexOf(b.prayer);
  final weak = [...cand]
    ..sort((a, b) {
      final c1 = b.lateOrMissed.compareTo(a.lateOrMissed);
      if (c1 != 0) return c1;
      final c2 = a.score!.compareTo(b.score!);
      if (c2 != 0) return c2;
      return order(a).compareTo(order(b));
    });
  final strong = [...cand]
    ..sort((a, b) {
      final c1 = b.score!.compareTo(a.score!);
      if (c1 != 0) return c1;
      final c2 = a.lateOrMissed.compareTo(b.lateOrMissed);
      if (c2 != 0) return c2;
      return order(a).compareTo(order(b));
    });
  final first = cand.first;
  final allSame = cand.every(
    (b) => b.score == first.score && b.lateOrMissed == first.lateOrMissed,
  );
  if (allSame) return (weakest: null, strongest: null);
  final w = weak.first.prayer, s = strong.first.prayer;
  return (weakest: w == s ? null : w, strongest: s);
}

/// Web `computeReport` for [from]..[to] (inclusive local days) evaluated on
/// [today]. Counted slots = every (day, fardhu) up to today except excused;
/// unrecorded past slots count as 0 (unfilled); for today only recorded slots
/// count. Days after today are listed (faded) but not counted.
PrayerReport buildPrayerReport(
  List<PrayerEntry> entries, {
  required DateTime from,
  required DateTime to,
  required DateTime today,
}) {
  final idx = _index(entries);
  final t = startOfDay(today);
  final start = startOfDay(from);
  final end = startOfDay(to);

  final counts = {for (final s in PrayerStatus.fardhu) s: 0};
  final sunnah = {for (final p in Prayer.sunnah) p: 0};
  final perCounts = {
    for (final p in Prayer.fardhu)
      p: {for (final s in PrayerStatus.fardhu) s: 0},
  };
  final perUnfilled = {for (final p in Prayer.fardhu) p: 0};
  final perCounted = {for (final p in Prayer.fardhu) p: 0};
  final perPoints = {for (final p in Prayer.fardhu) p: 0};
  var unfilled = 0, counted = 0, points = 0, elapsed = 0;
  var complete = 0, neutral = 0, qob = 0, bad = 0;
  final rows = <PrayerDay>[];

  for (var d = end; !d.isBefore(start); d = addDays(d, -1)) {
    final day = idx[dateKey(d)] ?? const <Prayer, PrayerEntry>{};
    final future = d.isAfter(t);
    final isToday = isSameDay(d, t);
    rows.add(
      PrayerDay(
        day: d,
        cells: [for (final p in Prayer.fardhu) PrayerCell(p, day[p])],
        sunnah: {for (final p in Prayer.sunnah) p: ?day[p]},
        isToday: isToday,
        isFuture: future,
      ),
    );
    if (future) continue;
    elapsed++;
    for (final p in Prayer.fardhu) {
      final e = day[p];
      if (e == null) {
        if (isToday) continue;
        unfilled++;
        perUnfilled[p] = perUnfilled[p]! + 1;
        counted++;
        perCounted[p] = perCounted[p]! + 1;
        continue;
      }
      final s = PrayerStatus.fardhu.contains(e.status)
          ? e.status
          : PrayerStatus.ontime;
      counts[s] = counts[s]! + 1;
      perCounts[p]![s] = perCounts[p]![s]! + 1;
      if (s == PrayerStatus.excused) continue;
      final pts = s.points ?? 0;
      counted++;
      points += pts;
      perCounted[p] = perCounted[p]! + 1;
      perPoints[p] = perPoints[p]! + pts;
      if (s.isPrayed) {
        if (e.qobliyah && p.hasQobliyah) qob++;
        if (e.badiyah && p.hasBadiyah) bad++;
      }
    }
    for (final p in Prayer.sunnah) {
      if (day.containsKey(p)) sunnah[p] = sunnah[p]! + 1;
    }
    switch (prayerDayState(day)) {
      case PrayerDayState.complete:
        complete++;
      case PrayerDayState.neutral:
        neutral++;
      case PrayerDayState.broken:
        break;
    }
  }

  final breakdown = [
    for (final p in Prayer.fardhu)
      PrayerBreakdown(
        prayer: p,
        counts: perCounts[p]!,
        unfilled: perUnfilled[p]!,
        counted: perCounted[p]!,
        points: perPoints[p]!,
      ),
  ];
  final ws = weakestStrongest(breakdown);
  return PrayerReport(
    from: start,
    to: end,
    days: rows,
    daysElapsed: elapsed,
    counted: counted,
    points: points,
    counts: counts,
    unfilled: unfilled,
    completeDays: complete,
    neutralDays: neutral,
    rawatibQobliyah: qob,
    rawatibBadiyah: bad,
    sunnahCounts: sunnah,
    breakdown: breakdown,
    weakest: ws.weakest,
    strongest: ws.strongest,
  );
}

// ---------------------------------------------------------------- ranges

/// Longest custom range (days).
const prayerReportMaxDays = 366;

/// Report range presets (spec "Report" → Range).
enum PrayerRangePreset {
  last7Days('7 hari'),
  thisMonth('Bulan ini'),
  lastMonth('Bulan lalu'),
  last3Months('3 bulan'),
  custom('Pilih tanggal');

  const PrayerRangePreset(this.label);
  final String label;

  /// Inclusive local-day range for [today]: 7 hari = today−6 … today; Bulan ini
  /// = the whole month (future days aren't counted); Bulan lalu = the whole
  /// previous month; 3 bulan = today−89 … today. [custom] falls back to 7 hari
  /// (use [customPrayerRange]).
  ({DateTime from, DateTime to}) resolve(DateTime today) {
    final t = startOfDay(today);
    return switch (this) {
      PrayerRangePreset.last7Days ||
      PrayerRangePreset.custom => (from: addDays(t, -6), to: t),
      PrayerRangePreset.thisMonth => (
        from: DateTime(t.year, t.month),
        to: DateTime(t.year, t.month + 1, 0),
      ),
      PrayerRangePreset.lastMonth => (
        from: DateTime(t.year, t.month - 1),
        to: DateTime(t.year, t.month, 0),
      ),
      PrayerRangePreset.last3Months => (from: addDays(t, -89), to: t),
    };
  }
}

/// Custom range: reversed dates are swapped; longer than
/// [prayerReportMaxDays] is clamped to the days ending at `to`.
({DateTime from, DateTime to}) customPrayerRange(DateTime a, DateTime b) {
  var from = startOfDay(a), to = startOfDay(b);
  if (from.isAfter(to)) (from, to) = (to, from);
  final min = addDays(to, -(prayerReportMaxDays - 1));
  if (from.isBefore(min)) from = min;
  return (from: from, to: to);
}
