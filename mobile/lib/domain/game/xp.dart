import 'activity.dart';
import 'daily_goal.dart';
import 'game_date.dart';
import 'game_store.dart';
import 'streak.dart';
import 'xp_rules.dart';

/// Where XP came from.
enum XpSource {
  transaction,
  prayer,
  prayerBonus,
  health,
  food,
  lesson,
  dailyGoal,
  streakMilestone,
}

/// XP and activity numbers for one local day.
class DayXp {
  DayXp(this.date);

  final GameDate date;
  final Map<XpSource, int> breakdown = {};

  /// Counted activities (for the daily goal).
  int activities = 0;
  DailyGoalLevel goal = DailyGoalLevel.defaultLevel;

  int transactionsCounted = 0;
  int transactionsTotal = 0;
  final Set<String> prayers = {};
  int healthCounted = 0;
  int foodCounted = 0;
  int lessons = 0;

  int get total => breakdown.values.fold(0, (a, b) => a + b);
  bool get goalMet => activities >= goal.target;
  bool get allPrayers => prayers.length >= prayerNames.length;

  void add(XpSource source, int xp) =>
      breakdown[source] = (breakdown[source] ?? 0) + xp;
}

class XpLedger {
  const XpLedger({required this.today, required this.days});

  final GameDate today;

  /// Per-day XP, only days with any activity/XP.
  final Map<GameDate, DayXp> days;

  int get total => days.values.fold(0, (a, d) => a + d.total);

  DayXp? dayOf(GameDate d) => days[d];
  int xpOn(GameDate d) => days[d]?.total ?? 0;
  int get xpToday => xpOn(today);
  int get activitiesToday => days[today]?.activities ?? 0;

  /// Days on which the daily goal was met (including today if met).
  int get goalDays =>
      days.values.where((d) => d.goalMet && d.activities > 0).length;

  /// XP per day for the last [count] days ending today (oldest first), for charts.
  List<(GameDate, int)> history({int count = 7}) => [
    for (var i = count - 1; i >= 0; i--)
      (today.addDays(-i), xpOn(today.addDays(-i))),
  ];
}

/// Pure XP computation from activity + local lesson completions + streak.
abstract final class XpCalculator {
  static XpLedger compute({
    required Iterable<ActivityEvent> events,
    required Iterable<LessonCompletion> lessons,
    required List<DailyGoalChange> goalHistory,
    required StreakResult streak,
    required GameDate today,
  }) {
    final days = <GameDate, DayXp>{};
    DayXp dayOf(GameDate d) => days.putIfAbsent(d, () => DayXp(d));

    // Dedupe by id (sync may deliver the same row twice).
    final seenIds = <String>{};
    final sorted = [
      for (final e in events)
        if (e.id == null || seenIds.add('${e.kind.name}:${e.id}')) e,
    ]..sort((a, b) => a.at.compareTo(b.at));

    for (final e in sorted) {
      final date = e.day;
      if (date.isAfter(today)) continue;
      final day = dayOf(date);
      switch (e.kind) {
        case ActivityKind.transaction:
          day.transactionsTotal++;
          if (day.transactionsCounted < XpRules.transactionDailyCap) {
            day.transactionsCounted++;
            day.activities++;
            day.add(XpSource.transaction, XpRules.transaction);
          }
        case ActivityKind.prayer:
          final name = e.prayer;
          if (name != null &&
              prayerNames.contains(name) &&
              day.prayers.add(name)) {
            day.activities++;
            day.add(XpSource.prayer, XpRules.prayer);
            if (day.allPrayers) {
              day.add(XpSource.prayerBonus, XpRules.allPrayersBonus);
            }
          }
        case ActivityKind.health:
          if (day.healthCounted < XpRules.healthDailyCap) {
            day.healthCounted++;
            day.activities++;
            day.add(XpSource.health, XpRules.health);
          }
        case ActivityKind.food:
          if (day.foodCounted < XpRules.foodDailyCap) {
            day.foodCounted++;
            day.activities++;
            day.add(XpSource.food, XpRules.food);
          }
        case ActivityKind.lesson:
          // Lessons come from local completions below.
          break;
      }
    }

    for (final c in lessons) {
      final date = c.day;
      if (date.isAfter(today)) continue;
      final day = dayOf(date);
      day.add(XpSource.lesson, c.xp);
      if (day.lessons < XpRules.lessonDailyGoalCap) day.activities++;
      day.lessons++;
    }

    for (final day in days.values) {
      day.goal = goalLevelOn(day.date, goalHistory);
      if (day.activities > 0 && day.goalMet) {
        day.add(XpSource.dailyGoal, XpRules.dailyGoalMet);
      }
    }

    for (final hit in streak.milestones) {
      if (hit.date.isAfter(today)) continue;
      dayOf(hit.date).add(
        XpSource.streakMilestone,
        XpRules.streakMilestones[hit.length] ?? 0,
      );
    }

    // Make sure today exists with the right goal even with no activity.
    dayOf(today).goal = goalLevelOn(today, goalHistory);

    return XpLedger(today: today, days: days);
  }
}
