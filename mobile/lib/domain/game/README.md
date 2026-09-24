# Ghina gamification engine

The engine turns synced activity (transactions, prayers, health, food, budgets) plus a
small amount of local-only progress into XP, levels, streaks, a daily goal, hearts, the
mascot's mood and message, achievements, and the Duolingo-style learning path.

| Layer | Path | Contents |
|---|---|---|
| domain (pure Dart) | `lib/domain/game/` | engine, content, use cases, the `GameStore` interface. Import the barrel `game.dart`. |
| data | `lib/data/game/shared_prefs_game_store.dart` | `SharedPrefsGameStore implements GameStore` |
| presentation | `lib/presentation/state/game/game_providers.dart` | Riverpod providers and actions |

**Design rule:** anything that can be derived from synced data is derived, so results
match across devices and survive a reinstall. Only true local state is persisted, as a
single JSON blob `ghina.game.state.v1` (`GameLocalState`). That covers:

- lesson completions
- daily-goal history
- used and granted streak freezes
- seen achievements
- last seen level
- celebrated keys
- the onboarding flag
- "FIRE kosong" days (local snapshot, see below)

## Wiring (composition root `lib/di/`)

Presentation never imports data, so `lib/di/` overrides the providers below.
Anything left unwired throws `UnimplementedError` with a pointer to this file.

| Provider (from `presentation/state/game/game_providers.dart`) | Type | Wire to |
|---|---|---|
| `activityEventsSourceProvider` | `StreamProvider<List<ActivityEvent>>` | all transactions, prayers, health and food rows mapped to `ActivityEvent` |
| `budgetStatusSourceProvider` | `StreamProvider<List<BudgetStatus>>` | every `Budget` row (all months) with that category's expense total for that month |
| `gameStoreProvider` | `Provider<GameStore>` | `SharedPrefsGameStore()` |
| `gameClockProvider` (optional) | `Provider<Clock>` | defaults to `SystemClock()` from `core/clock.dart` |
| `gameUserNameProvider` (optional) | `Provider<String?>` | the user's first name, used in mascot lines |
| `learnUnitsProvider` (optional) | `Provider<List<LearnUnit>>` | defaults to the built-in `learnUnits` |
| `gameTickProvider` (optional) | `StreamProvider<int>` | emits when the hour changes, to refresh the day and the mascot. In tests, override it with `Stream.empty()`. |

```dart
// lib/di/game_overrides.dart (example; repository names are illustrative)
final gameOverrides = [
  gameStoreProvider.overrideWithValue(SharedPrefsGameStore()),
  activityEventsSourceProvider.overrideWith((ref) {
    final txs = ref.watch(transactionRepositoryProvider).watchAll();
    final prayers = ref.watch(prayerRepositoryProvider).watchAll();
    final health = ref.watch(healthRepositoryProvider).watchAll();
    final food = ref.watch(foodRepositoryProvider).watchAll();
    return combineLatest4(txs, prayers, health, food, (t, p, h, f) => [
      for (final x in t) ActivityEvent.transaction(
          id: x.id, createdAt: x.createdAt, type: TxKind.parse(x.type.name),
          amount: x.amount, date: x.date),
      for (final x in p) ActivityEvent.prayer(
          id: x.id, date: GameDate.tryParse(x.date)!, prayer: x.prayer, createdAt: x.createdAt),
      for (final x in h) ActivityEvent.health(
          id: x.id, createdAt: x.createdAt, date: x.date, hasWeight: x.weight != null),
      for (final x in f) ActivityEvent.food(id: x.id, createdAt: x.createdAt, date: x.date),
    ]);
  }),
  budgetStatusSourceProvider.overrideWith((ref) =>
      ref.watch(budgetRepositoryProvider).watchAllWithSpent().map((rows) => [
        for (final r in rows) BudgetStatus(categoryId: r.categoryId, categoryName: r.categoryName,
            year: r.year, month: r.month, budget: r.amount, spent: r.spent),
      ])),
];
// ProviderScope(overrides: [...gameOverrides], child: App())
```

