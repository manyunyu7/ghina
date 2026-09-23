import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';

/// Income/expense totals per month for [months] (transfers excluded).
List<MonthTotals> monthlyTotals(List<Transaction> txs, List<YearMonth> months) {
  final inc = <YearMonth, double>{};
  final exp = <YearMonth, double>{};
  for (final t in txs) {
    final m = YearMonth.of(t.date);
    if (t.type == TxType.income) inc[m] = (inc[m] ?? 0) + t.amount;
    if (t.type == TxType.expense) exp[m] = (exp[m] ?? 0) + t.amount;
  }
  return [
    for (final m in months)
      MonthTotals(month: m, income: inc[m] ?? 0, expense: exp[m] ?? 0),
  ];
}

/// Totals per category for one [type] (web `getSpendingByCategory` /
/// `getIncomeByCategory`), rows with total > 0 only, largest first, with % share.
List<CategoryTotal> categoryTotals(
  List<Transaction> txs,
  List<TxCategory> categories,
  TxType type, {
  DateTime? from,
  DateTime? to,
}) {
  final sums = <String?, double>{};
  for (final t in txs) {
    if (t.type != type) continue;
    if (from != null && t.date.isBefore(from)) continue;
    if (to != null && t.date.isAfter(to)) continue;
    sums[t.categoryId] = (sums[t.categoryId] ?? 0) + t.amount;
  }
  final cats = {for (final c in categories) c.id: c};
  // Rows whose category no longer exists count as uncategorized (merged).
  final merged = <String?, double>{};
  sums.forEach((id, v) {
    final key = id != null && cats.containsKey(id) ? id : null;
    merged[key] = (merged[key] ?? 0) + v;
  });
  final total = merged.values.where((v) => v > 0).fold(0.0, (s, v) => s + v);
  final rows = [
    for (final e in merged.entries.where((e) => e.value > 0))
      CategoryTotal(
        category: e.key == null ? null : cats[e.key],
        total: e.value,
        pct: total > 0 ? e.value / total * 100 : 0,
      ),
  ]..sort((a, b) => b.total.compareTo(a.total));
  return rows;
}

/// The last [count] months ending with [now]'s month, oldest first.
List<YearMonth> lastMonths(DateTime now, int count) {
  final cur = YearMonth.of(now);
  return [for (var i = count - 1; i >= 0; i--) cur.plus(-i)];
}

/// Web `resolvePeriod`: the months covered by [period] and an Indonesian label.
({List<YearMonth> months, DateTime start, DateTime end, String label})
resolvePeriod(ReportPeriod period, DateTime now) {
  final cur = YearMonth.of(now);
  switch (period.range) {
    case ReportRange.thisMonth:
      return (
        months: [cur],
        start: cur.start,
        end: cur.end,
        label: 'Bulan ini',
      );
    case ReportRange.year:
      final y = period.year ?? now.year;
      final max = y == now.year ? now.month : 12;
      return (
        months: [for (var m = 1; m <= max; m++) YearMonth(y, m)],
        start: DateTime(y, 1, 1),
        end: DateTime(y, 12, 31, 23, 59, 59, 999),
        label: 'Tahun $y',
      );
    case ReportRange.last6Months:
    case ReportRange.last12Months:
      final count = period.range == ReportRange.last12Months ? 12 : 6;
      final months = lastMonths(now, count);
      return (
        months: months,
        start: months.first.start,
        end: months.last.end,
        label: '$count bulan terakhir',
      );
  }
}

/// Pure report assembly.
ReportData buildReport({
  required ReportPeriod period,
  required DateTime now,
  required List<Transaction> transactions,
  required List<TxCategory> categories,
  required List<Wallet> wallets,
}) {
  final p = resolvePeriod(period, now);
  final active = wallets.where((w) => !w.archived).toList()
    ..sort((a, b) => b.balance.compareTo(a.balance));
  return ReportData(
    period: period,
    label: p.label,
    months: monthlyTotals(transactions, p.months),
    spending: categoryTotals(
      transactions,
      categories,
      TxType.expense,
      from: p.start,
      to: p.end,
    ),
    income: categoryTotals(
      transactions,
      categories,
      TxType.income,
      from: p.start,
      to: p.end,
    ),
    netWorth: active.fold(0, (s, w) => s + w.balance),
    wallets: active,
  );
}

