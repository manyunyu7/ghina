import 'activity.dart';
import 'game_date.dart';
import 'xp_rules.dart';

/// Budget health for a month: 5 hearts, minus one per over-budget category.
class HeartsState {
  const HeartsState({
    required this.month,
    required this.current,
    required this.overBudget,
    required this.nearLimit,
    required this.budgetCount,
  });

  final GameMonth month;
  final int current;
  int get max => XpRules.heartsPerMonth;

  /// Categories over budget this month (each costs a heart).
  final List<BudgetStatus> overBudget;

  /// Categories at >= 90% but not over (warn the user).
  final List<BudgetStatus> nearLimit;

  /// Budgets set for this month.
  final int budgetCount;

  bool get isFull => current == max;
  bool get isLow => current <= 2;
  bool get isEmpty => current == 0;
  int get lost => max - current;
}

abstract final class HeartsCalculator {
  static HeartsState compute(Iterable<BudgetStatus> budgets, GameMonth month) {
    final thisMonth = budgets
        .where((b) => b.isIn(month.year, month.month))
        .toList();
    // One heart per category, even if duplicated rows exist.
    final over = <String, BudgetStatus>{};
    final near = <String, BudgetStatus>{};
    for (final b in thisMonth) {
      if (b.isOver) {
        over[b.categoryId] = b;
      } else if (b.budget > 0 && b.ratio >= XpRules.nearBudgetRatio) {
        near[b.categoryId] = b;
      }
    }
    near.removeWhere((k, _) => over.containsKey(k));
    final current = XpRules.heartsPerMonth - over.length;
    return HeartsState(
      month: month,
      current: current < 0 ? 0 : current,
      overBudget: over.values.toList(),
      nearLimit: near.values.toList(),
      budgetCount: {for (final b in thisMonth) b.categoryId}.length,
    );
  }
}
