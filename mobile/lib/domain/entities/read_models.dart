/// Composite, read-only view models produced by the watch use cases.
library;

import '../../core/dates.dart';
import 'budget.dart';
import 'category.dart';
import 'enums.dart';
import 'planned_transaction.dart';
import 'subscription.dart';
import 'transaction.dart';
import 'wallet.dart';

// ---------------------------------------------------------------- transactions

/// Filters for `WatchTransactions`. All fields optional; combine freely.
final class TransactionFilter {
  const TransactionFilter({
    this.month,
    this.from,
    this.to,
    this.type,
    this.walletId,
    this.categoryId,
    this.search,
    this.limit,
  });

  /// Restrict to one calendar month (overrides [from]/[to]).
  final YearMonth? month;

  /// Inclusive range bounds on `date`.
  final DateTime? from;
  final DateTime? to;
  final TxType? type;

  /// Matches either side of a transfer.
  final String? walletId;
  final String? categoryId;

  /// Case-insensitive match on note, category name or wallet name.
  final String? search;
  final int? limit;

  static const all = TransactionFilter();

  DateTime? get rangeStart => month?.start ?? from;
  DateTime? get rangeEnd => month?.end ?? to;

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.month == month &&
      other.from == from &&
      other.to == to &&
      other.type == type &&
      other.walletId == walletId &&
      other.categoryId == categoryId &&
      other.search == search &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(month, from, to, type, walletId, categoryId, search, limit);
}

/// A transaction joined with its wallet(s) and category for display.
final class TransactionView {
  const TransactionView({
    required this.transaction,
    this.wallet,
    this.toWallet,
    this.category,
  });

  final Transaction transaction;
  final Wallet? wallet;
  final Wallet? toWallet;
  final TxCategory? category;

  String get id => transaction.id;
  TxType get type => transaction.type;
  double get amount => transaction.amount;
  DateTime get date => transaction.date;

  /// Display title: note, else category name, else a type label.
  String get title {
    final note = transaction.note?.trim();
    if (note != null && note.isNotEmpty) return note;
    if (transaction.isTransfer) {
      return 'Transfer ke ${toWallet?.name ?? 'dompet'}';
    }
    return category?.name ?? transaction.type.label;
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionView &&
      other.transaction == transaction &&
      other.wallet == wallet &&
      other.toWallet == toWallet &&
      other.category == category;

  @override
  int get hashCode => Object.hash(transaction, wallet, toWallet, category);
}

/// Transactions of one local day (see `groupTransactionsByDay`).
final class DayGroup {
  const DayGroup({
    required this.day,
    required this.items,
    required this.income,
    required this.expense,
  });

  /// Local midnight of the day.
  final DateTime day;
  final List<TransactionView> items;
  final double income;
  final double expense;
  double get net => income - expense;
}

// ---------------------------------------------------------------- aggregates

/// Income/expense totals for one month (transfers excluded).
final class MonthTotals {
  const MonthTotals({
    required this.month,
    required this.income,
    required this.expense,
  });

  final YearMonth month;
  final double income;
  final double expense;
  double get net => income - expense;

  @override
  bool operator ==(Object other) =>
      other is MonthTotals &&
      other.month == month &&
      other.income == income &&
      other.expense == expense;

  @override
  int get hashCode => Object.hash(month, income, expense);

  @override
  String toString() => 'MonthTotals($month, +$income, -$expense)';
}

/// Total per category (null category = "Tanpa kategori"), with share of the whole.
final class CategoryTotal {
  const CategoryTotal({
    required this.category,
    required this.total,
    required this.pct,
  });

  final TxCategory? category;
  final double total;

  /// 0–100 share of the sum of all rows in the same list.
  final double pct;

  static const uncategorizedColor = '#94a3b8';
  String get name => category?.name ?? 'Tanpa kategori';
  String get color => category?.color ?? uncategorizedColor;
}

// ---------------------------------------------------------------- budgets

/// One budget with what has been spent against it this month.
final class BudgetView {
  const BudgetView({
    required this.budget,
    required this.category,
    required this.spent,
    required this.transactions,
  });

  final Budget budget;
  final TxCategory? category;
  final double spent;

  /// Expense transactions of the month in this category, newest first.
  final List<Transaction> transactions;

  double get remaining => budget.amount - spent;
  double get pct => budget.amount > 0 ? spent / budget.amount * 100 : 0;
  bool get over => spent > budget.amount;
}

/// All budgets of a month, sorted by usage (most used first), plus totals.
final class BudgetMonth {
  const BudgetMonth({
    required this.month,
    required this.items,
    required this.unbudgetedCategories,
  });

  final YearMonth month;
  final List<BudgetView> items;

  /// Expense categories that have no budget this month (for the "add budget" picker).
  final List<TxCategory> unbudgetedCategories;

  double get totalBudgeted => items.fold(0, (s, b) => s + b.budget.amount);
  double get totalSpent => items.fold(0, (s, b) => s + b.spent);
  double get totalRemaining => totalBudgeted - totalSpent;
  double get totalPct =>
      totalBudgeted > 0 ? totalSpent / totalBudgeted * 100 : 0;
  bool get over => totalSpent > totalBudgeted;
  int get overCount => items.where((b) => b.over).length;
}

// ---------------------------------------------------------------- dashboard

final class DashboardSummary {
  const DashboardSummary({
    required this.month,
    required this.totalBalance,
    required this.wallets,
    required this.monthIncome,
    required this.monthExpense,
    required this.todayExpense,
    required this.todayIncome,
    required this.monthBudgeted,
    required this.spendingByCategory,
    required this.trend,
    required this.recent,
  });

  final YearMonth month;