/// Reports: income vs expense over time, by category, savings rate, cashflow, net worth.
final class WatchReport {
  const WatchReport(this._tx, this._categories, this._wallets, this._clock);
  final TransactionRepository _tx;
  final CategoryRepository _categories;
  final WalletRepository _wallets;
  final Clock _clock;

  Stream<ReportData> call([ReportPeriod period = ReportPeriod.last6Months]) {
    final now = _clock.now();
    final p = resolvePeriod(period, now);
    return combineLatest3(
      _tx.watch(from: p.start, to: p.end),
      _categories.watchAll(),
      _wallets.watchAll(includeArchived: false),
      (List<Transaction> t, List<TxCategory> c, List<Wallet> w) => buildReport(
        period: period,
        now: now,
        transactions: t,
        categories: c,
        wallets: w,
      ),
    );
  }
}

/// Pure dashboard assembly.
DashboardSummary buildDashboard({
  required DateTime now,
  required List<Wallet> wallets,
  required List<TxCategory> categories,
  required List<Transaction> transactions,
  required List<Budget> monthBudgets,
  required List<TransactionView> recent,
}) {
  final month = YearMonth.of(now);
  final active = wallets.where((w) => !w.archived).toList();
  final trend = monthlyTotals(transactions, lastMonths(now, 6));
  final today = transactions.where((t) => isSameDay(t.date, now));
  return DashboardSummary(
    month: month,
    totalBalance: active.fold(0, (s, w) => s + w.balance),
    wallets: active,
    monthIncome: trend.last.income,
    monthExpense: trend.last.expense,
    todayExpense: today
        .where((t) => t.type == TxType.expense)
        .fold(0, (s, t) => s + t.amount),
    todayIncome: today
        .where((t) => t.type == TxType.income)
        .fold(0, (s, t) => s + t.amount),
    monthBudgeted: monthBudgets.fold(0, (s, b) => s + b.amount),
    spendingByCategory: categoryTotals(
      transactions,
      categories,
      TxType.expense,
      from: month.start,
      to: month.end,
    ),
    trend: trend,
    recent: recent,
  );
}

/// Home screen numbers: total balance, this month's income/expense, today's spending,
/// budget total, spending by category, 6-month trend and the 8 latest transactions.
final class WatchDashboard {
  const WatchDashboard(
    this._tx,
    this._wallets,
    this._categories,
    this._budgets,
    this._clock,
  );
  final TransactionRepository _tx;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final BudgetRepository _budgets;
  final Clock _clock;

  Stream<DashboardSummary> call() {
    final now = _clock.now();
    final months = lastMonths(now, 6);
    return combineLatest5(
      _wallets.watchAll(),
      _categories.watchAll(),
      _tx.watch(from: months.first.start, to: months.last.end),
      _budgets.watchByMonth(YearMonth.of(now)),
      _tx.watch(limit: 8),
      (
        List<Wallet> w,
        List<TxCategory> c,
        List<Transaction> t,
        List<Budget> b,
        List<Transaction> recent,
      ) {
        final wm = {for (final x in w) x.id: x};
        final cm = {for (final x in c) x.id: x};
        return buildDashboard(
          now: now,
          wallets: w,
          categories: c,
          transactions: t,
          monthBudgets: b,
          recent: [
            for (final r in recent)
              TransactionView(
                transaction: r,
                wallet: wm[r.walletId],
                toWallet: r.toWalletId == null ? null : wm[r.toWalletId],
                category: r.categoryId == null ? null : cm[r.categoryId],
              ),
          ],
        );
      },
    );
  }
}
