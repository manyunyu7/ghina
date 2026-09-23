import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../di/di.dart';

/// Month shown on the budgets page; the "new budget" form starts from it.
final budgetsMonthProvider = NotifierProvider<BudgetsMonth, YearMonth>(
  BudgetsMonth.new,
);

class BudgetsMonth extends Notifier<YearMonth> {
  @override
  YearMonth build() => YearMonth.of(ref.read(clockProvider).now());

  void set(YearMonth m) => state = m;
}

/// Category to preselect when opening `/budgets/new` from an
/// "unbudgeted category" chip. Consumed (cleared) by the form.
final budgetDraftCategoryProvider =
    NotifierProvider<BudgetDraftCategory, String?>(BudgetDraftCategory.new);

class BudgetDraftCategory extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}
