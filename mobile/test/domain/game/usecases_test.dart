import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';

void main() {
  final today = GameDate(2026, 9, 10);

  LessonResult result(String id, {int mistakes = 0, bool practice = false}) =>
      LessonResult(
        lessonId: id,
        practice: practice,
        totalQuestions: 5,
        correctFirstTry: 5 - mistakes,
        mistakes: mistakes,
        xp: XpRules.lessonXp(mistakes: mistakes, practice: practice),
      );

  test('CompleteLesson records the completion', () {
    final s = const CompleteLesson()(
      const GameLocalState(),
      result('u1l1'),
      DateTime(2026, 9, 10),
    );
    expect(s.lessonCompletions.single.xp, 20);
    expect(s.lessonCompletions.single.practice, isFalse);
    expect(s.isLessonCompleted('u1l1'), isTrue);
  });

  test('CompleteLesson downgrades a repeat run to practice XP', () {
    var s = const CompleteLesson()(
      const GameLocalState(),
      result('u1l1'),
      DateTime(2026, 9, 10),
    );
    s = const CompleteLesson()(s, result('u1l1'), DateTime(2026, 9, 11));
    expect(s.lessonCompletions.last.practice, isTrue);
    expect(
      s.lessonCompletions.last.xp,
      XpRules.lessonXp(mistakes: 0, practice: true),
    );
  });

  test('SetDailyGoal keeps history and replaces same-day changes', () {
    var s = const SetDailyGoal()(
      const GameLocalState(),
      DailyGoalLevel.santai,
      today.addDays(-3),
    );
    s = const SetDailyGoal()(s, DailyGoalLevel.serius, today);
    s = const SetDailyGoal()(s, DailyGoalLevel.intens, today);
    expect(s.dailyGoalHistory.length, 2);
    expect(s.currentGoal, DailyGoalLevel.intens);
    expect(
      goalLevelOn(today.addDays(-1), s.dailyGoalHistory),
      DailyGoalLevel.santai,
    );
  });

  test('freezes, seen flags, onboarding', () {
    var s = const GrantStreakFreeze()(const GameLocalState(), today);
    s = const RecordUsedFreezes()(s, [today.addDays(-1)]);
    s = const MarkAchievementsSeen()(s, ['a', 'b']);
    s = const CompleteOnboarding()(
      s,
      goal: DailyGoalLevel.serius,
      today: today,
    );
    expect(s.grantedFreezes, [today]);
    expect(s.usedFreezeDays, {today.addDays(-1)});
    expect(s.seenAchievements, {'a', 'b'});
    expect(s.onboardingDone, isTrue);
    expect(s.currentGoal, DailyGoalLevel.serius);
  });

  test('AcknowledgeCelebrations prunes old keys', () {
    final s = const AcknowledgeCelebrations()(
      const GameLocalState(celebrated: {'goal:2026-01-01', 'goal:2026-09-09'}),
      const GameCelebrations(dailyGoalMet: true),
      today,
    );
    expect(s.celebrated, {'goal:2026-09-09', 'goal:2026-09-10'});
  });

  test('GameLocalState JSON round-trip', () async {
    final state = GameLocalState(
      lessonCompletions: [
        LessonCompletion(
          lessonId: 'u1l1',
          at: DateTime(2026, 9, 10, 8, 30),
          xp: 20,
          accuracy: 0.8,
          perfect: false,
          practice: true,
        ),
      ],
      dailyGoalHistory: [DailyGoalChange(today, DailyGoalLevel.intens)],
      usedFreezeDays: {today},
      grantedFreezes: [today, today],
      seenAchievements: const {'x'},
      lastSeenLevel: 4,
      celebrated: const {'goal:2026-09-10'},
      onboardingDone: true,
    );
    final repo = GameStateRepository(InMemoryGameStore());
    await repo.save(state);
    final back = await repo.load();
    expect(back.toJson(), state.toJson());
    expect(back.lessonCompletions.single.at, DateTime(2026, 9, 10, 8, 30));
    await repo.clear();
    expect((await repo.load()).lessonCompletions, isEmpty);
  });

  test('corrupt storage falls back to a fresh state', () {
    expect(GameLocalState.decode('{not json').onboardingDone, isFalse);
    expect(GameLocalState.decode(null).lessonCompletions, isEmpty);
    final partial = GameLocalState.decode(
      '{"dailyGoalHistory":[{"from":"bad","level":"x"}]}',
    );
    expect(partial.dailyGoalHistory, isEmpty);
  });
}
