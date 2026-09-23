import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

/// Pure: budgets of [month] with spent amounts (web budgets page logic).
BudgetMonth computeBudgetMonth(
  YearMonth month,
  List<Budget> budgets,
  List<Transaction> transactions,
  List<TxCategory> categories,
) {
  final byCat = <String, List<Transaction>>{};
  for (final t in transactions) {
    if (t.type != TxType.expense || t.categoryId == null) continue;
    if (!month.contains(t.date)) continue;
    byCat.putIfAbsent(t.categoryId!, () => []).add(t);
  }
  final cats = {for (final c in categories) c.id: c};
  final items = [
    for (final b in budgets.where(
      (b) => b.month == month.month && b.year == month.year,
    ))
      BudgetView(
        budget: b,
        category: cats[b.categoryId],
        spent: (byCat[b.categoryId] ?? const []).fold(
          0.0,
          (s, t) => s + t.amount,
        ),
        transactions: List.unmodifiable(
          byCat[b.categoryId] ?? const <Transaction>[],
        ),
      ),
  ]..sort((a, b) => b.pct.compareTo(a.pct));
  final budgeted = items.map((i) => i.budget.categoryId).toSet();
  return BudgetMonth(
    month: month,
    items: items,
    unbudgetedCategories: categories
        .where(
          (c) => c.type == CategoryType.expense && !budgeted.contains(c.id),
        )
        .toList(),
  );
}

/// Budgets of a month with spent/remaining, sorted by usage.
final class WatchBudgetMonth {
  const WatchBudgetMonth(this._budgets, this._tx, this._categories);
  final BudgetRepository _budgets;
  final TransactionRepository _tx;
  final CategoryRepository _categories;

  Stream<BudgetMonth> call(YearMonth month) => combineLatest3(
    _budgets.watchByMonth(month),
    _tx.watch(from: month.start, to: month.end, type: TxType.expense),
    _categories.watchAll(),
    (List<Budget> b, List<Transaction> t, List<TxCategory> c) =>
        computeBudgetMonth(month, b, t, c),
  );
}

/// Pure: every budget (any month) with the spending of its category in its month.
List<BudgetView> computeBudgetUsage(
  List<Budget> budgets,
  List<Transaction> transactions,
  List<TxCategory> categories,
) {
  final spent = <(String, int, int), List<Transaction>>{};
  for (final t in transactions) {
    if (t.type != TxType.expense || t.categoryId == null) continue;
    spent
        .putIfAbsent((t.categoryId!, t.date.year, t.date.month), () => [])
        .add(t);
  }
  final cats = {for (final c in categories) c.id: c};
  return [
    for (final b in budgets)
      BudgetView(
        budget: b,
        category: cats[b.categoryId],
        spent: (spent[(b.categoryId, b.year, b.month)] ?? const <Transaction>[])
            .fold(0.0, (s, t) => s + t.amount),
        transactions: List.unmodifiable(
          spent[(b.categoryId, b.year, b.month)] ?? const <Transaction>[],
        ),
      ),
  ];
}

/// All budgets of all months with spent amounts (feeds gamification hearts).
final class WatchBudgetUsage {
  const WatchBudgetUsage(this._budgets, this._tx, this._categories);
  final BudgetRepository _budgets;
  final TransactionRepository _tx;
  final CategoryRepository _categories;

  Stream<List<BudgetView>> call() => combineLatest3(
    _budgets.watchAll(),
    _tx.watch(type: TxType.expense),
    _categories.watchAll(),
    computeBudgetUsage,
  );
}

final class WatchBudget {
  const WatchBudget(this._repo);
  final BudgetRepository _repo;

  Stream<Budget?> call(String id) => _repo.watchById(id);
}

/// Creates or updates the budget of an expense category for a month
/// (upsert on category + month, like the web's `setBudget`).
final class SetBudget {
  const SetBudget(this._budgets, this._categories, this._clock);
  final BudgetRepository _budgets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<Budget>> call({
    required String categoryId,
    required double amount,
    required YearMonth month,
  }) => guard(() async {
    final value = requirePositiveAmount(amount);
    final cat = await _categories.getById(categoryId);
    if (cat == null || cat.type != CategoryType.expense) {
      throw const ValidationFailure(
        'Kategori tidak valid',
        field: 'categoryId',
      );
    }
    final now = _clock.now();
    final existing = await _budgets.findByKey(categoryId, month);
    final b = Budget(
      id: existing?.id ?? newId(),
      categoryId: categoryId,
      amount: value,
      month: month.month,
      year: month.year,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _budgets.save(b);
    return b;
  });
}

final class UpdateBudgetAmount {
  const UpdateBudgetAmount(this._budgets, this._clock);
  final BudgetRepository _budgets;
  final Clock _clock;

  Future<Result<Budget>> call(String id, double amount) => guard(() async {
    final value = requirePositiveAmount(amount);
    final e = await _budgets.getById(id);
    if (e == null) throw const NotFoundFailure('Anggaran tidak ditemukan');
    final b = Budget(
      id: e.id,
      categoryId: e.categoryId,
      amount: value,
      month: e.month,
      year: e.year,
      createdAt: e.createdAt,
      updatedAt: _clock.now(),
    );
    await _budgets.save(b);
    return b;
  });
}

final class DeleteBudget {
  const DeleteBudget(this._budgets);
  final BudgetRepository _budgets;

  Future<Result<void>> call(String id) => guard(() => _budgets.delete(id));
}
