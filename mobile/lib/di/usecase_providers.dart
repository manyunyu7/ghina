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
