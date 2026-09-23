import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';

/// Months of history averaged for the "estimated from history" tier (web `HISTORY_MONTHS`).
const forecastHistoryMonths = 3;

/// Port of the web's `forecast/logic.ts` `occurrencesInMonth`: all billing occurrences
/// of a subscription within [start, end]. Rolls the anchor forward by whole cycles
/// (so a Jan 31 monthly anchor drifts to the 28th after February, like date-fns).
List<DateTime> occurrencesInRange(
  DateTime anchor,
  BillingCycle cycle,
  DateTime start,
  DateTime end,
) {
  final out = <DateTime>[];
  var d = anchor;
  var guard = 0;
  while (d.isBefore(start) && guard < 2000) {
    d = cycle.advance(d);
    guard++;
  }
  guard = 0;
  while (!d.isAfter(end) && guard < 2000) {
    out.add(d);
    d = cycle.advance(d);
    guard++;
  }
  return out;
}

/// Port of `getCategoryMonthlyAverages`: average monthly spend per expense category
/// over the last [months] complete months before [now]'s month. Only categories with
/// spend; largest first.
List<CategoryAverage> categoryMonthlyAverages(
  List<Transaction> transactions,
  List<TxCategory> categories,
  DateTime now, {
  int months = forecastHistoryMonths,
}) {
  final start = DateTime(now.year, now.month - months, 1);
  final end = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
  final sums = <String, double>{};
  for (final t in transactions) {
    if (t.type != TxType.expense || t.categoryId == null) continue;
    if (t.date.isBefore(start) || t.date.isAfter(end)) continue;
    sums[t.categoryId!] = (sums[t.categoryId!] ?? 0) + t.amount;
  }
  final cats = {
    for (final c in categories.where((c) => c.type == CategoryType.expense))
      c.id: c,
  };
  final out = <CategoryAverage>[];
  sums.forEach((id, sum) {
    final c = cats[id];
    final avg = sum / months;
    if (c != null && avg > 0) out.add(CategoryAverage(category: c, avg: avg));
  });
  out.sort((a, b) => b.avg.compareTo(a.avg));
  return out;
}

/// Pure forecast assembly (web forecast page): planned items in the month, occurrences
/// of **active** subscriptions, and history averages.
Forecast buildForecast({
  required YearMonth month,
  required List<PlannedTransaction> planned,
  required List<Subscription> subscriptions,
  required List<CategoryAverage> averages,
  int historyMonths = forecastHistoryMonths,
}) {
  final start = month.start;
  final end = month.end;
  final inMonth =
      planned
          .where((p) => !p.date.isBefore(start) && !p.date.isAfter(end))
          .toList()
        ..sort((a, b) {
          if (a.done != b.done) return a.done ? 1 : -1;
          return a.date.compareTo(b.date);
        });
  final subItems = [
    for (final s in subscriptions.where((s) => s.active))
      for (final d in occurrencesInRange(s.nextBilling, s.cycle, start, end))
        ForecastSubscriptionItem(subscription: s, date: d),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return Forecast(
    month: month,
    planned: inMonth,
    subscriptionItems: subItems,
    averages: averages,
    historyMonths: historyMonths,
  );
}

/// The web's default forecast month: the month after the current one.
YearMonth defaultForecastMonth(DateTime now) => YearMonth.of(now).next;

/// Reactive forecast for [month] (defaults to next month).
final class WatchForecast {
  const WatchForecast(
    this._planned,
    this._subs,
    this._tx,
    this._categories,
    this._clock,
  );
  final PlannedRepository _planned;
  final SubscriptionRepository _subs;
  final TransactionRepository _tx;
  final CategoryRepository _categories;
  final Clock _clock;

  Stream<Forecast> call([YearMonth? month]) {
    final now = _clock.now();
    final m = month ?? defaultForecastMonth(now);
    final histStart = DateTime(now.year, now.month - forecastHistoryMonths, 1);
    final histEnd = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
    return combineLatest4(
      _planned.watchRange(m.start, m.end),
      _subs.watchAll(),
      _tx.watch(from: histStart, to: histEnd, type: TxType.expense),
      _categories.watchAll(type: CategoryType.expense),
      (
        List<PlannedTransaction> p,
        List<Subscription> s,
        List<Transaction> t,
        List<TxCategory> c,
      ) => buildForecast(
        month: m,
        planned: p,
        subscriptions: s,
        averages: categoryMonthlyAverages(t, c, now),
      ),
    );
  }
}