**Task completions** (`docs/tasks.md` → Gamification) come in through
`activityEventsSourceProvider`: one `ActivityEvent.task` per task that is currently done
(un-completing removes it, so everything below is derived). Shape: `kind == ActivityKind.task`,
`id` = task id, `at` = `doneAt` (so `day` = local day of `doneAt`), `occurredAt` = task
`createdAt`, `taskBucket` = `fire|want|should`, `taskSeriesId`, `taskAreaId`.

- XP fire 10 / want 8 / should 5 (`XpRules.taskXp`, `XpSource.task`), at most 20 tasks per
  day (`XpRules.taskDailyCap`, earliest `doneAt` first). Counted tasks count toward the
  daily goal. They never touch the transaction streak.
- Achievements: `first_task`, `fire_tasks_10`, `tasks_100`, `series_10` (one recurring
  series done 10 times), `fire_clear_7` ("FIRE kosong" 7 times).
- **FIRE kosong** can't be derived from done events, so it's a local daily snapshot
  (`fire_clear.dart`, `GameLocalState.fireClearDays`, `RecordFireClearDay`).
  `fireClearRecorderProvider` (`presentation/state/game/task_game_providers.dart`, kept
  alive by Beranda) evaluates *yesterday* on the first open of a day and whenever the hour
  tick crosses midnight. A day counts when every FIRE task of that day's focus areas
  (unscheduled areas plus those scheduled on that weekday) that existed and was due by the
  end of the day was done by then, and at least one of them was completed that day.
  Records are add-only. Limitations: only days followed by a day the app ran are
  recorded. Deleted or re-bucketed tasks and schedule changes are not seen. The snapshot
  is per device and not synced.
- Mascot: `homeMascotProvider` re-runs the mascot with task info
  (`MascotContext.withTasks`). With 3 or more overdue tasks it shows a worried nudge, and it
  adds lines for open FIRE tasks and for FIRE kosong.

**Content planner milestones** (`docs/content.md` → Gamification) also come in through
`activityEventsSourceProvider` (mapped by `contentActivityEventsFrom` in
`lib/di/game_overrides.dart`), `kind == ActivityKind.content`. Everything is
derived (removing the underlying state removes the event); `id`s are stable, so the
engine's `kind:id` dedupe works. `contentType` (`ContentEventType`) tells them apart:

| `contentType` | One event per | `id` | `at` (the XP day) | Other fields |
|---|---|---|---|---|
| `stage` | item × stage reached after `ide`, up to its current stage | `<itemId>:<stage>` | when the stage was first reached (`stageReachedAt`, see below) | `contentItemId`, `contentStage` (`naskah…tayang`), `contentStageXp` (3/4/5/6/10 — the shared table, `stageXp`), `occurredAt` = item `createdAt` |
| `posted` | posted post with `postedAt` | post id | `postedAt` | `contentItemId`, `contentAccountId`, `contentPlatform` (wire id), `contentOnSchedule` (posted on/before the scheduled local day), `occurredAt` = `scheduledAt` |
| `weeklyTarget` | account × ISO week where posted ≥ `targetPerWeek` | `<accountId>:<Monday YYYY-MM-DD>` | `postedAt` of the post that reached the target | `contentAccountId`, `contentPlatform`, `contentWeekStart` (`GameDate`), `contentTarget`; XP constant `weeklyTargetXp` = 20 |
| `sponsorPaid` | item whose sponsor is paid | item id | the linked income transaction's `createdAt`, else the item's `updatedAt` | `contentItemId`, `amount` |

Rules (`XpRules`, `XpCalculator._content`):
- `stage`: its `contentStageXp` (naskah 3, produksi 4, siap 5, terjadwal 6, tayang 10;
  `XpSource.contentStage`). `posted`: +5 when `contentOnSchedule`
  (`XpSource.contentOnSchedule`). Stage + posted events count toward the daily goal, at
  most 20 a day (`XpRules.contentDailyCap`, earliest first) — dummy items can't farm XP.
- `weeklyTarget`: +20 (`XpSource.contentWeeklyTarget`); `sponsorPaid`: +15
  (`XpSource.contentSponsor`). Bonuses: no daily-goal activity, no cap.
- Never part of the (transaction) streak.
- Achievements: `first_content_post` (Tayang Perdana, 1 posted), `content_consistency_4`
  (Kreator Konsisten, 4 consecutive `contentWeekStart`s of one account),
  `content_posts_50` (Mesin Konten), `first_sponsor` (Endorse Pertama).
