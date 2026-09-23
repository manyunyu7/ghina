import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../domain/game/game.dart';

// ---------------------------------------------------------------------------
// Source providers — override these in the composition root (lib/di/).
// ---------------------------------------------------------------------------

Duration? _noRetry(int retryCount, Object error) => null;

/// All synced activity mapped to [ActivityEvent]s (transactions, prayers,
/// health, food). Must be overridden, e.g. with a repository stream.
final activityEventsSourceProvider = StreamProvider<List<ActivityEvent>>(
  (ref) => throw UnimplementedError(
    'activityEventsSourceProvider is not wired. Override it in lib/di/ '
    '(see lib/domain/game/README.md).',
  ),
  retry: _noRetry,
);

/// Budget vs spent per category per month (all months). Must be overridden.
final budgetStatusSourceProvider = StreamProvider<List<BudgetStatus>>(
  (ref) => throw UnimplementedError(
    'budgetStatusSourceProvider is not wired. Override it in lib/di/ '
    '(see lib/domain/game/README.md).',
  ),
  retry: _noRetry,
);

/// Local key-value store for game progress. Must be overridden with
/// `SharedPrefsGameStore()` from `lib/data/game/` (or [InMemoryGameStore] in tests).
final gameStoreProvider = Provider<GameStore>(
  (ref) => throw UnimplementedError(
    'gameStoreProvider is not wired. Override it with SharedPrefsGameStore() in lib/di/.',
  ),
);

/// Time source (override with `FixedClock` in tests).
final gameClockProvider = Provider<Clock>((ref) => const SystemClock());

/// Optional first name used in mascot messages.
final gameUserNameProvider = Provider<String?>((ref) => null);

/// The learning content (override to test with small fixtures).
final learnUnitsProvider = Provider<List<LearnUnit>>((ref) => learnUnits);

/// Emits whenever the local hour changes (checked every minute), so the day
/// rollover and night-time mascot update without user interaction.
final gameTickProvider = StreamProvider<int>((ref) {
  final clock = ref.watch(gameClockProvider);
  int hourKey() {
    final n = clock.now();
    return ((n.year * 100 + n.month) * 100 + n.day) * 100 + n.hour;
  }

  return Stream<int>.periodic(
    const Duration(minutes: 1),
    (_) => hourKey(),
  ).distinct();
}, retry: _noRetry);

// ---------------------------------------------------------------------------
// Local state
// ---------------------------------------------------------------------------

final gameLocalStateProvider =
    AsyncNotifierProvider<GameLocalStateController, GameLocalState>(
      GameLocalStateController.new,
      retry: _noRetry,
    );

/// Holds [GameLocalState]; every mutation is serialized and persisted.
class GameLocalStateController extends AsyncNotifier<GameLocalState> {
  Future<void> _queue = Future.value();

  GameStateRepository get _repo =>
      GameStateRepository(ref.read(gameStoreProvider));

  @override
  Future<GameLocalState> build() =>
      GameStateRepository(ref.watch(gameStoreProvider)).load();

