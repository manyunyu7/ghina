# Data API for screens

Screens import only `di/di.dart`, `domain/entities/entities.dart`, `domain/usecases/usecases.dart`
(input classes, pure helpers), `core/*` and `presentation/state/*`. Never import `data/`
or drift.

Everything works offline. Every write goes to the local DB and the outbox, and the UI
updates at once through the watch providers. Sync runs in the background.

## App bootstrap (owner of `main.dart` / `app/`)

```dart
await Fmt.initFormatting();                       // core/formatters.dart (optional, sync-safe)
runApp(ProviderScope(overrides: gameOverrides, child: App()));   // gameOverrides from di.dart
```

- `ref.watch(sessionControllerProvider)` gives `SessionLoading | SignedOut(expired) | SignedIn(user)`.
  Route on this. Sync starts and stops with the session on its own.
- The API URL comes from `--dart-define=API_BASE_URL=…`. The default is the emulator/simulator localhost on port 3000.

## Reading data: `ref.watch(provider)` → `AsyncValue<T>`

| Provider | Value |
|---|---|
| `watchWalletsProvider` / `watchAllWalletsProvider` | `List<Wallet>`, oldest first. The first one skips archived wallets. `wallet.balance` includes unsynced transactions and `syncedBalance` is the server value. |
| `watchWalletProvider(id)` | `Wallet?` |
| `watchCategoriesProvider(CategoryType?)` | `List<TxCategory>` sorted by name (`null` = all types) |
| `watchCategoryProvider(id)` | `TxCategory?` |
| `watchTransactionsProvider(TransactionFilter)` | `List<TransactionView>` (tx + wallet + toWallet + category, `.title`), newest first |
| `watchTransactionsByDayProvider(TransactionFilter)` | `List<DayGroup>` (`day`, `items`, `income`, `expense`, `net`) |
| `watchTransactionProvider(id)` | `TransactionView?` |
| `watchDashboardProvider` | `DashboardSummary`: `totalBalance`, `wallets`, `monthIncome`/`monthExpense`/`monthNet`, `todayExpense`/`todayIncome`, `monthBudgeted`, `spendingByCategory`, `trend` (6 × `MonthTotals`), `recent` (8) |
| `watchBudgetMonthProvider(YearMonth)` | `BudgetMonth`: `items` (`BudgetView`: `budget`, `category`, `spent`, `remaining`, `pct`, `over`, `transactions`), plus `totalBudgeted/Spent/Remaining/Pct`, `overCount` and `unbudgetedCategories` |
| `watchBudgetProvider(id)` | `Budget?` |
| `watchSubscriptionsProvider` | `SubscriptionSummary`: `items` (active first, by next billing), `monthlyTotal`, `yearlyTotal`. Each `Subscription` has `nextOccurrence(now)`, `daysUntilNext(now)` and `monthlyAmount`. |
| `watchSubscriptionProvider(id)` | `Subscription?` |
| `watchForecastProvider(YearMonth?)` | `Forecast` (`null` = next month): `planned`, `subscriptionItems`, `averages`, `totals(ForecastSources(manual, subscriptions, history))` → `projectedExpense/Income/net`. History is off by default, as on the web. |
| `watchPlannedProvider(id)` | `PlannedTransaction?` |
| `watchReportProvider(ReportPeriod)` | `ReportData`: `months` (income vs expense, cashflow `net`), `spending`/`income` (`CategoryTotal`: name, color, total, pct), `totalIncome/Expense`, `netSavings`, `savingsRate`, `netWorth`, `wallets`, `label`, `hasData`. Periods: `ReportPeriod.thisMonth`, `.last6Months`, `.last12Months`, `ReportPeriod.year(2026)`. |
| `watchPrayersProvider((from: d1, to: d2))` | `List<PrayerEntry>` (fardhu + daily sunnah, each with `status`, rawatib, `rakaat`, `prayedAt`, `note`). `prayerEntriesByDate(list)` → `Map<'YYYY-MM-DD', Map<Prayer, PrayerEntry>>`; `prayersByDate(list)` → prayed fardhu per day. |
| `watchPrayerReportProvider((from: d1, to: d2))` | `PrayerReport` (docs/prayer-quality.md): `score`, `pct(status)`, `jamaahPct`, `completeDays`, `breakdown`, `weakest`/`strongest`, `sunnahCounts`, `rawatibCount`, `days` (color-map rows, newest first). Ranges: `PrayerRangePreset.resolve(today)`, `customPrayerRange(a, b)`. |
| `watchHealthEntriesProvider` / `watchHealthEntryProvider(id)` | newest first. `entry.bpCategory` gives the AHA level, Indonesian label and color. |
| `watchFoodLogsProvider` / `watchFoodLogProvider(id)` | newest first. For the photo, use `localPhotoPath` (a `File`) if set, else `AppConfig.resolveUrl(photoUrl)`. |
| `syncStatusProvider` | `SyncStatus`: `phase` (idle, syncing, offline, error), `lastSyncAt`, `pendingCount`, `lastError` |
| `currentUserProvider` / `currencyProvider` | `AppUser?` / `'IDR'` … |

