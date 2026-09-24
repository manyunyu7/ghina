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

## Notes & content API (`docs/notes.md`, `docs/content.md`)

Offline-first like everything else. Providers live in `di/notes_content_providers.dart`
(exported by `di/di.dart`); types come from `domain/entities/entities.dart`, rules and
inputs from `domain/usecases/usecases.dart` (`notes_rules.dart`, `content_rules.dart`,
`notes_usecases.dart`, `content_usecases.dart`). Rules are ports of the server's
`src/lib/notes.ts` / `src/lib/content.ts` (same limits, messages, ids).

### Entities

- `Note`: `id, title?` (one line ≤ 200), `body` (Markdown subset ≤ 50 000), `checklist`
  (`List<ChecklistItem(id, text, done)>`, ≤ 200), `labelIds` (≤ 20), `color` (a
  **palette id** or null — `noteColors` = 11 `NoteColor(id, label, light, dark)`; use
  `note.palette?.light/.dark`), `pinned`, `archived`, `photos`
  (`List<TransactionPhoto>` ≤ 10 — same type/rules as transaction photos: `url` or
  pending `localPath`), `audio` (`List<NoteAudio>` ≤ 5: `url` or pending `localPath`,
  `durationSec`, `transcript?`, `isPending`, `hasTranscript`), `links`
  (`List<NoteLink(url, title?)>` ≤ 20; body URLs are added automatically, titles arrive
  from the server later), `source` (`NoteSource.share|quick|voice`), `linkedTaskId`,
  `linkedContentId`, `linkedTransactionId`. Helpers: `displayTitle` (title → first body
  line without markdown → first checklist text → `''`), `checklistDone`, `hasPhotos`,
  `hasAudio`, `hasLabels`, `hasPendingUploads`, `isBlank`, `hasLabel(id)`, `copyWith`.
- `NoteLabel`: `id, name` (1–30, unique case-insensitively), `color` (`#rrggbb`),
  `pinnedTab` (shown as a tab), `sortOrder`. `NoteView(note, labels)` = a note with its
  label rows (what lists give you).
- `SocialAccount`: `platform` (`SocialPlatform` enum = the web's registry: `.label`,
  `.code` IG/TT/YT/X/TH/IN/FB/LAIN, `.color`, `.icon` (lucide name: camera, music-2,
  play, at-sign, briefcase, users, globe), `.profileUrl/.createUrl/.appUrl` templates),
  `platformName` (required for `other`), `handle`, `color`, `targetPerWeek?`, `archived`,
  `sortOrder`. Helpers: `platformLabel`, `code` (`other` → `PINT` from "Pinterest"),
  `atHandle`, `profileUrl`, `appUrl` ("Buka Instagram": try `appUrl`, fall back to
  `profileUrl`), `createUrl`, `hasTarget`.
- `ContentItem`: `title, stage` (`ContentStage.ide|naskah|produksi|siap|terjadwal|tayang`,
  each with `.label`, `.emoji`, `.color`, `.xp`), `format?` (`ContentFormat`, `.label`),
  `pillar?` (a pillar **name**), `idea` (Markdown), `noteId?`, `checklist`, `photos`
  (≤ 10), `assetLinks` (`AssetLink(url, label?)` ≤ 20), `sponsor?`
  (`Sponsor(brand, amount ≥ 0 — 0 = barter, currency, due 'YYYY-MM-DD'?, paid,
  transactionId?)`), `stageReachedAt` (device-only, for XP).
- `ContentPost` (one per account per item): `contentId, accountId, caption, hashtags,
  scheduledAt?, remindBefore?, status` (`PostStatus.draft|scheduled|posted|skipped`,
  `.label`, `.color`), `postedAt?, url?, metrics` (`PostMetrics(views, likes, comments,
  shares, saves, followers)` all optional ints, `.engagement`, `.isEmpty`), `metricsAt?`.
  Helpers: `copyText` ("Salin caption + hashtag"), `calendarAt`, `remindAt`, `isPosted`…
- `ContentPillar(id, name, color, sortOrder)`.
- Read models: `ContentPostView(post, account?, item?)` (`title`, `code`, `color`,
  `notificationTitle`), `ContentItemView(item, posts, note?)` (`accounts`,
  `nextScheduledAt`, `postedCount`), `ContentBoard(columns)` (always 6
  `ContentColumn(stage, items)`, `column(stage)`, `total`), `ContentCalendar(from, to,
  days: {'YYYY-MM-DD': [ContentPostView]}, weeks: [CalendarWeek(weekStart, accounts:
  [AccountWeekCount])])` with `AccountWeekCount.label` = `IG: 1/3` (planned/target),
  `posted`, `met`, `emptySlots`; `TodayPosts(posts)` (`isEmpty`, `pending`);
  `ContentReport` (below).

### Reading (`ref.watch(provider)` → `AsyncValue`)