  /// Sum of displayed balances of non-archived wallets.
  final double totalBalance;
  final List<Wallet> wallets;
  final double monthIncome;
  final double monthExpense;
  double get monthNet => monthIncome - monthExpense;
  final double todayExpense;
  final double todayIncome;

  /// Sum of this month's budgets (0 when none).
  final double monthBudgeted;

  /// This month's expenses by category, largest first.
  final List<CategoryTotal> spendingByCategory;

  /// Last 6 months (oldest → current).
  final List<MonthTotals> trend;

  /// Latest transactions (8).
  final List<TransactionView> recent;
}

// ---------------------------------------------------------------- reports

enum ReportRange { thisMonth, last6Months, last12Months, year }

/// Report window (web `resolvePeriod`): this month, rolling 6/12 months, or a calendar year.
final class ReportPeriod {
  const ReportPeriod(this.range, {this.year});

  static const thisMonth = ReportPeriod(ReportRange.thisMonth);
  static const last6Months = ReportPeriod(ReportRange.last6Months);
  static const last12Months = ReportPeriod(ReportRange.last12Months);
  const ReportPeriod.year(int this.year) : range = ReportRange.year;

  final ReportRange range;

  /// Only for [ReportRange.year].
  final int? year;

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.range == range && other.year == year;

  @override
  int get hashCode => Object.hash(range, year);
}

final class ReportData {
  const ReportData({
    required this.period,
    required this.label,
    required this.months,
    required this.spending,
    required this.income,
    required this.netWorth,
    required this.wallets,
  });

  final ReportPeriod period;

  /// Indonesian label, e.g. `6 bulan terakhir`.
  final String label;

  /// Per-month totals (oldest → newest) — income vs expense & cashflow charts.
  final List<MonthTotals> months;

  /// Expense by category over the whole period, largest first.
  final List<CategoryTotal> spending;

  /// Income by category over the whole period, largest first.
  final List<CategoryTotal> income;

  /// Sum of current displayed balances of non-archived wallets.
  final double netWorth;

  /// Non-archived wallets, highest balance first.
  final List<Wallet> wallets;

  double get totalIncome => months.fold(0, (s, m) => s + m.income);
  double get totalExpense => months.fold(0, (s, m) => s + m.expense);
  double get netSavings => totalIncome - totalExpense;

  /// Percent of income saved (0 when no income).
  double get savingsRate =>
      totalIncome > 0 ? netSavings / totalIncome * 100 : 0;
  bool get hasData => totalIncome > 0 || totalExpense > 0;
}

// ---------------------------------------------------------------- subscriptions

final class SubscriptionSummary {
  const SubscriptionSummary({required this.items});

  /// All subscriptions: active first, then by next occurrence.
  final List<Subscription> items;

  Iterable<Subscription> get active => items.where((s) => s.active);
  double get monthlyTotal => active.fold(0, (s, x) => s + x.monthlyAmount);
  double get yearlyTotal => active.fold(0, (s, x) => s + x.yearlyAmount);
}

// ---------------------------------------------------------------- forecast

/// One billing of a subscription inside the forecast month.
final class ForecastSubscriptionItem {
  const ForecastSubscriptionItem({
    required this.subscription,
    required this.date,
  });

  final Subscription subscription;
  final DateTime date;

  /// Stable key (web: `${id}-${date.getTime()}`).
  String get key => '${subscription.id}-${date.millisecondsSinceEpoch}';
  double get amount => subscription.amount;
}

/// Average monthly spend of one expense category over the history window.
final class CategoryAverage {
  const CategoryAverage({required this.category, required this.avg});

  final TxCategory category;
  final double avg;
}

/// Which forecast sources to include (web chips; history is off by default).
final class ForecastSources {
  const ForecastSources({
    this.manual = true,
    this.subscriptions = true,
    this.history = false,
  });

  final bool manual;
  final bool subscriptions;
  final bool history;

  bool get none => !manual && !subscriptions && !history;
}

final class ForecastTotals {
  const ForecastTotals({
    required this.projectedExpense,
    required this.projectedIncome,
  });

  final double projectedExpense;
  final double projectedIncome;
  double get net => projectedIncome - projectedExpense;
}

/// Forecast of one month: planned items (tier 3), subscription billings (tier 1) and
/// history averages (tier 2). Use [totals] with the user's source toggles.
final class Forecast {
  const Forecast({
    required this.month,
    required this.planned,
    required this.subscriptionItems,
    required this.averages,
    required this.historyMonths,
  });

  final YearMonth month;

  /// Sorted: not-done first, then by date.
  final List<PlannedTransaction> planned;

  /// Sorted by date.
  final List<ForecastSubscriptionItem> subscriptionItems;

  /// Largest first.
  final List<CategoryAverage> averages;
  final int historyMonths;

  double get plannedExpense => planned
      .where((p) => p.type == TxType.expense)
      .fold(0, (s, p) => s + p.amount);
  double get plannedIncome => planned
      .where((p) => p.type == TxType.income)
      .fold(0, (s, p) => s + p.amount);
  double get subscriptionsExpense =>
      subscriptionItems.fold(0, (s, x) => s + x.amount);
  double get estimatedExpense => averages.fold(0, (s, x) => s + x.avg);

  bool get isEmpty =>
      planned.isEmpty && subscriptionItems.isEmpty && averages.isEmpty;

  ForecastTotals totals([ForecastSources sources = const ForecastSources()]) =>
      ForecastTotals(
        projectedExpense:
            (sources.manual ? plannedExpense : 0) +
            (sources.subscriptions ? subscriptionsExpense : 0) +
            (sources.history ? estimatedExpense : 0),
        projectedIncome: sources.manual ? plannedIncome : 0,
      );
}
