/// Wires the gamification engine's data seams (see `lib/domain/game/README.md`).
///
/// Pass to the root scope: `ProviderScope(overrides: gameOverrides, child: App())`.
/// Without them the game providers throw `UnimplementedError`.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/streams.dart';
import '../data/game/shared_prefs_game_store.dart';
import '../domain/entities/entities.dart';
import '../domain/game/activity.dart';
import '../domain/game/game_date.dart';
import '../domain/game/game_store.dart';
import '../domain/usecases/usecases.dart';
import '../presentation/state/game/game_providers.dart';
import '../presentation/state/session_controller.dart';
import 'core_providers.dart';

/// Maps synced rows to the engine's [ActivityEvent]s. [tasks]: every task; the
/// done ones become `ActivityEvent.task` (by `doneAt`).
List<ActivityEvent> activityEventsFrom(
  List<Transaction> transactions,
  List<PrayerEntry> prayers,
  List<HealthEntry> health,
  List<FoodLog> food, {
  List<Task> tasks = const [],
}) => [
  // Balance adjustments are not "logging a transaction": no XP/streak/goal.
  for (final x in transactions.where((t) => !t.isAdjustment))
    ActivityEvent.transaction(
      id: x.id,
      createdAt: x.createdAt,
      type: TxKind.parse(x.type.wire),
      amount: x.amount,
      date: x.date,
    ),
  for (final x in prayers)
    if (GameDate.tryParse(x.date) case final d?)
      ActivityEvent.prayer(
        id: x.id,
        date: d,
        prayer: x.prayer.wire,
        status: x.status.wire,
        qobliyah: x.qobliyah,
        badiyah: x.badiyah,
        createdAt: x.createdAt,
      ),
  for (final x in health)
    ActivityEvent.health(
      id: x.id,
      createdAt: x.createdAt,
      date: x.date,
      hasWeight: x.weight != null,
    ),
  for (final x in food)
    ActivityEvent.food(id: x.id, createdAt: x.createdAt, date: x.date),
  for (final x in tasks)
    if (x.done)
      ActivityEvent.task(
        id: x.id,
        doneAt: x.doneAt ?? x.updatedAt,
        bucket: x.bucket.wire,
        seriesId: x.seriesId,
        areaId: x.areaId,
        createdAt: x.createdAt,
      ),
];

/// The production overrides (game progress in shared_preferences).
List<Override> get gameOverrides => buildGameOverrides();

/// [store] replaces the shared_preferences store (tests: `InMemoryGameStore()`).
List<Override> buildGameOverrides({GameStore? store}) => [
  gameStoreProvider.overrideWithValue(store ?? SharedPrefsGameStore()),
  gameClockProvider.overrideWith((ref) => ref.watch(clockProvider)),
  gameUserNameProvider.overrideWith(
    (ref) => ref.watch(currentUserProvider)?.displayName,
  ),
  activityEventsSourceProvider.overrideWith(
    (ref) => combineLatest5(
      ref.watch(transactionRepositoryProvider).watch(),
      ref
          .watch(prayerRepositoryProvider)
          .watchRange('0000-01-01', '9999-12-31'),
      ref.watch(healthRepositoryProvider).watchAll(),
      ref.watch(foodRepositoryProvider).watchAll(),
      ref.watch(taskRepositoryProvider).watchAll(),
      (t, p, h, f, k) => activityEventsFrom(t, p, h, f, tasks: k),
    ),
  ),
  budgetStatusSourceProvider.overrideWith(
    (ref) =>
        WatchBudgetUsage(
          ref.watch(budgetRepositoryProvider),
          ref.watch(transactionRepositoryProvider),
          ref.watch(categoryRepositoryProvider),
        )().map(
          (rows) => [
            for (final r in rows)
              BudgetStatus(
                categoryId: r.budget.categoryId,
                categoryName: r.category?.name,
                year: r.budget.year,
                month: r.budget.month,
                budget: r.budget.amount,
                spent: r.spent,
              ),
          ],
        ),
  ),
];