  /// Apply [change] to the latest state and persist it. Updates run one at a
  /// time so concurrent actions never overwrite each other.
  Future<GameLocalState> apply(GameLocalState Function(GameLocalState) change) {
    final completer = Completer<GameLocalState>();
    _queue = _queue.then((_) async {
      try {
        final current = state.value ?? await future;
        final next = change(current);
        if (!identical(next, current)) {
          if (ref.mounted) state = AsyncData(next);
          await _repo.save(next);
        }
        completer.complete(next);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Fold derived facts (used freezes, first-run baselines) into local state.
  void reconcile(GameSnapshot snapshot) {
    if (!ref.mounted) return;
    apply((s) => const ReconcileLocalState()(s, snapshot)).ignore();
  }
}

// ---------------------------------------------------------------------------
// Derived state
// ---------------------------------------------------------------------------

/// Whole derived game state. Prefer the narrower providers below in widgets.
final gameSnapshotProvider = FutureProvider<GameSnapshot>((ref) async {
  ref.watch(gameTickProvider);
  // Subscribe to every source before awaiting any of them.
  final eventsF = ref.watch(activityEventsSourceProvider.future);
  final budgetsF = ref.watch(budgetStatusSourceProvider.future);
  final localF = ref.watch(gameLocalStateProvider.future);
  // Avoid unhandled-error reports for futures awaited after an earlier failure.
  budgetsF.ignore();
  localF.ignore();
  final events = await eventsF;
  final budgets = await budgetsF;
  final local = await localF;
  final snapshot = const ComputeGameSnapshot()(
    events: events,
    budgets: budgets,
    local: local,
    now: ref.read(gameClockProvider).now(),
    units: ref.watch(learnUnitsProvider),
    userName: ref.watch(gameUserNameProvider),
  );
  if (snapshot.needsReconcile) {
    final controller = ref.read(gameLocalStateProvider.notifier);
    // After this build: persist used freezes / first-run baselines.
    scheduleMicrotask(() => controller.reconcile(snapshot));
  }
  return snapshot;
}, retry: _noRetry);

/// XP, level, streak, daily goal, hearts, mascot mood + message, celebrations.
final gameSummaryProvider = FutureProvider<GameSummary>(
  (ref) async => (await ref.watch(gameSnapshotProvider.future)).summary,
  retry: _noRetry,
);

/// All achievements with progress; `newlyUnlocked` = unlocked but not seen.
final achievementsProvider = FutureProvider<AchievementsState>(
  (ref) async => (await ref.watch(gameSnapshotProvider.future)).achievements,
  retry: _noRetry,
);

/// Learning path progress. Depends only on local state (works offline and
/// before the data sources emit).
final learnPathProvider = FutureProvider<LearnPathProgress>((ref) async {
  final local = await ref.watch(gameLocalStateProvider.future);
  return LearnPathCalculator.compute(
    ref.watch(learnUnitsProvider),
    local.lessonCompletions,
  );
}, retry: _noRetry);

/// Streak calendar for one month (logged / frozen / missed / pending / none).
final streakCalendarProvider =
    FutureProvider.family<List<CalendarDay>, GameMonth>(
      (ref, month) async => (await ref.watch(
        gameSummaryProvider.future,
      )).streak.month(month.year, month.month),
      retry: _noRetry,
    );

/// Currently selected daily goal.
final dailyGoalLevelProvider = FutureProvider<DailyGoalLevel>(
  (ref) async => (await ref.watch(gameLocalStateProvider.future)).currentGoal,
  retry: _noRetry,
);

/// Whether the onboarding flow was completed on this device.
final onboardingDoneProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(gameLocalStateProvider.future)).onboardingDone,
  retry: _noRetry,
);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

final gameActionsProvider = Provider<GameActions>(GameActions.new);

/// Imperative game actions for the UI. All persist to the [GameStore].
class GameActions {
  GameActions(this._ref);

  final Ref _ref;

  GameLocalStateController get _local =>
      _ref.read(gameLocalStateProvider.notifier);
  DateTime get _now => _ref.read(gameClockProvider).now();
  GameDate get _today => GameDate.fromDateTime(_now);

  /// Record a finished lesson (called automatically by [lessonSessionProvider]).
  Future<void> completeLesson(LessonResult result) =>
      _local.apply((s) => const CompleteLesson()(s, result, _now));

  Future<void> setDailyGoal(DailyGoalLevel level) =>
      _local.apply((s) => const SetDailyGoal()(s, level, _today));

  Future<void> markAchievementsSeen(Iterable<String> ids) {
    final list = ids.toList();
    return _local.apply((s) => const MarkAchievementsSeen()(s, list));
  }

  Future<void> markAllAchievementsSeen() async {
    final achievements = await _ref.read(achievementsProvider.future);
    await _local.apply(
      (s) => const MarkAchievementsSeen().all(s, achievements),
    );
  }

  /// Give the user an extra streak freeze (reward). Max held still applies.
  Future<void> earnFreeze() =>
      _local.apply((s) => const GrantStreakFreeze()(s, _today));

  /// Persist freezes consumed on [days] (done automatically on each summary
  /// computation; exposed for completeness).
  Future<void> consumeFreezes(Iterable<GameDate> days) {
    final list = days.toList();
    return _local.apply((s) => const RecordUsedFreezes()(s, list));
  }

  /// Call after showing the celebrations from [GameSummary.celebrations].
  Future<void> acknowledgeCelebrations(GameCelebrations celebrations) => _local
      .apply((s) => const AcknowledgeCelebrations()(s, celebrations, _today));

  Future<void> completeOnboarding({DailyGoalLevel? goal}) => _local.apply(
    (s) => const CompleteOnboarding()(s, goal: goal, today: _today),
  );

  /// Wipe local game progress (settings → reset local data).
  Future<void> resetLocalProgress() async {
    await GameStateRepository(_ref.read(gameStoreProvider)).clear();
    _ref.invalidate(gameLocalStateProvider);
  }
}

// ---------------------------------------------------------------------------
// Lesson sessions
// ---------------------------------------------------------------------------

/// A running lesson, keyed by lesson id. Auto-disposed when the lesson screen
/// closes. Finishing (the last `next()`) records the completion once.
///
/// Async on purpose: the session starts only after saved game progress has
/// loaded, so replaying an already-completed lesson is always practice (less
/// XP), even when the lesson screen is the first thing that reads progress.
final lessonSessionProvider = AsyncNotifierProvider.autoDispose
    .family<LessonSessionController, LessonSession, String>(
      LessonSessionController.new,
      retry: _noRetry,
    );

class LessonSessionController extends AsyncNotifier<LessonSession> {
  LessonSessionController(this.lessonId);

  final String lessonId;
  bool _recorded = false;

  @override
  Future<LessonSession> build() async {
    final found = findLesson(lessonId, ref.read(learnUnitsProvider));
    if (found == null) {
      throw ArgumentError.value(lessonId, 'lessonId', 'Unknown lesson');
    }
    // read, not watch: recording the completion updates local state and must
    // not restart the running session.
    GameLocalState? local;
    try {
      local = await ref.read(gameLocalStateProvider.future);
    } catch (_) {
      local = null; // Unreadable progress: treat as a first run.
    }
    _recorded = false;
    return LessonSession.start(
      found.lesson,
      practice: local?.isLessonCompleted(lessonId) ?? false,
    );
  }

  LessonSession get _session => state.requireValue;

  /// Check an answer; returns the feedback to show.
  LessonFeedback submit(QuestionAnswer answer) {
    final next = _session.submit(answer);
    state = AsyncData(next);
    return next.feedback!;
  }

  /// Continue after feedback. When the lesson finishes, the result is recorded
  /// (XP etc.) and returned; otherwise returns null.
  Future<LessonResult?> next() async {
    final s = _session.next();
    state = AsyncData(s);
    if (!s.isFinished || _recorded) return null;
    _recorded = true;
    final result = s.result!;
    await ref.read(gameActionsProvider).completeLesson(result);
    return result;
  }

  /// Start over (e.g. "Ulangi" on the result screen).
  void restart() {
    final s = _session;
    final practice = s.practice || _recorded;
    _recorded = false;
    state = AsyncData(LessonSession.start(s.lesson, practice: practice));
  }
}