- Notes created are **not** XP (no event).

Limitation — per-stage timestamps: the synced model has none, so the device keeps a local
`stageReachedAt` log (drift `content_items.stage_log`, never synced). A stage reached on
this device is stamped with the edit time; a stage first seen through a pull (another
device / the web, a reinstall, a full re-pull after an epoch change) gets that row's
`updatedAt` — so stages reached elsewhere land on the day the item was last updated there,
and several stages skipped at once share one time. Once recorded, a stage's time never
changes (moving back and forth can't re-farm XP); moving an item back hides the later
stage events until it reaches them again (with their original time).

The source streams should emit their current value on subscribe (drift `watch()` streams
do this). Exclude soft-deleted rows. XP, the streak and the daily goal are counted on the
**local day of `createdAt`**, not the transaction `date`, so backfilled history can't farm
XP. Monthly stats (savings rate) use `date`. Prayers count on their own `YYYY-MM-DD` date.

## Public API (presentation providers)

| Provider | Type | Notes |
|---|---|---|
| `gameSummaryProvider` | `FutureProvider<GameSummary>` | `totalXp`, `xpToday`, `xp` (`XpLedger`: per-day breakdown and `history(count:)`), `level` (`LevelInfo`: level, title, progress, xpToNext, nextTitle), `streak` (`StreakResult`), `goal` (`DailyGoalProgress`), `hearts` (`HeartsState`), `mood` (`MascotMood`), `message`, `celebrations` |
| `achievementsProvider` | `FutureProvider<AchievementsState>` | `items` (`AchievementProgress`: def, current/target, fraction, unlocked, isNew), `newlyUnlocked`, `unlockedCount` |
| `learnPathProvider` | `FutureProvider<LearnPathProgress>` | units → lessons with status (locked, available or completed), stars 0–3, bestAccuracy, perfect, `nextLesson`. It depends only on local state. |
| `lessonSessionProvider(lessonId)` | `AsyncNotifierProvider.autoDispose.family<LessonSessionController, LessonSession, String>` | Loading until saved progress is read, so a replay of a completed lesson always starts as practice. `submit(answer)` returns a `LessonFeedback`. After the last question, `next()` returns `Future<LessonResult?>`, records the completion once, and returns the result. `restart()` starts the lesson again. |
| `streakCalendarProvider(GameMonth)` | `FutureProvider.family<List<CalendarDay>, GameMonth>` | each day is logged, frozen, missed, pending or none |
| `dailyGoalLevelProvider`, `onboardingDoneProvider` | `FutureProvider` | local settings |
| `gameSnapshotProvider` | `FutureProvider<GameSnapshot>` | everything above in one object |
| `gameActionsProvider` | `Provider<GameActions>` | see the list below |

`GameActions`:

- `completeLesson(result)`
- `setDailyGoal(level)`
- `markAchievementsSeen(ids)`
- `markAllAchievementsSeen()`
- `earnFreeze()`
- `consumeFreezes(days)`
- `acknowledgeCelebrations(c)`
- `completeOnboarding({goal})`
- `resetLocalProgress()`

`gameSnapshotProvider` records freezes the streak simulation has consumed automatically,
so the streak stays stable if data later changes. On the very first run it also sets a
baseline: it stores the current level and marks already-unlocked achievements as seen, so
a user who has years of web history isn't flooded with pop-ups.

### Answering questions (`lib/domain/game/learn/learn_models.dart`)

| Question | Answer |
|---|---|
| `MultipleChoiceQuestion`, `FillBlankQuestion` (prompt contains `___`) | `ChoiceAnswer(index)` |
| `TrueFalseQuestion` | `BoolAnswer(bool)` |
| `MatchPairsQuestion` | `PairsAnswer({leftIndex: rightIndex})`. Shuffle the right column in the UI and map back to the original indices. |
| `OrderStepsQuestion` (steps are stored in the correct order) | `OrderAnswer([originalIndices in chosen order])`. Shuffle the steps in the UI. |
| `NumericQuestion` (`prefix` or `suffix`, `tolerance`) | `NumericAnswer(num)` |

Every question has an `explanation` and a `correctAnswerText` for the feedback sheet. A
wrong answer is re-queued at the end of the lesson, at most twice per question. A lesson
can't be failed: mistakes only reduce XP.

## Rules (tunable in `xp_rules.dart`)

**XP per activity:**
- Transaction: +10 XP, counting at most 15 per day.
- Prayer (docs/prayer-quality.md): each fardhu = its status points (masjid 10, jamaah 8, ontime 6, late 3, qadha 1, missed/excused 0); each rawatib +2; each daily sunnah (dhuha/tahajud/witir) +3; +15 bonus when all 5 fardhu of a day are prayed. Missed/excused rows don't count toward the daily goal.
- Balance adjustments are not activity (no XP, streak or daily goal).
- Health: +5 XP, at most 3 per day.
- Food: +5 XP, at most 6 per day.
- Task: fire 10 / want 8 / should 5 XP by `doneAt` day, at most 20 per day.
- Content: stage reached 3/4/5/6/10, posted on schedule +5 (≤ 20 milestones a day),
  weekly target met +20, sponsor paid +15.
- Lesson: 15 XP minus 2 per mistake, with a minimum of 5, plus a +5 bonus for a perfect lesson.
- Practice replay: 5 XP, plus 5 for a perfect replay.
- Daily goal met: +20 XP.
- Streak milestones: 3 days +15, 7 +30, 14 +50, 30 +100, 50 +150, 100 +300, 365 +1000.

**Daily goal:** Santai 1, Reguler 3 (the default), Serius 5 or Intens 8 counted
activities. The goal history is kept, so past days use the goal that applied at the time.

**Levels:** going from level L to L+1 costs `100 + 50·(L−1)` XP. Titles run from *Receh
Pemula* up to *Sultan Bijak* at level 50.

**Streak:** a day counts when at least one transaction was logged (by the local day of
`createdAt`). If today isn't logged yet, the streak stays alive but is flagged as at risk.

**Streak freezes:**
- The user earns one freeze each time the streak reaches a multiple of 7 days, holding at most 2.
- Freezes are used automatically on missed past days, at most 2 days in a row.
- A frozen day keeps the streak alive but doesn't add to its length.

**Hearts:** 5 each month, minus one per category that is over budget this month (never
below 0). `nearLimit` lists categories at 90% or more of their budget.

**Mascot moods:**

| Condition | Mood |
|---|---|
| Streak at risk after 18:00 | `worried` |
| Night (22:00–05:00) | `sleeping` |
| Daily goal met | `celebrating` |
| No hearts left, or streak just lost | `sad` |
| 1 heart or fewer | `worried` |
| 3+ overdue tasks (home, `homeMascotProvider`) | `worried` |
| Nothing logged yet today | `encouraging` |
| Otherwise | `happy` |

The message line is chosen per day and hour, so it doesn't flicker between rebuilds.

## Reward moments the UI should celebrate

`GameSummary.celebrations` (`GameCelebrations`) lists these. In the app, don't show or
acknowledge them by hand: use `presentPendingCelebrations` / `RewardTracker` from
`lib/presentation/shared/rewards/`, the single path that shows each moment once and calls
`acknowledgeCelebrations(celebrations)`.

1. **Daily goal met** (`dailyGoalMet`): full-screen confetti with "+20 XP".
2. **Streak milestone** (`streakMilestone`: 3, 7, 14, 30, 50, 100 or 365 days): a fire
   animation and the bonus XP. At a multiple of 7 days, also mention the new freeze.
3. **Level up** (`levelUp`): the new level and title, plus `nextTitle` teaser.
4. **Achievement unlocked** (`newAchievements`): a badge sheet for each one, with its tier colour.

Also celebrate these moments, which don't go through `GameCelebrations`:

5. **Lesson finished:** the `LessonResult` returned by `next()`. Show XP, accuracy, and a "Sempurna!" badge when `perfect`.
6. **Unit completed:** `learnPathProvider` shows the unit's `isCompleted` flipping to true after a lesson.
7. **Streak saved by a freeze:** today's streak shows a `frozen` status for yesterday.
8. **All 5 prayers logged:** the `prayerBonus` source in `xp.dayOf(today).breakdown`.