`TransactionFilter(month: YearMonth(2026, 9), type: TxType.expense, walletId:, categoryId:, search: 'kopi', limit:)`.
All fields are optional. `walletId` matches both sides of a transfer (the wallet "Riwayat"). `TxType.adjustment` rows have a signed amount and are never income/expense; `TxType.loggable` = the types a user logs. Rows of unknown future types are skipped. `search` matches the note, category name and wallet name.

## Writing data: `await ref.read(provider)(args)` → `Result<T>`

Mutations never throw. `switch (r) { case Ok(:final value): …; case Err(:final failure): … }`.
`failure` is a `Failure` (`ValidationFailure(field)`, `NotFoundFailure`, `NetworkFailure`,
`UnauthorizedFailure`, `ConflictFailure`, `UnknownFailure`), and `failure.message` is already in Indonesian.

| Area | Providers → call |
|---|---|
| Wallets | `createWalletProvider(WalletInput(name, type, currency, color, icon, initialBalance))`, `updateWalletProvider(id, WalletInput)` (balance ignored), `adjustWalletBalanceProvider(id, realBalance, note:)` → an `adjustment` transaction for the difference (docs/balance-adjustment.md), `setWalletArchivedProvider(id, bool)`, `deleteWalletProvider(id)` (also deletes its transactions) |
| Categories | `createCategoryProvider(CategoryInput(name, type, color, icon))` (`icon` must be one of `categoryIcons`), `updateCategoryProvider(id, …)`, `deleteCategoryProvider(id)`, `seedDefaultCategoriesProvider()` → count created (new server accounts already have defaults) |
| Transactions | `createTransactionProvider(TransactionInput(type, amount, walletId, toWalletId?, categoryId?, note?, date))`, `updateTransactionProvider(id, …)`, `deleteTransactionProvider(id)`, `transferBetweenWalletsProvider(fromWalletId:, toWalletId:, amount:, date:, note:)` |
| Budgets | `setBudgetProvider(categoryId:, amount:, month: YearMonth)` (upsert; expense categories only), `updateBudgetAmountProvider(id, amount)`, `deleteBudgetProvider(id)` |
| Subscriptions | `create/updateSubscriptionProvider(SubscriptionInput(...))`, `deleteSubscriptionProvider(id)`, `toggleSubscriptionProvider(id)` → new `active`, `paySubscriptionProvider(id)` → creates today's expense and advances `nextBilling` (quick pay) |
| Forecast | `create/updatePlannedProvider(PlannedInput(type, amount, note, date, categoryId, walletId))`, `deletePlannedProvider(id)`, `togglePlannedDoneProvider(id)`, `convertPlannedProvider(id)` → the new `Transaction` |
| Prayers | `setPrayerStatusProvider(day, Prayer.subuh, PrayerStatus.quick)` (tap = jamaah; clears rawatib on missed/excused), `savePrayerDetailsProvider(day, prayer, PrayerDetailsInput(status, qobliyah, badiyah, prayedAt, note))`, `toggleRawatibProvider(day, prayer, RawatibSlot.qobliyah)`, `setSunnahProvider(day, Prayer.witir, done:, rakaat:)`, `clearPrayerProvider(day, prayer)`, `togglePrayerProvider(day, prayer)` (quick toggle) |
| Health | `create/updateHealthEntryProvider(HealthInput(date, weight, systolic, diastolic, pulse, note))`, `deleteHealthEntryProvider(id)` |
| Food | `createFoodLogProvider(FoodInput(date, name, meal, calories, note), photoPath: picked.path)`, `updateFoodLogProvider(id, input, photoPath:, removePhoto:)`, `deleteFoodLogProvider(id)`. Compress in `image_picker` (`maxWidth: 1600, imageQuality: 80`), because the server limit is 5 MB. The photo uploads on the next sync. |
| Sync | `syncNowProvider()` (pull-to-refresh), `resetLocalDataProvider()` (Settings → reset: wipes local data, including unsynced changes, and downloads again) |

Account actions go through `ref.read(sessionControllerProvider.notifier)`:
- `signIn(email, pw)`
- `register(name, email, pw)`
- `signInWithGoogle(idToken)`: get the idToken from `google_sign_in`.
- `signOut()`: wipes local data.
- `refreshProfile()`
- `updateProfile(name:, currency:)`: needs to be online.

Each returns a `Result<AppUser>`, except `signOut`.

## Helpers and constants

- `Fmt.money(25000, currency: user.currency)` → `Rp 25.000`. There are also `Fmt.moneyCompact`, `Fmt.parseAmount('25.000')`, `Fmt.date`, `dateFull` (`Rabu, 23 September 2026`), `time`, `monthYear`, `monthShort`, and `relativeDay` (`Hari ini`/`Kemarin`).
- `YearMonth(y, m)` has `.start`, `.end`, `.next`, `.previous` and `.contains(d)`. Other date helpers: `dateKey(d)`, `defaultForecastMonth(now)`.
- Enums carry an Indonesian `.label`: `TxType`, `CategoryType`, `WalletType`, `BillingCycle` (`.per` → `/bln`), `MealType` (`.emoji`), `Prayer`.
- Lists: `colorPalette`, `categoryIcons`, `defaultCategories`, `subscriptionPresets`, `supportedCurrencies`.
- Pure functions: `groupTransactionsByDay`, `prayersByDate`, `classifyBp`, `occurrencesInRange`.