| Provider | Value |
|---|---|
| `watchNotesProvider(NoteFilter)` | `List<NoteView>` pinned first, then newest. `NoteFilter.all` (Semua, not archived), `NoteFilter.label(id, search:)`, `NoteFilter.archive`, `NoteFilter(search: 'kopi', archived: null)` (search everywhere). Search = every word must appear in title/body/checklist/transcripts/link titles (SQL, fast). |
| `watchNoteProvider(id)` | `NoteView?` (editor) |
| `watchNoteLabelsProvider` / `watchNoteTabsProvider` | all labels in order / only `pinnedTab` ones (the "Semua" tab is yours) |
| `watchIdeaInboxProvider` | `List<Note>` labelled Ide Konten, not archived, not converted yet |
| `watchSocialAccountsProvider` / `watchAllSocialAccountsProvider` | accounts in order without / with archived |
| `watchContentPillarsProvider` | `List<ContentPillar>` in order |
| `watchContentBoardProvider(ContentFilter(accountId:, pillar:, format:, search:))` | `ContentBoard`; `ContentFilter.all` |
| `watchContentItemProvider(id)` | `ContentItemView?` (posts in account order + source note) |
| `watchContentPostProvider(id)` | `ContentPostView?` — the target of reminder taps `/content/posts/<id>` |
| `watchContentCalendarProvider((from:, to:))` | `ContentCalendar`; ranges: `weekRange(day)`, `monthGridRange(YearMonth(y, m))` (Monday-first grid) |
| `watchTodayPostsProvider` | `TodayPosts` for the home card "Tayang hari ini" (hide when `isEmpty`) |
| `watchMetricsDueProvider` | `List<ContentPostView>` posted ≥ 3 days ago without metrics ("Isi performa?") |
| `watchContentReportProvider((from:, to:))` | `ContentReport`: `totals` (posted/scheduled/skipped/views/engagement), `accounts` (`AccountReport`: `posted`, `target`, `expected` = round(target × days / 7), `ratio`, `weeksMet`/`weeks` (full ISO weeks in range), `longestStreak`, `currentStreak`), `bestByViews`/`bestByEngagement` (top 5 `ContentPostView`), `byPillar` (also the balance chart: `posts`, `share`), `byFormat`, `byWeekday`, `byHour` (`ContentGroupStat`: `key`, `label`, `posts`, `withMetrics`, `avgViews`, `avgEngagement`, `avgRate`), `sponsors` (`SponsorSummary`: `byMonth` `SponsorMonth('YYYY-MM', amount, count)`, `byAccount`, `unpaid` `SponsorDue(item, sponsor, overdue)`, `paidTotal`; not range-bound) |
| `watchRemindersProvider` | now tasks **and** scheduled posts with `remindBefore` (`[IG-TAYANG] <title>`, body `Hari ini 19.00 · @handle`, route `/content/posts/<id>`, key `content-post-<id>`), ≤ 60 total, soonest first — already wired to notifications |

### Writing (`await ref.read(provider)(…)` → `Result<T>`)

