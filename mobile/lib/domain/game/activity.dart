import 'game_date.dart';

/// What kind of logged activity an [ActivityEvent] is.
enum ActivityKind { transaction, prayer, health, food, lesson }

/// Transaction type, mirrors `Transaction.type` (expense | income | transfer).
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

/// The five daily prayers, mirrors `PrayerEntry.prayer`.
const prayerNames = ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya'];

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
  factory ActivityEvent.prayer({
    String? id,
    required GameDate date,
    required String prayer,
    DateTime? createdAt,
  }) => ActivityEvent(
    kind: ActivityKind.prayer,
    id: id,
    at: createdAt ?? date.toLocalDateTime(),
    dayOverride: date,
    prayer: prayer.toLowerCase(),
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

  /// Prayer name (see [prayerNames]).
  final String? prayer;

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
