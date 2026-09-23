import 'achievements.dart';
import 'activity.dart';
import 'daily_goal.dart';
import 'game_date.dart';
import 'game_store.dart';
import 'hearts.dart';
import 'learn/learn_content.dart';
import 'learn/learn_models.dart';
import 'learn/learn_path.dart';
import 'levels.dart';
import 'mascot.dart';
import 'streak.dart';
import 'xp.dart';

/// Reward moments the UI should celebrate (confetti, sheets, sounds).
class GameCelebrations {
  const GameCelebrations({
    this.levelUp,
    this.streakMilestone,
    this.dailyGoalMet = false,
    this.newAchievements = const [],
  });

  /// New level reached since the user last acknowledged (null = none).
  final LevelInfo? levelUp;

  /// Streak milestone reached today and not yet celebrated.
  final StreakMilestoneHit? streakMilestone;

  /// Today's daily goal met and not yet celebrated.
  final bool dailyGoalMet;

  /// Achievements unlocked and not yet marked seen.
  final List<AchievementProgress> newAchievements;

  bool get isEmpty =>
      levelUp == null &&
      streakMilestone == null &&
      !dailyGoalMet &&
      newAchievements.isEmpty;
  bool get isNotEmpty => !isEmpty;

  static String goalKey(GameDate d) => 'goal:${d.toKey()}';
  static String streakKey(StreakMilestoneHit h) =>
      'streak:${h.date.toKey()}:${h.length}';
}

/// Everything the home/profile screens need, computed in one pass.
class GameSummary {
  const GameSummary({
    required this.today,
    required this.now,
    required this.xp,
    required this.level,
    required this.streak,
    required this.goal,
    required this.hearts,
    required this.mood,
    required this.message,
    required this.celebrations,
  });

  final GameDate today;
  final DateTime now;
  final XpLedger xp;
  final LevelInfo level;
  final StreakResult streak;
  final DailyGoalProgress goal;
  final HeartsState hearts;
  final MascotMood mood;
  final String message;
  final GameCelebrations celebrations;

  int get totalXp => xp.total;
  int get xpToday => xp.xpToday;
}

/// Full derived game state + reconciliation work for the local store.
class GameSnapshot {
  const GameSnapshot({
    required this.summary,
    required this.achievements,
    required this.path,
    required this.stats,
    required this.needsReconcile,
  });

  final GameSummary summary;
  final AchievementsState achievements;
  final LearnPathProgress path;
  final AchievementStats stats;

  /// True when local state should be updated via [ReconcileLocalState]
  /// (newly used freezes to record, or first-run baselines to set).
  final bool needsReconcile;
}

/// Use case: fold derived facts back into local state so results stay stable:
/// records freezes consumed by the streak simulation and, on first run, sets the
/// level baseline and marks already-unlocked achievements as seen (so a user
/// with years of synced history isn't flooded with celebrations).
class ReconcileLocalState {
  const ReconcileLocalState();

  GameLocalState call(GameLocalState current, GameSnapshot snapshot) {
    final firstRun = current.lastSeenLevel == null;
    final frozen = snapshot.summary.streak.newlyFrozenDays;
    if (!firstRun && current.usedFreezeDays.containsAll(frozen)) return current;
    return current.copyWith(
      usedFreezeDays: {...current.usedFreezeDays, ...frozen},
      lastSeenLevel: current.lastSeenLevel ?? snapshot.summary.level.level,
      seenAchievements: firstRun
          ? {
              ...current.seenAchievements,
              for (final a in snapshot.achievements.unlocked) a.id,
            }
          : null,
    );
  }
}

/// Use case: derive the whole game state from data + local state. Pure.
class ComputeGameSnapshot {
  const ComputeGameSnapshot();

  GameSnapshot call({
    required Iterable<ActivityEvent> events,
    required Iterable<BudgetStatus> budgets,
    required GameLocalState local,
    required DateTime now,
    List<LearnUnit> units = learnUnits,
    String? userName,
  }) {
    final eventList = events.toList();
    final today = GameDate.fromDateTime(now);

    final streak = StreakCalculator.compute(
      loggedDays: [
        for (final e in eventList)
          if (e.kind == ActivityKind.transaction) e.day,
      ],
      today: today,
      recordedFrozenDays: local.usedFreezeDays,
      grantedFreezes: local.grantedFreezes,
    );

    final xp = XpCalculator.compute(
      events: eventList,
      lessons: local.lessonCompletions,
      goalHistory: local.dailyGoalHistory,
      streak: streak,
      today: today,
    );
    final level = LevelCurve.forXp(xp.total);
    final todayXp = xp.dayOf(today);
    final goal = DailyGoalProgress(
      level: todayXp?.goal ?? goalLevelOn(today, local.dailyGoalHistory),
      done: todayXp?.activities ?? 0,
    );
    final hearts = HeartsCalculator.compute(budgets, GameMonth.of(today));

    final mascotCtx = MascotContext(
      now: now,
      streak: streak.current,
      loggedToday: streak.loggedToday,
      goalMet: goal.isMet,
      goalRemaining: goal.remaining,
      hearts: hearts.current,
      maxHearts: hearts.max,
      longestStreak: streak.longest,
      hasAnyActivity: streak.days.isNotEmpty,
      name: userName,
    );
    final mood = Mascot.moodFor(mascotCtx);

    final path = LearnPathCalculator.compute(units, local.lessonCompletions);
    final stats = AchievementStats.compute(
      events: eventList,
      budgets: budgets,
      streak: streak,
      xp: xp,
      level: level.level,
      path: path,
      lessons: local.lessonCompletions,
      today: today,
    );
    final achievements = AchievementsState.evaluate(
      stats,
      local.seenAchievements,
    );

    final milestone = streak.milestoneToday;
    final celebrations = GameCelebrations(
      levelUp: local.lastSeenLevel != null && level.level > local.lastSeenLevel!
          ? level
          : null,
      streakMilestone:
          milestone != null &&
              !local.celebrated.contains(GameCelebrations.streakKey(milestone))
          ? milestone
          : null,
      dailyGoalMet:
          goal.isMet &&
          !local.celebrated.contains(GameCelebrations.goalKey(today)),
      // First run (no baseline yet): history gets marked seen by reconciliation.
      newAchievements: local.lastSeenLevel == null
          ? const []
          : achievements.newlyUnlocked,
    );

    return GameSnapshot(
      summary: GameSummary(
        today: today,
        now: now,
        xp: xp,
        level: level,
        streak: streak,
        goal: goal,
        hearts: hearts,
        mood: mood,
        message: Mascot.messageFor(mood, mascotCtx),
        celebrations: celebrations,
      ),
      achievements: achievements,
      path: path,
      stats: stats,
      needsReconcile:
          streak.newlyFrozenDays.isNotEmpty || local.lastSeenLevel == null,
    );
  }
}
