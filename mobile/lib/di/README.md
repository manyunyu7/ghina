# Data API for screens

Screens import only `di/di.dart`, `domain/entities/entities.dart`, `domain/usecases/usecases.dart`
(input classes, pure helpers), `core/*` and `presentation/state/*`. Never import `data/`
or drift.

Everything works offline. Every write goes to the local DB and the outbox, and the UI
updates at once through the watch providers. Sync runs in the background.

## App bootstrap (owner of `main.dart` / `app/`)

```dart
await Fmt.initFormatting();                       // core/formatters.dart (optional, sync-safe)
runApp(ProviderScope(
  overrides: [...gameOverrides, ...reminderOverrides],   // both from di.dart
  child: App(),
));
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
| Tasks | see "Tasks & photos API" below |
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
| Transactions | `createTransactionProvider(TransactionInput(type, amount, walletId, toWalletId?, categoryId?, note?, date, photos?))` (photos: see below), `updateTransactionProvider(id, …)`, `deleteTransactionProvider(id)`, `transferBetweenWalletsProvider(fromWalletId:, toWalletId:, amount:, date:, note:)` |
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

## Tasks & photos API (`docs/tasks.md`, `docs/transaction-photos.md`)

Everything below is offline-first like the rest: writes go to the local DB + outbox and
the watch providers update at once. All types come from `domain/entities/entities.dart`,
all rules/inputs from `domain/usecases/usecases.dart`.

### Entities

- `TaskArea`: `id, name, code` (`KERJA`), `color` (`#rrggbb`), `icon` (one of
  `categoryIcons`), `schedule` (`AreaSchedule?`, null = anytime), `sortOrder`,
  `archived`, `hasSchedule`, `copyWith`.
- `AreaSchedule(days: [1..7], start: 'HH:mm', end: 'HH:mm')` — ISO weekdays (1 = Senin),
  `start < end`. `AreaSchedule.workHours` = Mon–Fri 09:00–17:00. `contains(now)`.
  Labels: `isoWeekdayShort` (`Sen…Min`), `isoWeekdayNames`.
- `Task`: `id, areaId, title, note, bucket` (`TaskBucket`), `dueDate` (`'YYYY-MM-DD'`),
  `dueTime` (`'HH:mm'`), `remindBefore` (minutes, null = no reminder), `recurrence`,
  `seriesId`, `done`, `doneAt`, `sortOrder`, money link `amount, walletId, categoryId`,
  `transactionId`, and helpers `dueDay` (DateTime), `dueAt` (DateTime with time),
  `remindAt`, `isRecurring`, `hasMoneyLink`, `hasReminder`, `copyWith`.
- `TaskBucket.fire | want | should` (this order everywhere = `TaskBucket.values`):
  `.label` (`FIRE`), `.emoji` (🔥 ✨ 📋), `.display` (`🔥 FIRE`), `.meaning`, `.color`
  (ARGB int: `Color(bucket.color)`), `.xp` (10/8/5).
- `Recurrence(freq: RecurrenceFreq.daily|weekly|monthly, interval: 1..365, weekdays:
  [1..7]?, monthDay: 1..31?)`; shortcuts `Recurrence.daily(n)`,
  `Recurrence.weekly(interval:, weekdays:)`, `Recurrence.monthly(interval:, monthDay:)`;
  `.label` (`Setiap 2 minggu (Sen, Rab)`). Defaults (weekday/day of the due date) are
  filled in on save.
- `TaskView` (what lists give you): `task`, `area`, `isOverdue` (red "Terlambat" =
  `overdueLabel`, `overdueColor`), `isMepet` (WANT due today/tomorrow → "Mepet" =
  `mepetLabel`, fire accent), `isDueToday`, `tag` (`[KERJA-FIRE]`), `id/title/bucket/done`.
- Helpers: `formatHm(h, m)` → `'09:05'`, `isHm(s)`, `remindBeforeOptions` (`[0, 10, 30,
  60]`), `sortOrderBetween(prev, next)` for drag & drop, `taskRoute(id)` (`/tasks/<id>`,
  the notification tap route), `expenseDraftFor(task)`, `defaultAreaIds(userId)`.

### Reading (`ref.watch(provider)` → `AsyncValue`)

Time-based values (focus mode, Terlambat, Mepet, reminders) are re-evaluated every
minute by themselves; streams only emit when the result actually changes.

| Provider | Value |
|---|---|
| `watchTaskAreasProvider` / `watchAllTaskAreasProvider` | `List<TaskArea>` in area order; the first skips archived (chips), the second has all (area manager) |
| `watchTaskAreaProvider(id)` | `TaskArea?` |
| `watchFocusAreasProvider` | `FocusAreas`: `areas` (non-archived areas whose schedule contains now; else the unscheduled ones), `ids`, `bySchedule` (true = "jam kerja" style match) |
| `watchTaskBoardProvider(TaskFilter)` | `TaskBoard`: `sections` (always 3, fire → want → should; `section(TaskBucket.fire).tasks`), `areas` in scope, `total`, `isEmpty` |
| `watchTasksProvider(TaskFilter)` | flat `List<TaskView>` (board order; the `done` filter is newest-completed first) |
| `watchTaskProvider(id)` | `TaskView?` (task sheet) |
| `watchTaskHomeProvider` | `TaskHome`: `focus`, `fireTasks` (undone FIRE of the focus areas), `showSapuBersih` (Sunday < 12:00) + `sapuBersih` (undone SHOULD of unscheduled areas), `overdueCount`, `openCount` |
| `watchRemindersProvider` | `List<Reminder>` (≤ 60, soonest first) — already wired to notifications via `reminderOverrides` |

