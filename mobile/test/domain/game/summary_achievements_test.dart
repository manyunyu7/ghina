import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';

final now = DateTime(2026, 9, 10, 14);
final today = GameDate.fromDateTime(now);

ActivityEvent tx(
  GameDate day, {
  TxKind type = TxKind.expense,
  double amount = 10000,
  String? id,
  DateTime? date,
}) => ActivityEvent.transaction(
  id: id,
  createdAt: day.toLocalDateTime().add(const Duration(hours: 12)),
  type: type,
  amount: amount,
  date: date,
);

GameSnapshot snap(
  List<ActivityEvent> events, {
  List<BudgetStatus> budgets = const [],
  GameLocalState local = const GameLocalState(lastSeenLevel: 1),
  DateTime? at,
}) => const ComputeGameSnapshot()(
  events: events,
  budgets: budgets,
  local: local,
  now: at ?? now,
);

void main() {
  group('Achievements', () {
    test('nothing unlocked for a new user', () {
      final s = snap([]);
      expect(s.achievements.unlockedCount, 0);
      expect(s.achievements.total, greaterThanOrEqualTo(25));
      final ids = achievementDefs.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('first transaction + first transfer unlock and are new', () {
      final s = snap([tx(today), tx(today, type: TxKind.transfer)]);
      final a = s.achievements;
      expect(a.byId('first_transaction')!.unlocked, isTrue);
      expect(a.byId('first_transfer')!.unlocked, isTrue);
      expect(a.byId('transactions_100')!.current, 2);
      expect(a.byId('transactions_100')!.fraction, closeTo(0.02, 1e-9));
      expect(
        a.newlyUnlocked.map((e) => e.id),
        containsAll(['first_transaction', 'first_transfer']),
      );
      expect(s.summary.celebrations.newAchievements, isNotEmpty);
    });

    test('seen flags hide them from newlyUnlocked', () {
      final s = snap(
        [tx(today)],
        local: const GameLocalState(
          lastSeenLevel: 1,
          seenAchievements: {'first_transaction'},
        ),
      );
      expect(s.achievements.byId('first_transaction')!.isNew, isFalse);
      expect(
        s.achievements.newlyUnlocked.any((a) => a.id == 'first_transaction'),
        isFalse,
      );
    });

    test('streak achievements use the longest streak', () {
      final events = [for (var i = 0; i < 7; i++) tx(today.addDays(-20 + i))];
      final a = snap(events).achievements;
      expect(a.byId('streak_7')!.unlocked, isTrue);
      expect(a.byId('streak_30')!.current, 7);
    });

    test('prayers: full days and 7-day run', () {
      final events = [
        for (var i = 0; i < 7; i++)
          for (final p in prayerNames)
            ActivityEvent.prayer(date: today.addDays(-i), prayer: p),
        for (final p in prayerNames.take(4))
          ActivityEvent.prayer(date: today.addDays(-9), prayer: p),
      ];
      final a = snap(events).achievements;
      expect(a.byId('prayers_full_day')!.unlocked, isTrue);
      expect(a.byId('prayers_7_days')!.unlocked, isTrue);
      expect(a.byId('prayers_30_days')!.current, 7);
    });

    test('budgets: first budget, clean past months only', () {
      BudgetStatus b(int month, double spent) => BudgetStatus(
        categoryId: 'food',
        year: 2026,
        month: month,
        budget: 100,
        spent: spent,
      );
      final a = snap(
        [],
        budgets: [b(6, 50), b(7, 150), b(8, 90), b(9, 10)],
      ).achievements;
      expect(a.byId('first_budget')!.unlocked, isTrue);
      expect(
        a.byId('clean_month')!.current,
        2,
      ); // June + August; July over; Sept ongoing
      expect(a.byId('clean_month_3')!.unlocked, isFalse);
    });

    test('savings rate from completed months by transaction date', () {
      final aug = DateTime(2026, 8, 15);
      final events = [
        tx(today, type: TxKind.income, amount: 10000000, date: aug, id: 'i'),
        tx(today, amount: 7000000, date: aug, id: 'e'),
        // Current month doesn't count yet.
        tx(today, type: TxKind.income, amount: 10000000, id: 'i2'),
      ];
      final a = snap(events).achievements;
      expect(a.byId('savings_20')!.current, 30);
      expect(a.byId('savings_20')!.unlocked, isTrue);
      expect(a.byId('savings_50')!.unlocked, isFalse);
      expect(AchievementStats.savingsRatePct(0, 100), 0);
      expect(AchievementStats.savingsRatePct(100, 150), 0);
    });

    test('health, weight days, food', () {
      final events = [
        for (var i = 0; i < 7; i++)
          ActivityEvent.health(
            createdAt: today.addDays(-i).toLocalDateTime(),
            hasWeight: true,
          ),
        ActivityEvent.health(createdAt: now),
        for (var i = 0; i < 30; i++)
          ActivityEvent.food(createdAt: now, id: 'f$i'),
      ];
      final a = snap(events).achievements;
      expect(a.byId('first_health')!.unlocked, isTrue);
      expect(a.byId('weight_7_days')!.unlocked, isTrue);
      expect(a.byId('food_30')!.unlocked, isTrue);
    });

    test('lesson achievements', () {
      final local = GameLocalState(
        lastSeenLevel: 1,
        lessonCompletions: [
          for (final l in learnUnits.first.lessons)
            LessonCompletion(
              lessonId: l.id,
              at: now,
              xp: 15,
              accuracy: 1,
              perfect: l.id == 'u1l2',
              practice: false,
            ),
        ],
      );
      final a = snap([], local: local).achievements;
      expect(a.byId('first_lesson')!.unlocked, isTrue);
      expect(a.byId('perfect_lesson')!.unlocked, isTrue);
      expect(a.byId('unit_complete')!.unlocked, isTrue);
      expect(a.byId('lessons_10')!.current, learnUnits.first.lessons.length);
      expect(a.byId('path_complete')!.unlocked, isFalse);
    });
  });

  group('Summary', () {
    test('combines streak, goal, xp, hearts and mascot', () {
      final events = [
        tx(today.addDays(-2)),
        tx(today.addDays(-1)),
        tx(today),
        tx(today),
        tx(today),
      ];
      final s = snap(
        events,
        budgets: [
          BudgetStatus(
            categoryId: 'a',
            year: 2026,
            month: 9,
            budget: 100,
            spent: 200,
          ),
        ],
      ).summary;
      expect(s.streak.current, 3);
      expect(s.goal.done, 3);
      expect(s.goal.isMet, isTrue);
      expect(s.hearts.current, 4);
      expect(s.mood, MascotMood.celebrating);
      expect(s.message, isNotEmpty);
      // 50 tx XP + 3 goal bonuses? day-2: 1 tx (goal 3 not met), day-1 same, today met.
      expect(
        s.totalXp,
        50 + XpRules.dailyGoalMet + XpRules.streakMilestones[3]!,
      );
      expect(
        s.xpToday,
        30 + XpRules.dailyGoalMet + XpRules.streakMilestones[3]!,
      );
      expect(s.celebrations.dailyGoalMet, isTrue);
      expect(s.celebrations.streakMilestone, StreakMilestoneHit(today, 3));
    });

    test('at-risk streak late in the day makes the mascot worried', () {
      final s = snap([
        tx(today.addDays(-1)),
      ], at: DateTime(2026, 9, 10, 21)).summary;
      expect(s.streak.atRisk, isTrue);
      expect(s.mood, MascotMood.worried);
    });

    test('first run: needs reconcile, no achievement flood, then stable', () {
      final events = [for (var i = 0; i < 10; i++) tx(today.addDays(-i))];
      final first = snap(events, local: const GameLocalState());
      expect(first.needsReconcile, isTrue);
      expect(first.summary.celebrations.newAchievements, isEmpty);
      expect(first.summary.celebrations.levelUp, isNull);

      final reconciled = const ReconcileLocalState()(
        const GameLocalState(),
        first,
      );
      expect(reconciled.lastSeenLevel, first.summary.level.level);
      expect(reconciled.seenAchievements, contains('first_transaction'));
      final second = snap(events, local: reconciled);
      expect(second.needsReconcile, isFalse);
      expect(second.achievements.newlyUnlocked, isEmpty);
    });

    test('used freezes get reconciled into local state', () {
      final events = [
        for (var i = 3; i < 10; i++) tx(today.addDays(-i)),
        tx(today.addDays(-1)),
      ];
      final s1 = snap(events);
      expect(s1.summary.streak.newlyFrozenDays, {today.addDays(-2)});
      expect(s1.needsReconcile, isTrue);
      final local = const ReconcileLocalState()(
        const GameLocalState(lastSeenLevel: 1),
        s1,
      );
      expect(local.usedFreezeDays, {today.addDays(-2)});
      final s2 = snap(events, local: local);
      expect(s2.needsReconcile, isFalse);
      expect(s2.summary.streak.current, s1.summary.streak.current);
    });

    test('level up celebration and acknowledgement', () {
      final events = [for (var i = 0; i < 15; i++) tx(today, id: 't$i')];
      final s = snap(events).summary;
      expect(s.level.level, greaterThan(1));
      expect(s.celebrations.levelUp!.level, s.level.level);

      final acked = const AcknowledgeCelebrations()(
        const GameLocalState(lastSeenLevel: 1),
        s.celebrations,
        today,
      );
      final after = snap(events, local: acked).summary.celebrations;
      expect(after.levelUp, isNull);
      expect(after.dailyGoalMet, isFalse);
      expect(after.newAchievements, isEmpty);
      expect(after.isEmpty, isTrue);
    });
  });
}
