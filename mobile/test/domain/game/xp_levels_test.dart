import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';

final today = GameDate(2026, 9, 10);
DateTime at(int day, [int hour = 12]) => DateTime(2026, 9, day, hour);

ActivityEvent tx(int day, {String? id, int hour = 12}) =>
    ActivityEvent.transaction(id: id, createdAt: at(day, hour), amount: 10000);

XpLedger compute(
  List<ActivityEvent> events, {
  List<LessonCompletion> lessons = const [],
  List<DailyGoalChange> goals = const [],
}) {
  final streak = StreakCalculator.compute(
    loggedDays: [
      for (final e in events)
        if (e.kind == ActivityKind.transaction) e.day,
    ],
    today: today,
  );
  return XpCalculator.compute(
    events: events,
    lessons: lessons,
    goalHistory: goals,
    streak: streak,
    today: today,
  );
}

void main() {
  group('XP', () {
    test('transaction XP is capped per day', () {
      final ledger = compute([for (var i = 0; i < 20; i++) tx(10, id: 't$i')]);
      final day = ledger.dayOf(today)!;
      expect(day.transactionsTotal, 20);
      expect(day.transactionsCounted, XpRules.transactionDailyCap);
      expect(
        day.breakdown[XpSource.transaction],
        XpRules.transactionDailyCap * XpRules.transaction,
      );
      // Goal met (default Reguler = 3) adds the bonus.
      expect(day.breakdown[XpSource.dailyGoal], XpRules.dailyGoalMet);
    });

    test('duplicate ids are counted once', () {
      final ledger = compute([tx(10, id: 'a'), tx(10, id: 'a')]);
      expect(ledger.dayOf(today)!.transactionsTotal, 1);
    });

    test('prayers: 5 XP each, dedupe, bonus for all five', () {
      final events = [
        for (final p in prayerNames)
          ActivityEvent.prayer(date: today, prayer: p),
        ActivityEvent.prayer(date: today, prayer: 'subuh'),
        ActivityEvent.prayer(date: today, prayer: 'tahajud'),
      ];
      final day = compute(events).dayOf(today)!;
      expect(day.breakdown[XpSource.prayer], 25);
      expect(day.breakdown[XpSource.prayerBonus], XpRules.allPrayersBonus);
      expect(day.activities, 5);
    });

    test('prayer counts on its own date, not createdAt', () {
      final e = ActivityEvent.prayer(
        date: today.addDays(-1),
        prayer: 'isya',
        createdAt: at(10, 8),
      );
      final ledger = compute([e]);
      expect(ledger.xpOn(today.addDays(-1)), XpRules.prayer);
    });

    test('health and food caps', () {
      final events = [
        for (var i = 0; i < 5; i++) ActivityEvent.health(createdAt: at(10)),
        for (var i = 0; i < 9; i++) ActivityEvent.food(createdAt: at(10)),
      ];
      final day = compute(events).dayOf(today)!;
      expect(
        day.breakdown[XpSource.health],
        XpRules.healthDailyCap * XpRules.health,
      );
      expect(day.breakdown[XpSource.food], XpRules.foodDailyCap * XpRules.food);
    });

    test('lesson XP and daily goal bonus with goal history', () {
      final lessons = [
        LessonCompletion(
          lessonId: 'u1l1',
          at: at(10, 9),
          xp: 20,
          accuracy: 1,
          perfect: true,
          practice: false,
        ),
      ];
      final ledger = compute(
        [tx(9), tx(10)],
        lessons: lessons,
        goals: [DailyGoalChange(today.addDays(-5), DailyGoalLevel.santai)],
      );
      // Day 9: 1 tx, Santai goal met -> 10 + 20.
      expect(ledger.xpOn(today.addDays(-1)), 30);
      // Today: tx 10 + lesson 20 + goal 20.
      expect(ledger.xpToday, 50);
      expect(ledger.activitiesToday, 2);
      expect(ledger.goalDays, 2);
    });

    test('goal not met = no bonus', () {
      final ledger = compute(
        [tx(10)],
        goals: [DailyGoalChange(today, DailyGoalLevel.serius)],
      );
      expect(ledger.dayOf(today)!.goalMet, isFalse);
      expect(ledger.xpToday, 10);
    });

    test('streak milestone bonus is added on the milestone day', () {
      final ledger = compute([tx(8), tx(9), tx(10)]);
      expect(ledger.dayOf(today)!.breakdown[XpSource.streakMilestone], 15);
    });

    test('history returns the last N days oldest first', () {
      final ledger = compute([tx(9), tx(10)]);
      final h = ledger.history(count: 3);
      expect(h.map((e) => e.$1), [today.addDays(-2), today.addDays(-1), today]);
      expect(h.first.$2, 0);
    });

    test('events at 23:59 and 00:01 fall on different days', () {
      final ledger = compute([tx(9, hour: 23), tx(10, hour: 0)]);
      expect(ledger.dayOf(today.addDays(-1))!.transactionsTotal, 1);
      expect(ledger.dayOf(today)!.transactionsTotal, 1);
    });

    test('lesson XP formula', () {
      expect(XpRules.lessonXp(mistakes: 0, practice: false), 20);
      expect(XpRules.lessonXp(mistakes: 2, practice: false), 11);
      expect(
        XpRules.lessonXp(mistakes: 20, practice: false),
        XpRules.lessonMinimum,
      );
      expect(XpRules.lessonXp(mistakes: 0, practice: true), 10);
      expect(XpRules.lessonXp(mistakes: 3, practice: true), 5);
    });
  });

  group('Levels', () {
    test('thresholds increase', () {
      expect(LevelCurve.xpToReach(1), 0);
      expect(LevelCurve.xpToReach(2), 100);
      expect(LevelCurve.xpToReach(3), 250);
      expect(LevelCurve.xpToReach(4), 450);
      for (var l = 2; l < 60; l++) {
        final step = LevelCurve.xpToReach(l + 1) - LevelCurve.xpToReach(l);
        final prev = LevelCurve.xpToReach(l) - LevelCurve.xpToReach(l - 1);
        expect(step, greaterThan(prev));
      }
    });

    test('forXp boundaries and progress', () {
      expect(LevelCurve.forXp(0).level, 1);
      expect(LevelCurve.forXp(99).level, 1);
      expect(LevelCurve.forXp(100).level, 2);
      final info = LevelCurve.forXp(175);
      expect(info.level, 2);
      expect(info.xpIntoLevel, 75);
      expect(info.xpForLevel, 150);
      expect(info.progress, closeTo(0.5, 1e-9));
      expect(info.xpToNext, 75);
      expect(LevelCurve.forXp(-5).level, 1);
    });

    test('titles', () {
      expect(LevelCurve.titleFor(1), 'Receh Pemula');
      expect(LevelCurve.titleFor(2), 'Receh Pemula');
      expect(LevelCurve.titleFor(5), 'Penabung Rajin');
      expect(LevelCurve.titleFor(99), 'Sultan Bijak');
      expect(
        LevelCurve.forXp(LevelCurve.xpToReach(2)).nextTitle,
        'Pencatat Cilik',
      );
      expect(LevelCurve.forXp(0).nextTitle, isNull);
    });
  });

  group('Daily goal', () {
    test('levels and progress', () {
      expect(DailyGoalLevel.values.map((l) => l.target), [1, 3, 5, 8]);
      const p = DailyGoalProgress(level: DailyGoalLevel.serius, done: 2);
      expect(p.remaining, 3);
      expect(p.isMet, isFalse);
      expect(p.fraction, closeTo(0.4, 1e-9));
      const q = DailyGoalProgress(level: DailyGoalLevel.santai, done: 4);
      expect(q.isMet, isTrue);
      expect(q.fraction, 1);
      expect(q.remaining, 0);
    });

    test('goalLevelOn picks the change effective that day', () {
      final history = [
        DailyGoalChange(today.addDays(-10), DailyGoalLevel.santai),
        DailyGoalChange(today.addDays(-2), DailyGoalLevel.intens),
      ];
      expect(goalLevelOn(today.addDays(-20), history), DailyGoalLevel.santai);
      expect(goalLevelOn(today.addDays(-3), history), DailyGoalLevel.santai);
      expect(goalLevelOn(today, history), DailyGoalLevel.intens);
      expect(goalLevelOn(today, const []), DailyGoalLevel.reguler);
    });
  });
}