`TaskFilter(focusAreasOnly:, areaIds:, bucket:, status:, search:)` — value-equal, safe as
a family key. Presets: `TaskFilter.focus` (Tugas tab default), `TaskFilter.everything`
("Semua"), `TaskFilter.area(id)`. `areaIds: null` = all non-archived areas (an archived
area shows only when listed explicitly). `status` (`TaskStatusFilter`, each with an
Indonesian `.label`): `open` (default, undone), `today` (due today), `mepet`, `overdue`,
`done` (Selesai), `all`. `search` matches title + note.

### Writing (`await ref.read(provider)(…)` → `Result<T>`)

| Provider → call | Notes |
|---|---|
| `createTaskAreaProvider(TaskAreaInput(name, code, color:, icon:, schedule:))` → `TaskArea` | code is uppercased; `ValidationFailure(field: 'code')` if not `A–Z0–9{1,8}` or already used; name 1–40; `field: 'schedule'` for no day / start ≥ end. Added at the end of the order. |
| `updateTaskAreaProvider(id, TaskAreaInput)` | keeps order/archived |
| `reorderTaskAreasProvider([ids in new order])` | sortOrder = index |
| `setTaskAreaArchivedProvider(id, bool)` | archived areas leave the chips/board/focus |
| `deleteTaskAreaProvider(id)` | **also deletes all its tasks** (confirm in the UI) |
| `seedDefaultTaskAreasProvider(userId)` → `int` | Kerjaan + Keseharian if there is no area (0 or 2). Normally unnecessary: the server seeds them and the sync engine seeds locally after the first pull if still none. |
| `createTaskProvider(TaskInput(areaId:, title:, bucket:, dueDate:, dueTime:, remindBefore:, recurrence:, note:, amount:, walletId:, categoryId:))` → `Task` | quick add = `areaId, title, bucket, dueDate?`. `dueDate` is a `DateTime` (day only), `dueTime` `'HH:mm'` (needs dueDate), `remindBefore` 0–10080 (fires only with date + time; use the Settings default for new timed tasks), recurrence needs dueDate, amount > 0, category must be an expense one. Errors carry `field` (`title`, `areaId`, `dueTime`, `remindBefore`, `recurrence`, `amount`, `categoryId`). New task goes to the end of its (area, bucket) cell. |
| `updateTaskProvider(id, TaskInput)` | full edit; keeps done/doneAt/transactionId; a new area/bucket moves it to the end of that cell |
| `deleteTaskProvider(id)` | swipe to delete |
| `completeTaskProvider(id, expense: TaskExpense?)` → `TaskCompletion(task, next, transaction)` | Money link flow: if `task.hasMoneyLink`, ask "Catat pengeluaran ${Fmt.money(task.amount!)}?" with `expenseDraftFor(task)` (amount, wallet, category, note = title; `walletId` may be null → let the user pick, else `ValidationFailure(field: 'walletId')`). Accept → pass `expense: draft` (or `draft.copyWith(walletId: …)`) — the expense is created via `createTransaction` and linked (`transactionId`); decline → call without `expense`. Recurring → `next` is the next occurrence (deterministic id; completing twice/on two devices never duplicates). Already done → no-op. All-or-nothing. |
| `uncompleteTaskProvider(id)` | keeps the next occurrence and the recorded expense |
| `moveTaskProvider(id, bucket:, areaId:, sortOrder:)` | long-press "pindah"/drag; `sortOrder` null = end of the target cell, else `sortOrderBetween(prev?.task.sortOrder, next?.task.sortOrder)` |
| `reorderTasksProvider([ids of one cell in new order])` | sortOrder = index |

XP for the completion celebration: `task.bucket.xp` (the game engine's rules are wired
separately; see `lib/domain/game/README.md`).

### Transaction photos

`Transaction.photos` is a `List<TransactionPhoto>` (≤ `maxTransactionPhotos` = 5, display
order); `hasPhotos` for the list badge (count = `photos.length`). Each photo is either
uploaded — `photo.url` (`/uploads/x.jpg`, display with `AppConfig.resolveUrl(url)`) — or
pending — `photo.isPending`, `photo.localPath` (display with `Image.file(File(path))`
right away; it uploads on the next sync, before the transaction is pushed).

| Provider → call | Notes |
|---|---|
| `createTransactionProvider(TransactionInput(…, photos: [TransactionPhoto.local(x.path), …]))` | new transaction with photos (quick-add chip) |
| `updateTransactionProvider(id, TransactionInput(…, photos: …))` | `photos: null` keeps the current list; pass the edited list to change it |
| `addTransactionPhotosProvider(txId, [path, …])` → `Transaction` | append picked files (`ValidationFailure(field: 'photos')` beyond 5) |
| `removeTransactionPhotoProvider(txId, photo)` → `Transaction` | uploaded or pending |
| `setTransactionPhotosProvider(txId, photos)` → `Transaction` | reorder |

Compress in `image_picker` (`maxWidth: 1600, imageQuality: 80`; `pickMultiImage` for the
gallery). Picked files are copied into app storage, so temp files may disappear. A photo
the server refuses (bad/too large) is dropped and reported through
`syncStatusProvider.lastError`; network/server errors retry with backoff.
