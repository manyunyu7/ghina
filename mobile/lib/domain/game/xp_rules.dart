/// Tunable gamification constants. Everything XP-related reads from here.
abstract final class XpRules {
  // --- Activities -----------------------------------------------------------
  static const transaction = 10;

  /// Max transactions per day that earn XP / count toward the daily goal.
  static const transactionDailyCap = 15;

  static const prayer = 5;

  /// Bonus when all 5 prayers of a day are logged.
  static const allPrayersBonus = 15;

  static const health = 5;
  static const healthDailyCap = 3;

  static const food = 5;
  static const foodDailyCap = 6;

  // --- Lessons --------------------------------------------------------------
  static const lessonBase = 15;
  static const lessonPerfectBonus = 5;

  /// XP lost per mistake (no failing — the lesson just earns less).
  static const lessonMistakePenalty = 2;
  static const lessonMinimum = 5;

  /// Replaying an already completed lesson ("Latihan").
  static const practiceBase = 5;
  static const practicePerfectBonus = 5;

  /// Max lesson sessions per day that count toward the daily goal.
  static const lessonDailyGoalCap = 10;

  // --- Goals & streak -------------------------------------------------------
  static const dailyGoalMet = 20;

  /// Streak length -> bonus XP when the streak reaches that length.
  static const streakMilestones = <int, int>{
    3: 15,
    7: 30,
    14: 50,
    30: 100,
    50: 150,
    100: 300,
    365: 1000,
  };

  /// A streak freeze is earned every time the streak reaches a multiple of this.
  static const freezeEveryDays = 7;
  static const maxFreezesHeld = 2;

  /// Max consecutive missed days that freezes may cover.
  static const maxConsecutiveFrozenDays = 2;

  // --- Hearts ---------------------------------------------------------------
  static const heartsPerMonth = 5;

  /// Categories at or above this spent/budget ratio are "near the limit".
  static const nearBudgetRatio = 0.9;

  /// XP earned for a finished lesson session.
  static int lessonXp({required int mistakes, required bool practice}) {
    final perfect = mistakes == 0;
    if (practice) return practiceBase + (perfect ? practicePerfectBonus : 0);
    final base = lessonBase - mistakes * lessonMistakePenalty;
    return (base < lessonMinimum ? lessonMinimum : base) +
        (perfect ? lessonPerfectBonus : 0);
  }
}
