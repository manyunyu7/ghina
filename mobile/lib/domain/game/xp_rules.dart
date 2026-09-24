/// Tunable gamification constants. Everything XP-related reads from here.
abstract final class XpRules {
  // --- Activities -----------------------------------------------------------
  static const transaction = 10;

  /// Max transactions per day that earn XP / count toward the daily goal.
  static const transactionDailyCap = 15;

  /// XP per fardhu = its quality points (spec `docs/prayer-quality.md`):
  /// masjid 10, jamaah 8, ontime 6, late 3, qadha 1, missed/excused 0.
  static const prayerStatusXp = <String, int>{
    'masjid': 10,
    'jamaah': 8,
    'ontime': 6,
    'late': 3,
    'qadha': 1,
    'missed': 0,
    'excused': 0,
  };

  /// XP of one fardhu with [status] (unknown → 0).
  static int prayerXp(String? status) => prayerStatusXp[status] ?? 0;

  /// Each rawatib (qobliyah / ba'diyah) ticked.
  static const rawatib = 2;

  /// Each daily sunnah (dhuha / tahajud / witir).
  static const sunnah = 3;

  /// Bonus when all 5 fardhu of a day are prayed (masjid … qadha).
  static const allPrayersBonus = 15;

  static const health = 5;
  static const healthDailyCap = 3;

  static const food = 5;
  static const foodDailyCap = 6;

  /// Completed task XP by bucket (`docs/tasks.md` → Gamification); mirrors
  /// `TaskBucket.xp` (fire 10 / want 8 / should 5).
  static const taskBucketXp = <String, int>{'fire': 10, 'want': 8, 'should': 5};

  /// Max completed tasks per local day (of `doneAt`) that earn XP / count toward
  /// the daily goal; mirrors `taskXpDailyCap` in `domain/usecases/task_rules.dart`.
  static const taskDailyCap = 20;

  /// XP of one completed task in [bucket] (unknown → the SHOULD value).
  static int taskXp(String? bucket) =>
      taskBucketXp[bucket] ?? taskBucketXp['should']!;

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
