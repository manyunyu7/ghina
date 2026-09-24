import 'game_date.dart';

/// What kind of logged activity an [ActivityEvent] is.
enum ActivityKind { transaction, prayer, health, food, lesson }

/// Transaction type, mirrors `Transaction.type` (expense | income | transfer).
/// Balance adjustments are not activity: the data seam never maps them to
/// events (they don't earn XP, streak or daily goal progress).
enum TxKind {
  expense,
  income,
  transfer;

  static TxKind parse(String value) => switch (value) {
    'income' => TxKind.income,
    'transfer' => TxKind.transfer,
    _ => TxKind.expense,
  };
}

/// The five daily (fardhu) prayers, mirrors `PrayerEntry.prayer`.
const prayerNames = ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya'];

/// The daily sunnah prayers tracked alongside the fardhu.
const sunnahPrayerNames = ['dhuha', 'tahajud', 'witir'];

/// Fardhu statuses that count as prayed (spec `docs/prayer-quality.md`).
const prayedStatuses = {'masjid', 'jamaah', 'ontime', 'late', 'qadha'};

/// Rawatib muakkad slots per day (subuh q, dzuhur q+b, maghrib b, isya b).
const rawatibSlotsPerDay = 5;

/// One piece of synced user activity, the engine's only view of the data layer.
///
/// [at] is when the entry was *logged* (`createdAt`) — XP, the daily goal and the
/// streak are counted on that local day, so backfilling old entries can't farm
/// XP for past days. [occurredAt] is the domain date (transaction `date`, health
/// `date`, …) used for monthly stats like the savings rate.
class ActivityEvent {
  const ActivityEvent({
    required this.kind,
    required this.at,
    this.id,
    this.dayOverride,
    this.occurredAt,
    this.txKind,
    this.amount,
    this.prayer,
    this.prayerStatus,
    this.qobliyah = false,
    this.badiyah = false,
    this.hasWeight = false,
  });

  /// A transaction. [createdAt] drives streak/XP; [date] drives monthly stats.
  factory ActivityEvent.transaction({
    String? id,
    required DateTime createdAt,
    TxKind type = TxKind.expense,
    double amount = 0,
    DateTime? date,
  }) => ActivityEvent(
    kind: ActivityKind.transaction,
    id: id,
    at: createdAt,
    occurredAt: date,
    txKind: type,
    amount: amount,
  );

  /// A prayer entry. Counted on its own [date] (`YYYY-MM-DD` local date).
  /// [status] is the fardhu status (`masjid … excused`; null → `ontime`, the
  /// server default); sunnah rows are `done`. [qobliyah]/[badiyah] = rawatib.
  factory ActivityEvent.prayer({
    String? id,
    required GameDate date,
    required String prayer,
    String? status,
    bool qobliyah = false,
    bool badiyah = false,
    DateTime? createdAt,
  }) => ActivityEvent(
    kind: ActivityKind.prayer,
    id: id,
    at: createdAt ?? date.toLocalDateTime(),
    dayOverride: date,
    prayer: prayer.toLowerCase(),
    prayerStatus:
        status?.toLowerCase() ??
        (sunnahPrayerNames.contains(prayer.toLowerCase()) ? 'done' : 'ontime'),
    qobliyah: qobliyah,
    badiyah: badiyah,
  );

  /// A health entry (weight / blood pressure).
  factory ActivityEvent.health({
    String? id,
    required DateTime createdAt,
    DateTime? date,
    bool hasWeight = false,
  }) => ActivityEvent(
    kind: ActivityKind.health,
    id: id,
    at: createdAt,
    occurredAt: date,
    hasWeight: hasWeight,
  );

  /// A food log entry.
  factory ActivityEvent.food({
    String? id,
    required DateTime createdAt,
    DateTime? date,
  }) => ActivityEvent(
    kind: ActivityKind.food,
    id: id,
    at: createdAt,
    occurredAt: date,
  );

  final ActivityKind kind;

  /// When it was logged (local or UTC; converted to the local day).
  final DateTime at;
  final String? id;

  /// Forces the day this event counts on (used for prayers).
  final GameDate? dayOverride;

  /// Domain date of the entry (transaction/health/food `date`).
  final DateTime? occurredAt;
  final TxKind? txKind;
  final double? amount;

  /// Prayer name (see [prayerNames] / [sunnahPrayerNames]).
  final String? prayer;

  /// Prayer status (`masjid|jamaah|ontime|late|qadha|missed|excused|done`).
  final String? prayerStatus;

  /// Rawatib ticked on a fardhu row.
  final bool qobliyah;
  final bool badiyah;

  bool get isFardhu => prayer != null && prayerNames.contains(prayer);
  bool get isSunnah => prayer != null && sunnahPrayerNames.contains(prayer);

  /// Fardhu with a prayed status.
  bool get isPrayedFardhu => isFardhu && prayedStatuses.contains(prayerStatus);
  int get rawatibCount => (qobliyah ? 1 : 0) + (badiyah ? 1 : 0);

  /// Health entry includes a weight measurement.
  final bool hasWeight;

  /// Local day the activity counts for (XP, streak, daily goal).
  GameDate get day => dayOverride ?? GameDate.fromDateTime(at);

  /// Local day of the domain date (falls back to [day]).
  GameDate get occurredDay =>
      occurredAt == null ? day : GameDate.fromDateTime(occurredAt!);
}

/// Budget vs actual spending of one category in one month (`Budget` row + sum of
/// that category's expenses in that month).
class BudgetStatus {
  const BudgetStatus({
    required this.categoryId,
    required this.year,
    required this.month,
    required this.budget,
    required this.spent,
    this.categoryName,
  });

  final String categoryId;
  final String? categoryName;
  final int year;

  /// 1–12.
  final int month;
  final double budget;
  final double spent;

  bool get isOver => spent > budget;

  /// spent / budget (0 when budget is 0 and nothing spent).
  double get ratio =>
      budget <= 0 ? (spent > 0 ? double.infinity : 0) : spent / budget;

  bool isIn(int y, int m) => year == y && month == m;
}
