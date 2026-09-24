/// Composition root, part 2: every use case as a provider, plus reactive
/// `watch…Provider`s that expose the watch use cases as `AsyncValue`s.
///
/// Mutations: `final r = await ref.read(createTransactionProvider)(input);`
/// → `Result<T>` (`Ok` / `Err(failure)`).
/// Streams:   `ref.watch(watchTransactionsProvider(filter))` → `AsyncValue<…>`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import '../presentation/state/session_controller.dart' show currencyProvider;
import 'core_providers.dart';

// ---------------------------------------------------------------- Wallets

final createWalletProvider = Provider<CreateWallet>(
  (ref) => CreateWallet(
    ref.watch(walletRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateWalletProvider = Provider<UpdateWallet>(
  (ref) => UpdateWallet(
    ref.watch(walletRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setWalletArchivedProvider = Provider<SetWalletArchived>(
  (ref) => SetWalletArchived(
    ref.watch(walletRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteWalletProvider = Provider<DeleteWallet>(
  (ref) => DeleteWallet(ref.watch(walletRepositoryProvider)),
);

/// "Sesuaikan saldo": records an `adjustment` transaction (works offline).
final adjustWalletBalanceProvider = Provider<AdjustWalletBalance>(
  (ref) => AdjustWalletBalance(
    ref.watch(walletRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

// ---------------------------------------------------------------- Categories

final createCategoryProvider = Provider<CreateCategory>(
  (ref) => CreateCategory(
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateCategoryProvider = Provider<UpdateCategory>(
  (ref) => UpdateCategory(
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteCategoryProvider = Provider<DeleteCategory>(
  (ref) => DeleteCategory(ref.watch(categoryRepositoryProvider)),
);
final seedDefaultCategoriesProvider = Provider<SeedDefaultCategories>(
  (ref) => SeedDefaultCategories(
    ref.watch(categoryRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

// ---------------------------------------------------------------- Transactions

final createTransactionProvider = Provider<CreateTransaction>(
  (ref) => CreateTransaction(
    ref.watch(transactionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateTransactionProvider = Provider<UpdateTransaction>(
  (ref) => UpdateTransaction(
    ref.watch(transactionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteTransactionProvider = Provider<DeleteTransaction>(
  (ref) => DeleteTransaction(ref.watch(transactionRepositoryProvider)),
);
final transferBetweenWalletsProvider = Provider<TransferBetweenWallets>(
  (ref) => TransferBetweenWallets(ref.watch(createTransactionProvider)),
);

/// `(txId, [pickedFile.path, …])` → appends pending photos (≤ 5 total).
final addTransactionPhotosProvider = Provider<AddTransactionPhotos>(
  (ref) => AddTransactionPhotos(
    ref.watch(transactionRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(txId, photo)` → removes one photo (uploaded or pending).
final removeTransactionPhotoProvider = Provider<RemoveTransactionPhoto>(
  (ref) => RemoveTransactionPhoto(
    ref.watch(transactionRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(txId, photos)` → replaces the list (reorder).
final setTransactionPhotosProvider = Provider<SetTransactionPhotos>(
  (ref) => SetTransactionPhotos(
    ref.watch(transactionRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

// ---------------------------------------------------------------- Budgets

final setBudgetProvider = Provider<SetBudget>(
  (ref) => SetBudget(
    ref.watch(budgetRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateBudgetAmountProvider = Provider<UpdateBudgetAmount>(
  (ref) => UpdateBudgetAmount(
    ref.watch(budgetRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteBudgetProvider = Provider<DeleteBudget>(
  (ref) => DeleteBudget(ref.watch(budgetRepositoryProvider)),
);

// ---------------------------------------------------------------- Subscriptions

final createSubscriptionProvider = Provider<CreateSubscription>(
  (ref) => CreateSubscription(
    ref.watch(subscriptionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateSubscriptionProvider = Provider<UpdateSubscription>(
  (ref) => UpdateSubscription(
    ref.watch(subscriptionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteSubscriptionProvider = Provider<DeleteSubscription>(
  (ref) => DeleteSubscription(ref.watch(subscriptionRepositoryProvider)),
);
final toggleSubscriptionProvider = Provider<ToggleSubscription>(
  (ref) => ToggleSubscription(
    ref.watch(subscriptionRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final paySubscriptionProvider = Provider<PaySubscription>(
  (ref) => PaySubscription(
    ref.watch(subscriptionRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

// ---------------------------------------------------------------- Planned items (forecast)

final createPlannedProvider = Provider<CreatePlanned>(
  (ref) => CreatePlanned(
    ref.watch(plannedRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updatePlannedProvider = Provider<UpdatePlanned>(
  (ref) => UpdatePlanned(
    ref.watch(plannedRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deletePlannedProvider = Provider<DeletePlanned>(
  (ref) => DeletePlanned(ref.watch(plannedRepositoryProvider)),
);
final togglePlannedDoneProvider = Provider<TogglePlannedDone>(
  (ref) => TogglePlannedDone(
    ref.watch(plannedRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final convertPlannedProvider = Provider<ConvertPlanned>(
  (ref) => ConvertPlanned(
    ref.watch(plannedRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

// ---------------------------------------------------------------- Prayers, health, food

final togglePrayerProvider = Provider<TogglePrayer>(
  (ref) => TogglePrayer(
    ref.watch(prayerRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setPrayerStatusProvider = Provider<SetPrayerStatus>(
  (ref) => SetPrayerStatus(
    ref.watch(prayerRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final toggleRawatibProvider = Provider<ToggleRawatib>(
  (ref) => ToggleRawatib(
    ref.watch(prayerRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setSunnahProvider = Provider<SetSunnah>(
  (ref) =>
      SetSunnah(ref.watch(prayerRepositoryProvider), ref.watch(clockProvider)),
);
final savePrayerDetailsProvider = Provider<SavePrayerDetails>(
  (ref) => SavePrayerDetails(
    ref.watch(prayerRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final clearPrayerProvider = Provider<ClearPrayer>(
  (ref) => ClearPrayer(ref.watch(prayerRepositoryProvider)),
);
final createHealthEntryProvider = Provider<CreateHealthEntry>(
  (ref) => CreateHealthEntry(
    ref.watch(healthRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateHealthEntryProvider = Provider<UpdateHealthEntry>(
  (ref) => UpdateHealthEntry(
    ref.watch(healthRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteHealthEntryProvider = Provider<DeleteHealthEntry>(
  (ref) => DeleteHealthEntry(ref.watch(healthRepositoryProvider)),
);
final createFoodLogProvider = Provider<CreateFoodLog>(
  (ref) => CreateFoodLog(
    ref.watch(foodRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateFoodLogProvider = Provider<UpdateFoodLog>(
  (ref) => UpdateFoodLog(
    ref.watch(foodRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteFoodLogProvider = Provider<DeleteFoodLog>(
  (ref) => DeleteFoodLog(ref.watch(foodRepositoryProvider)),
);

// ---------------------------------------------------------------- Tasks (docs/tasks.md)

final createTaskAreaProvider = Provider<CreateTaskArea>(
  (ref) => CreateTaskArea(
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateTaskAreaProvider = Provider<UpdateTaskArea>(
  (ref) => UpdateTaskArea(
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final reorderTaskAreasProvider = Provider<ReorderTaskAreas>(
  (ref) => ReorderTaskAreas(
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final setTaskAreaArchivedProvider = Provider<SetTaskAreaArchived>(
  (ref) => SetTaskAreaArchived(
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Deletes the area **and all its tasks**.
final deleteTaskAreaProvider = Provider<DeleteTaskArea>(
  (ref) => DeleteTaskArea(ref.watch(taskAreaRepositoryProvider)),
);

/// `(userId)` → creates Kerjaan + Keseharian when there is no area (0 or 2).
final seedDefaultTaskAreasProvider = Provider<SeedDefaultTaskAreas>(
  (ref) => SeedDefaultTaskAreas(
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final createTaskProvider = Provider<CreateTask>(
  (ref) => CreateTask(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateTaskProvider = Provider<UpdateTask>(
  (ref) => UpdateTask(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteTaskProvider = Provider<DeleteTask>(
  (ref) => DeleteTask(ref.watch(taskRepositoryProvider)),
);

/// `(id, expense: TaskExpense?)` → [TaskCompletion] (done task, next occurrence,
/// recorded expense).
final completeTaskProvider = Provider<CompleteTask>(
  (ref) => CompleteTask(
    ref.watch(taskRepositoryProvider),
    ref.watch(createTransactionProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final uncompleteTaskProvider = Provider<UncompleteTask>(
  (ref) => UncompleteTask(
    ref.watch(taskRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, bucket:, areaId:, sortOrder:)`
final moveTaskProvider = Provider<MoveTask>(
  (ref) => MoveTask(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `([ids in new order])` → sortOrder = index.
final reorderTasksProvider = Provider<ReorderTasks>(
  (ref) => ReorderTasks(
    ref.watch(taskRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

// ---------------------------------------------------------------- Account & sync

final restoreSessionProvider = Provider<RestoreSession>(
  (ref) => RestoreSession(ref.watch(authRepositoryProvider)),
);
final signInProvider = Provider<SignIn>(
  (ref) => SignIn(ref.watch(authRepositoryProvider)),
);
final registerProvider = Provider<Register>(
  (ref) => Register(ref.watch(authRepositoryProvider)),
);
final signInWithGoogleProvider = Provider<SignInWithGoogle>(
  (ref) => SignInWithGoogle(ref.watch(authRepositoryProvider)),
);
final signOutProvider = Provider<SignOut>(
  (ref) => SignOut(
    ref.watch(authRepositoryProvider),
    ref.watch(syncServiceProvider),
  ),
);
final refreshProfileProvider = Provider<RefreshProfile>(
  (ref) => RefreshProfile(ref.watch(authRepositoryProvider)),
);
final updateProfileProvider = Provider<UpdateProfile>(
  (ref) => UpdateProfile(ref.watch(authRepositoryProvider)),
);
final watchSessionExpiredProvider = Provider<WatchSessionExpired>(
  (ref) => WatchSessionExpired(ref.watch(authRepositoryProvider)),
);
final startSyncProvider = Provider<StartSync>(
  (ref) => StartSync(ref.watch(syncServiceProvider)),
);
final stopSyncProvider = Provider<StopSync>(
  (ref) => StopSync(ref.watch(syncServiceProvider)),
);
final syncNowProvider = Provider<SyncNow>(
  (ref) => SyncNow(ref.watch(syncServiceProvider)),
);
final resetLocalDataProvider = Provider<ResetLocalData>(
  (ref) => ResetLocalData(ref.watch(syncServiceProvider)),
);

// ---------------------------------------------------------------- watch use cases

final watchWalletsUseCaseProvider = Provider(
  (ref) => WatchWallets(ref.watch(walletRepositoryProvider)),
);
final watchCategoriesUseCaseProvider = Provider(
  (ref) => WatchCategories(ref.watch(categoryRepositoryProvider)),
);
final watchTransactionsUseCaseProvider = Provider(
  (ref) => WatchTransactions(
    ref.watch(transactionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
  ),
);
final watchBudgetMonthUseCaseProvider = Provider(
  (ref) => WatchBudgetMonth(
    ref.watch(budgetRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
  ),
);
final watchSubscriptionsUseCaseProvider = Provider(
  (ref) => WatchSubscriptions(
    ref.watch(subscriptionRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final watchForecastUseCaseProvider = Provider(
  (ref) => WatchForecast(
    ref.watch(plannedRepositoryProvider),
    ref.watch(subscriptionRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final watchDashboardUseCaseProvider = Provider(
  (ref) => WatchDashboard(
    ref.watch(transactionRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(budgetRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final watchReportUseCaseProvider = Provider(
  (ref) => WatchReport(
    ref.watch(transactionRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final watchTasksUseCaseProvider = Provider(
  (ref) => WatchTasks(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(tickSourceProvider),
  ),
);
final watchTaskBoardUseCaseProvider = Provider(
  (ref) => WatchTaskBoard(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(tickSourceProvider),
  ),
);

/// Task reminders merged with content post reminders (≤ 60 total).
final watchRemindersUseCaseProvider = Provider(
  (ref) => WatchReminders(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(tickSourceProvider),
    posts: ref.watch(contentPostRepositoryProvider),
    items: ref.watch(contentItemRepositoryProvider),
    accounts: ref.watch(socialAccountRepositoryProvider),
  ),
);
final watchSyncStatusUseCaseProvider = Provider(
  (ref) => WatchSyncStatus(ref.watch(syncServiceProvider)),
);

// ---------------------------------------------------------------- reactive providers

/// Non-archived wallets (displayed balances include pending changes).
final watchWalletsProvider = StreamProvider.autoDispose<List<Wallet>>(
  (ref) => ref.watch(watchWalletsUseCaseProvider)(),
);

/// All wallets including archived ones.
final watchAllWalletsProvider = StreamProvider.autoDispose<List<Wallet>>(
  (ref) => ref.watch(watchWalletsUseCaseProvider)(includeArchived: true),
);

final watchWalletProvider = StreamProvider.autoDispose.family<Wallet?, String>(
  (ref, id) => WatchWallet(ref.watch(walletRepositoryProvider))(id),
);

/// Categories by name; `null` = all types.
final watchCategoriesProvider = StreamProvider.autoDispose
    .family<List<TxCategory>, CategoryType?>(
      (ref, type) => ref.watch(watchCategoriesUseCaseProvider)(type: type),
    );

final watchCategoryProvider = StreamProvider.autoDispose
    .family<TxCategory?, String>(
      (ref, id) => WatchCategory(ref.watch(categoryRepositoryProvider))(id),
    );

/// Filtered transactions, newest first.
final watchTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionView>, TransactionFilter>(
      (ref, filter) => ref.watch(watchTransactionsUseCaseProvider)(filter),
    );

/// Same, grouped by local day (for the Transaksi tab).
final watchTransactionsByDayProvider = StreamProvider.autoDispose
    .family<List<DayGroup>, TransactionFilter>(
      (ref, filter) => WatchTransactionsByDay(
        ref.watch(watchTransactionsUseCaseProvider),
      )(filter),
    );

final watchTransactionProvider = StreamProvider.autoDispose
    .family<TransactionView?, String>(
      (ref, id) => WatchTransaction(
        ref.watch(transactionRepositoryProvider),
        ref.watch(walletRepositoryProvider),
        ref.watch(categoryRepositoryProvider),
      )(id),
    );

final watchBudgetMonthProvider = StreamProvider.autoDispose
    .family<BudgetMonth, YearMonth>(
      (ref, month) => ref.watch(watchBudgetMonthUseCaseProvider)(month),
    );

final watchBudgetProvider = StreamProvider.autoDispose.family<Budget?, String>(
  (ref, id) => WatchBudget(ref.watch(budgetRepositoryProvider))(id),
);

final watchSubscriptionsProvider =
    StreamProvider.autoDispose<SubscriptionSummary>(
      (ref) => ref.watch(watchSubscriptionsUseCaseProvider)(),
    );

final watchSubscriptionProvider = StreamProvider.autoDispose
    .family<Subscription?, String>(
      (ref, id) =>
          WatchSubscription(ref.watch(subscriptionRepositoryProvider))(id),
    );

/// Forecast of a month; `null` = next month (web default).
final watchForecastProvider = StreamProvider.autoDispose
    .family<Forecast, YearMonth?>(
      (ref, month) => ref.watch(watchForecastUseCaseProvider)(month),
    );

final watchPlannedProvider = StreamProvider.autoDispose
    .family<PlannedTransaction?, String>(
      (ref, id) => WatchPlanned(ref.watch(plannedRepositoryProvider))(id),
    );

final watchDashboardProvider = StreamProvider.autoDispose<DashboardSummary>(
  (ref) => ref.watch(watchDashboardUseCaseProvider)(),
);

final watchReportProvider = StreamProvider.autoDispose
    .family<ReportData, ReportPeriod>(
      (ref, period) => ref.watch(watchReportUseCaseProvider)(period),
    );

/// Prayers in an inclusive range of local days.
final watchPrayersProvider = StreamProvider.autoDispose
    .family<List<PrayerEntry>, ({DateTime from, DateTime to})>(
      (ref, r) =>
          WatchPrayers(ref.watch(prayerRepositoryProvider))(r.from, r.to),
    );

/// Prayer quality report for an inclusive range of local days (clipped to today).
final watchPrayerReportProvider = StreamProvider.autoDispose
    .family<PrayerReport, ({DateTime from, DateTime to})>(
      (ref, r) => WatchPrayerReport(
        ref.watch(prayerRepositoryProvider),
        ref.watch(clockProvider),
      )(r.from, r.to),
    );

/// Health entries, newest first (all).
final watchHealthEntriesProvider =
    StreamProvider.autoDispose<List<HealthEntry>>(
      (ref) => WatchHealthEntries(ref.watch(healthRepositoryProvider))(),
    );

final watchHealthEntryProvider = StreamProvider.autoDispose
    .family<HealthEntry?, String>(
      (ref, id) => WatchHealthEntry(ref.watch(healthRepositoryProvider))(id),
    );

/// Food logs, newest first (all).
final watchFoodLogsProvider = StreamProvider.autoDispose<List<FoodLog>>(
  (ref) => WatchFoodLogs(ref.watch(foodRepositoryProvider))(),
);

final watchFoodLogProvider = StreamProvider.autoDispose
    .family<FoodLog?, String>(
      (ref, id) => WatchFoodLog(ref.watch(foodRepositoryProvider))(id),
    );

// ---------------------------------------------------------------- tasks (reactive)

/// Non-archived areas, in area order.
final watchTaskAreasProvider = StreamProvider.autoDispose<List<TaskArea>>(
  (ref) => WatchTaskAreas(ref.watch(taskAreaRepositoryProvider))(),
);

/// Every area incl. archived (area manager).
final watchAllTaskAreasProvider = StreamProvider.autoDispose<List<TaskArea>>(
  (ref) => WatchTaskAreas(ref.watch(taskAreaRepositoryProvider))(
    includeArchived: true,
  ),
);

final watchTaskAreaProvider = StreamProvider.autoDispose
    .family<TaskArea?, String>(
      (ref, id) => WatchTaskArea(ref.watch(taskAreaRepositoryProvider))(id),
    );

/// Filtered tasks as a flat list (board order; `done` filter: latest first).
final watchTasksProvider = StreamProvider.autoDispose
    .family<List<TaskView>, TaskFilter>(
      (ref, filter) => ref.watch(watchTasksUseCaseProvider)(filter),
    );

/// The Tugas tab: three bucket sections for a filter (`TaskFilter.focus`,
/// `TaskFilter.everything`, `TaskFilter.area(id)`, …).
final watchTaskBoardProvider = StreamProvider.autoDispose
    .family<TaskBoard, TaskFilter>(
      (ref, filter) => ref.watch(watchTaskBoardUseCaseProvider)(filter),
    );

final watchTaskProvider = StreamProvider.autoDispose.family<TaskView?, String>(
  (ref, id) => WatchTask(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(tickSourceProvider),
  )(id),
);

/// Focus areas now (changes when a schedule starts or ends).
final watchFocusAreasProvider = StreamProvider.autoDispose<FocusAreas>(
  (ref) => WatchFocusAreas(
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(tickSourceProvider),
  )(),
);

/// Home: focus-area FIRE tasks + Sunday-morning "Sapu bersih SHOULD 🧹".
final watchTaskHomeProvider = StreamProvider.autoDispose<TaskHome>(
  (ref) => WatchTaskHome(
    ref.watch(taskRepositoryProvider),
    ref.watch(taskAreaRepositoryProvider),
    ref.watch(tickSourceProvider),
  )(),
);

/// The reminders to schedule — tasks + content posts (`[IG-TAYANG] …`), ≤ 60,
/// soonest first; emits only on change.
/// Feed to `ReminderScheduler.replaceAll`.
final watchRemindersProvider = StreamProvider.autoDispose<List<Reminder>>(
  (ref) => ref.watch(watchRemindersUseCaseProvider)(
    currency: ref.watch(currencyProvider),
  ),
);
