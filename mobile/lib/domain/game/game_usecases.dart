import 'achievements.dart';
import 'daily_goal.dart';
import 'game_date.dart';
import 'game_store.dart';
import 'game_summary.dart';
import 'learn/lesson_session.dart';
import 'xp_rules.dart';

// Pure state transitions on GameLocalState. The presentation layer holds the
// state, applies these and persists via GameStateRepository.

/// Record a finished lesson session (XP comes from [LessonResult.xp]).
class CompleteLesson {
  const CompleteLesson();

  GameLocalState call(GameLocalState state, LessonResult result, DateTime at) {
    // A "first" run of an already-completed lesson is stored as practice.
    final practice =
        result.practice || state.isLessonCompleted(result.lessonId);
    final completion = LessonCompletion(
      lessonId: result.lessonId,
      at: at,
      xp: practice && !result.practice
          ? XpRules.lessonXp(mistakes: result.mistakes, practice: true)
          : result.xp,
      accuracy: result.accuracy,
      perfect: result.perfect,
      practice: practice,
    );
    return state.copyWith(
      lessonCompletions: [...state.lessonCompletions, completion],
    );
  }
}

/// Change the daily goal from [today] on (past days keep their old goal).
class SetDailyGoal {
  const SetDailyGoal();

  GameLocalState call(
    GameLocalState state,
    DailyGoalLevel level,
    GameDate today,
  ) {
    final history = [
      for (final c in state.dailyGoalHistory)
        if (c.from != today) c,
      DailyGoalChange(today, level),
    ]..sort((a, b) => a.from.compareTo(b.from));
    return state.copyWith(dailyGoalHistory: history);
  }
}

class MarkAchievementsSeen {
  const MarkAchievementsSeen();

  GameLocalState call(GameLocalState state, Iterable<String> ids) =>
      state.copyWith(seenAchievements: {...state.seenAchievements, ...ids});

  GameLocalState all(GameLocalState state, AchievementsState achievements) =>
      call(state, achievements.unlocked.map((a) => a.id));
}

/// Grant an extra streak freeze (e.g. a reward). Capped by the max held.
class GrantStreakFreeze {
  const GrantStreakFreeze();

  GameLocalState call(GameLocalState state, GameDate today) =>
      state.copyWith(grantedFreezes: [...state.grantedFreezes, today]);
}

/// Persist days covered by a freeze so the streak stays stable.
class RecordUsedFreezes {
  const RecordUsedFreezes();

  GameLocalState call(GameLocalState state, Iterable<GameDate> days) =>
      state.copyWith(usedFreezeDays: {...state.usedFreezeDays, ...days});
}

/// Mark the given celebrations as shown.
class AcknowledgeCelebrations {
  const AcknowledgeCelebrations();

  /// Keys older than this are pruned.
  static const keepDays = 30;

  GameLocalState call(
    GameLocalState state,
    GameCelebrations c,
    GameDate today,
  ) {
    final keys = {
      for (final k in state.celebrated)
        if (_isRecent(k, today)) k,
      if (c.dailyGoalMet) GameCelebrations.goalKey(today),
      if (c.streakMilestone != null)
        GameCelebrations.streakKey(c.streakMilestone!),
    };
    return state.copyWith(
      celebrated: keys,
      lastSeenLevel: c.levelUp?.level,
      seenAchievements: {
        ...state.seenAchievements,
        for (final a in c.newAchievements) a.id,
      },
    );
  }

  static bool _isRecent(String key, GameDate today) {
    final parts = key.split(':');
    if (parts.length < 2) return false;
    final d = GameDate.tryParse(parts[1]);
    return d != null && today.difference(d) <= keepDays;
  }
}

/// Record the "FIRE kosong" snapshot of [day] (see `fire_clear.dart`).
/// Add-only; returns the same instance when nothing changes.
class RecordFireClearDay {
  const RecordFireClearDay();

  GameLocalState call(GameLocalState state, GameDate day) =>
      state.fireClearDays.contains(day)
      ? state
      : state.copyWith(fireClearDays: {...state.fireClearDays, day});
}

class CompleteOnboarding {
  const CompleteOnboarding();

  GameLocalState call(
    GameLocalState state, {
    DailyGoalLevel? goal,
    required GameDate today,
  }) {
    final s = goal == null ? state : const SetDailyGoal()(state, goal, today);
    return s.copyWith(onboardingDone: true);
  }
}