| Provider → call | Notes |
|---|---|
| `createNoteProvider(NoteInput(title:, body:, checklist:, labelIds:, color:, pinned:, archived:, photos:, audio:, links:, source:))` → `Note` | A blank note → `ValidationFailure(field: 'empty')` (discard it on back). `photos`/`audio`: `TransactionPhoto.local(path)` / `NoteAudio.local(path, durationSec:, transcript:)`. Errors carry `field`: title, body, checklist, labels, color, photos, audio. |
| `createNoteFromShareProvider(SharedNoteInput(text:, subject:, imagePaths:))` → `Note` | Android share target (`source = share`); then offer label / convert |
| `updateNoteProvider(id, NoteInput)` → `Note` | full save (editor); `photos`/`audio`/`links` null = unchanged; body URLs synced into `links` |
| `deleteNoteProvider(id)` | real delete (confirm); archive is the soft option |
| `setNotePinnedProvider(id, bool)`, `setNoteArchivedProvider(id, bool)` (archiving unpins), `setNoteColorProvider(id, 'red'…/null)` | |
| `setNoteLabelsProvider(id, [ids])`, `toggleNoteLabelProvider(id, labelId)` | ≤ 20 labels |
| `setNoteChecklistProvider(id, items)`, `toggleNoteChecklistItemProvider(id, itemId)` | edit with the pure ops `checklistAdd(items, text, id: newId())` (empty text allowed), `checklistToggle`, `checklistSetText`, `checklistRemove`, `checklistMove(from, to)`, `checklistReorder(ids)`, `checklistClearDone`, `checklistUncheckAll` |
| `addNotePhotosProvider(id, [paths])`, `removeNotePhotoProvider(id, photo)`, `setNotePhotosProvider(id, photos)` | ≤ 10; compress like transaction photos |
| `addNoteAudioProvider(id, NoteAudioInput(path:, durationSec:, transcript:))`, `removeNoteAudioProvider(id, clip)`, `setNoteAudioTranscriptProvider(id, clip, text?)`, `insertTranscriptIntoBodyProvider(id, clip)` | ≤ 5 clips, ≤ 610 s; the recorder's `.m4a` is copied into app storage and uploads on sync |
| `createNoteLabelProvider(NoteLabelInput(name:, color:, pinnedTab:))`, `updateNoteLabelProvider(id, input)`, `setNoteLabelPinnedTabProvider(id, bool)`, `reorderNoteLabelsProvider([ids])`, `deleteNoteLabelProvider(id)` | delete strips the label from every note (confirm) |
| `seedDefaultNoteLabelProvider(userId)` / `seedDefaultContentPillarsProvider(userId)` → count | call when Notes / Content opens: offline fallback only — a no-op once a pull from the (notes-aware) server succeeded, since the server seeds them once and never re-creates deleted ones |
| `convertNoteToTaskProvider(noteId, NoteTaskInput(areaId:, bucket:, title:, dueDate:, dueTime:, remindBefore:))` → `(note:, task:)` | title = note title/first line, task note = body as plain text; sets `linkedTaskId` |
| `convertNoteToContentProvider(noteId, format:, pillar:, title:)` → `(note:, item:)` | "Jadikan konten": item at `ide`, idea = body, checklist + photos copied, `noteId`; sets `linkedContentId`; idempotent |
| `noteTransactionDraft(note)` (pure) then `convertNoteToTransactionProvider(noteId, TransactionInput(…, photos: draft.photos))` → `(note:, transaction:)` | draft: `amount` (the single `Rp …`/number via `parseAmount`, else null → ask), `note` = title, `photos` = first 5. Or save the form yourself and call `linkNoteTransactionProvider(noteId, txId)` |
| `createSocialAccountProvider(SocialAccountInput(platform:, handle:, platformName:, color:, targetPerWeek:))`, `updateSocialAccountProvider(id, input)`, `setSocialAccountArchivedProvider(id, bool)`, `reorderSocialAccountsProvider([ids])`, `deleteSocialAccountProvider(id)` | color null = platform default; target 1–50 (0/null = none); delete also deletes its posts |
| `createContentPillarProvider(ContentPillarInput(name:, color:))`, `updateContentPillarProvider(id, input)` (rename renames items), `reorderContentPillarsProvider([ids])`, `deleteContentPillarProvider(id)` (items lose the pillar) | names unique case-insensitively |
| `createContentItemProvider(ContentItemInput(title:, stage:, format:, pillar:, idea:, checklist:, photos:, assetLinks:, sponsor: SponsorInput(brand:, amount:, currency:, due:, paid:)))`, `updateContentItemProvider(id, input)` (`photos` null = unchanged; sponsor null keeps it unless `keepSponsor: false`), `deleteContentItemProvider(id)` (+ its posts) | |
| `moveContentStageProvider(id, stage)` | board drag, any direction |
| `setContentChecklistProvider`, `toggleContentChecklistItemProvider`, `addContentPhotosProvider`, `removeContentPhotoProvider`, `setContentPhotosProvider`, `setContentSponsorProvider(id, SponsorInput?)` | same patterns as notes |
| `markSponsorPaidProvider(itemId, record: SponsorPayment(walletId:, amount:, categoryId:, date:, note:)?)` → `(item:, transaction:)` | with `record`: income transaction `Endorse <brand>` (income category only) linked as `sponsor.transactionId` — never twice; `markSponsorUnpaidProvider(id)` |
| `createContentPostProvider(itemId, ContentPostInput(accountId:, caption:, hashtags:, scheduledAt:, remindBefore:, url:))` | one post per account (`ValidationFailure(field: 'accountId')`); `scheduledAt` → `scheduled` else `draft` |
| `updateContentPostProvider(id, input)`, `scheduleContentPostProvider(id, at, remindBefore:)`, `markPostPostedProvider(id, postedAt:, url:)` ("Sudah tayang"), `markPostSkippedProvider(id)`, `reopenContentPostProvider(id)`, `setPostMetricsProvider(id, PostMetrics(…))`, `deleteContentPostProvider(id)` | post changes auto-advance the item (`autoStage`: any scheduled → `terjadwal`, all non-skipped posted → `tayang`; never backwards) |

Pure helpers: `extractUrls`, `mergeLinks`, `parseAmount`, `noteMatches`, `firstLine`,
`stripMarkdown`, `bodyExcerpt`, `noteActionTitle`, `findIdeaLabel`, `defaultLabelId`,
`autoStage`, `stageXp`, `weekStartOf`, `weekRange`, `monthGridRange`, `needsMetricsPrompt`,
`engagementRate`, `postNotificationTitle`, `platformUrl`, `otherPlatformCode`,
`noteRoute(id)` (`/notes/<id>`), `contentItemRoute(id)` (`/content/<id>`),
`contentPostRoute(id)` (`/content/posts/<id>` — reminder taps; add this route).

Uploads: pending photos (image) and clips (audio) upload before the push; a file the
server refuses (4xx), that is missing, or that comes back as the wrong kind is dropped
with a message in `syncStatusProvider.lastError` (a dropped clip's transcript is
appended to the note body); network/5xx errors retry with backoff.

Tests that override the game's source repositories must also override
`contentItemRepositoryProvider`, `contentPostRepositoryProvider` and
`socialAccountRepositoryProvider` (e.g. with the fakes in `test/domain/fakes.dart`) —
the activity stream and the reminders read them.
