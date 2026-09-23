import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/domain/game/game.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';

void main() {
  late StreamController<List<ActivityEvent>> events;
  late StreamController<List<BudgetStatus>> budgets;
  late InMemoryGameStore store;
  late FixedClock clock;
  late ProviderContainer container;

  final now = DateTime(2026, 9, 10, 14);
  final today = GameDate.fromDateTime(now);

  ActivityEvent tx(GameDate d, String id) => ActivityEvent.transaction(
    id: id,
    createdAt: d.toLocalDateTime().add(const Duration(hours: 9)),
  );

  setUp(() {
    events = StreamController.broadcast();
    budgets = StreamController.broadcast();
    store = InMemoryGameStore();
    clock = FixedClock(now);
    container = ProviderContainer(
      overrides: [
        activityEventsSourceProvider.overrideWith((ref) => events.stream),
        budgetStatusSourceProvider.overrideWith((ref) => budgets.stream),
        gameStoreProvider.overrideWithValue(store),
        gameClockProvider.overrideWithValue(clock),
        gameTickProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(() {
      container.dispose();
      events.close();
      budgets.close();
    });
  });

  Future<GameSummary> summary() async {
    final sub = container.listen(gameSummaryProvider, (_, _) {});
    addTearDown(sub.close);
    return container.read(gameSummaryProvider.future);
  }

  Future<void> emit(
    List<ActivityEvent> e, [
    List<BudgetStatus> b = const [],
  ]) async {
    // Keep the providers alive so they subscribe before we emit.
    container.listen(gameSummaryProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    events.add(e);
    budgets.add(b);
    await Future<void>.delayed(Duration.zero);
  }

  test('summary derives from the source providers', () async {
    await emit([tx(today.addDays(-1), 'a'), tx(today, 'b')]);
    final s = await summary();
    expect(s.streak.current, 2);
    expect(s.totalXp, 20);
    expect(s.hearts.current, 5);
    expect(s.goal.level, DailyGoalLevel.reguler);
  });

  test('first run reconciliation is persisted', () async {
    await emit([tx(today, 'a')]);
    await summary();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final saved = GameLocalState.decode(
      store.values[GameLocalState.storageKey],
    );
    expect(saved.lastSeenLevel, 1);
    expect(saved.seenAchievements, contains('first_transaction'));
  });

  test('actions persist and update the summary', () async {
    await emit([tx(today, 'a')]);
    await summary();
    final actions = container.read(gameActionsProvider);
    await actions.setDailyGoal(DailyGoalLevel.santai);
    final s = await summary();
    expect(s.goal.level, DailyGoalLevel.santai);
    expect(s.goal.isMet, isTrue);
    expect(
      await container.read(dailyGoalLevelProvider.future),
      DailyGoalLevel.santai,
    );

    await actions.completeOnboarding();
    expect(await container.read(onboardingDoneProvider.future), isTrue);
    final saved = GameLocalState.decode(
      store.values[GameLocalState.storageKey],
    );
    expect(saved.onboardingDone, isTrue);
    expect(saved.currentGoal, DailyGoalLevel.santai);
  });

  test('new achievement after first run can be marked seen', () async {
    await emit([]);
    await summary();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    events.add([tx(today, 'a')]);
    await Future<void>.delayed(Duration.zero);
    var a = await container.read(achievementsProvider.future);
    expect(a.newlyUnlocked.map((e) => e.id), contains('first_transaction'));
    await container.read(gameActionsProvider).markAllAchievementsSeen();
    a = await container.read(achievementsProvider.future);
    expect(a.newlyUnlocked, isEmpty);
  });

  /// Plays [id] to the end: first answer wrong once, everything else right.
  Future<LessonResult> playLesson(ProviderContainer c, String id) async {
    final controller = c.read(lessonSessionProvider(id).notifier);
    LessonResult? result;
    var first = true;
    while (!c.read(lessonSessionProvider(id)).requireValue.isFinished) {
      final s = c.read(lessonSessionProvider(id)).requireValue;
      final answer = first
          ? const ChoiceAnswer(-1)
          : _correct(s.currentQuestion);
      first = false;
      final fb = controller.submit(answer);
      expect(fb.explanation, isNotEmpty);
      result = await controller.next() ?? result;
    }
    return result!;
  }

  test('lesson session flow records the completion once', () async {
    final sub = container.listen(lessonSessionProvider('u1l1'), (_, _) {});
    addTearDown(sub.close);
    await container.read(lessonSessionProvider('u1l1').future);
    final result = await playLesson(container, 'u1l1');
    expect(result.mistakes, 1);
    expect(result.practice, isFalse);

    final path = await container.read(learnPathProvider.future);
    expect(path.lessonById('u1l1')!.isCompleted, isTrue);
    expect(path.nextLesson!.lesson.id, 'u1l2');
    final local = await container.read(gameLocalStateProvider.future);
    expect(local.lessonCompletions.length, 1);
    expect(local.lessonCompletions.single.xp, result.xp);

    // Replaying is practice.
    container.read(lessonSessionProvider('u1l1').notifier).restart();
    expect(
      container.read(lessonSessionProvider('u1l1')).requireValue.practice,
      isTrue,
    );
  });

  test('replay is practice even when progress was not loaded yet', () async {
    // Finish the lesson once; progress is persisted to the store.
    final sub = container.listen(lessonSessionProvider('u1l1'), (_, _) {});
    addTearDown(sub.close);
    await container.read(lessonSessionProvider('u1l1').future);
    final first = await playLesson(container, 'u1l1');
    expect(first.practice, isFalse);

    // Cold start: the lesson screen is the first thing to read progress.
    final cold = ProviderContainer(
      overrides: [
        gameStoreProvider.overrideWithValue(store),
        gameClockProvider.overrideWithValue(clock),
        gameTickProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(cold.dispose);
    final coldSub = cold.listen(lessonSessionProvider('u1l1'), (_, _) {});
    addTearDown(coldSub.close);
    expect(cold.read(gameLocalStateProvider).hasValue, isFalse);
    final session = await cold.read(lessonSessionProvider('u1l1').future);
    expect(session.practice, isTrue);

    final replay = await playLesson(cold, 'u1l1');
    expect(replay.practice, isTrue);
    expect(replay.xp, lessThan(first.xp));
    expect(
      replay.xp,
      XpRules.lessonXp(mistakes: replay.mistakes, practice: true),
    );
  });

  test('streak calendar provider', () async {
    await emit([tx(today, 'a')]);
    final sub = container.listen(
      streakCalendarProvider(const GameMonth(2026, 9)),
      (_, _) {},
    );
    addTearDown(sub.close);
    final cal = await container.read(
      streakCalendarProvider(const GameMonth(2026, 9)).future,
    );
    expect(cal[9].status, StreakDayStatus.logged);
  });

  test('unwired sources report a clear error', () async {
    final bare = ProviderContainer(
      overrides: [gameStoreProvider.overrideWithValue(InMemoryGameStore())],
    );
    addTearDown(bare.dispose);
    final sub = bare.listen(gameSummaryProvider, (_, _) {});
    addTearDown(sub.close);
    await expectLater(
      bare.read(gameSummaryProvider.future),
      throwsA(isA<UnimplementedError>()),
    );
  });
}

QuestionAnswer _correct(Question q) => switch (q) {
  MultipleChoiceQuestion(:final correctIndex) => ChoiceAnswer(correctIndex),
  FillBlankQuestion(:final correctIndex) => ChoiceAnswer(correctIndex),
  TrueFalseQuestion(:final answer) => BoolAnswer(answer),
  NumericQuestion(:final answer) => NumericAnswer(answer),
  MatchPairsQuestion(:final pairs) => PairsAnswer({
    for (var i = 0; i < pairs.length; i++) i: i,
  }),
  OrderStepsQuestion(:final steps) => OrderAnswer([
    for (var i = 0; i < steps.length; i++) i,
  ]),
};
