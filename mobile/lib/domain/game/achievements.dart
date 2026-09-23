import 'activity.dart';
import 'game_date.dart';
import 'game_store.dart';
import 'learn/learn_path.dart';
import 'streak.dart';
import 'xp.dart';

enum AchievementTier { bronze, silver, gold, diamond }

/// Numbers achievements are measured against (see [AchievementStats]).
enum AchievementMetric {
  totalTransactions,
  transfers,
  longestStreak,
  budgetsCreated,
  cleanBudgetMonths,
  bestSavingsRatePct,
  allPrayerDays,
  bestAllPrayerRun,
  weightDays,
  healthEntries,
  foodLogs,
  lessonsCompleted,
  perfectLessons,
  unitsCompleted,
  pathPercent,
  level,
  totalXp,
  goalDays,
}

class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.tier,
    required this.metric,
    required this.target,
  });

  /// Stable id — persisted in "seen" flags, never rename.
  final String id;
  final String title;
  final String description;

  /// Material icon name hint (e.g. `local_fire_department`).
  final String icon;
  final AchievementTier tier;
  final AchievementMetric metric;
  final int target;
}

/// All achievements, in display order.
const List<AchievementDef> achievementDefs = [
  AchievementDef(
    id: 'first_transaction',
    title: 'Langkah Pertama',
    description: 'Catat transaksi pertamamu.',
    icon: 'edit_note',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.totalTransactions,
    target: 1,
  ),
  AchievementDef(
    id: 'transactions_100',
    title: 'Pencatat Rajin',
    description: 'Catat 100 transaksi.',
    icon: 'receipt_long',
    tier: AchievementTier.silver,
    metric: AchievementMetric.totalTransactions,
    target: 100,
  ),
  AchievementDef(
    id: 'transactions_1000',
    title: 'Arsiparis Keuangan',
    description: 'Catat 1.000 transaksi. Luar biasa telaten!',
    icon: 'inventory',
    tier: AchievementTier.gold,
    metric: AchievementMetric.totalTransactions,
    target: 1000,
  ),
  AchievementDef(
    id: 'first_transfer',
    title: 'Pindah Kantong',
    description: 'Catat transfer pertama antar dompet.',
    icon: 'swap_horiz',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.transfers,
    target: 1,
  ),
  AchievementDef(
    id: 'streak_3',
    title: 'Mulai Panas',
    description: 'Streak 3 hari berturut-turut.',
    icon: 'local_fire_department',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.longestStreak,
    target: 3,
  ),
  AchievementDef(
    id: 'streak_7',
    title: 'Seminggu Konsisten',
    description: 'Streak 7 hari berturut-turut.',
    icon: 'local_fire_department',
    tier: AchievementTier.silver,
    metric: AchievementMetric.longestStreak,
    target: 7,
  ),
  AchievementDef(
    id: 'streak_30',
    title: 'Sebulan Penuh',
    description: 'Streak 30 hari tanpa putus.',
    icon: 'whatshot',
    tier: AchievementTier.gold,
    metric: AchievementMetric.longestStreak,
    target: 30,
  ),
  AchievementDef(
    id: 'streak_100',
    title: 'Streak Legendaris',
    description: 'Streak 100 hari. Kamu legenda!',
    icon: 'military_tech',
    tier: AchievementTier.diamond,
    metric: AchievementMetric.longestStreak,
    target: 100,
  ),
  AchievementDef(
    id: 'first_budget',
    title: 'Si Perencana',
    description: 'Buat anggaran pertamamu.',
    icon: 'pie_chart',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.budgetsCreated,
    target: 1,
  ),
  AchievementDef(
    id: 'clean_month',
    title: 'Bulan Bebas Jebol',
    description: 'Lewati satu bulan penuh tanpa anggaran yang jebol.',
    icon: 'verified',
    tier: AchievementTier.silver,
    metric: AchievementMetric.cleanBudgetMonths,
    target: 1,
  ),
  AchievementDef(
    id: 'clean_month_3',
    title: 'Disiplin Baja',
    description: '3 bulan tanpa anggaran jebol.',
    icon: 'shield',
    tier: AchievementTier.gold,
    metric: AchievementMetric.cleanBudgetMonths,
    target: 3,
  ),
  AchievementDef(
    id: 'savings_20',
    title: 'Hemat Pangkal Kaya',
    description: 'Sisihkan minimal 20% pemasukan dalam sebulan.',
    icon: 'savings',
    tier: AchievementTier.silver,
    metric: AchievementMetric.bestSavingsRatePct,
    target: 20,
  ),
  AchievementDef(
    id: 'savings_50',
    title: 'Raja Nabung',
    description: 'Sisihkan minimal 50% pemasukan dalam sebulan.',
    icon: 'workspace_premium',
    tier: AchievementTier.gold,
    metric: AchievementMetric.bestSavingsRatePct,
    target: 50,
  ),
  AchievementDef(
    id: 'prayers_full_day',
    title: 'Lima Waktu',
    description: 'Catat kelima salat dalam satu hari.',
    icon: 'mosque',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.allPrayerDays,
    target: 1,
  ),
  AchievementDef(
    id: 'prayers_7_days',
    title: 'Istiqomah',
    description: 'Lengkap lima waktu selama 7 hari berturut-turut.',
    icon: 'mosque',
    tier: AchievementTier.silver,
    metric: AchievementMetric.bestAllPrayerRun,
    target: 7,
  ),
  AchievementDef(
    id: 'prayers_30_days',
    title: 'Istiqomah Sebulan',
    description: 'Lengkap lima waktu selama 30 hari berturut-turut.',
    icon: 'auto_awesome',
    tier: AchievementTier.gold,
    metric: AchievementMetric.bestAllPrayerRun,
    target: 30,
  ),
  AchievementDef(
    id: 'first_health',
    title: 'Cek Kesehatan',
    description: 'Catat data kesehatan pertamamu.',
    icon: 'favorite',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.healthEntries,
    target: 1,
  ),
  AchievementDef(
    id: 'weight_7_days',
    title: 'Pantau Timbangan',
    description: 'Catat berat badan di 7 hari berbeda.',
    icon: 'monitor_weight',
    tier: AchievementTier.silver,
    metric: AchievementMetric.weightDays,
    target: 7,
  ),
  AchievementDef(
    id: 'food_30',
    title: 'Food Diary',
    description: 'Catat 30 makanan.',
    icon: 'restaurant',
    tier: AchievementTier.silver,
    metric: AchievementMetric.foodLogs,
    target: 30,
  ),
  AchievementDef(
    id: 'first_lesson',
    title: 'Murid Baru',
    description: 'Selesaikan pelajaran pertamamu.',
    icon: 'school',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.lessonsCompleted,
    target: 1,
  ),
  AchievementDef(
    id: 'lessons_10',
    title: 'Kutu Buku Finansial',
    description: 'Selesaikan 10 pelajaran.',
    icon: 'menu_book',
    tier: AchievementTier.silver,
    metric: AchievementMetric.lessonsCompleted,
    target: 10,
  ),
  AchievementDef(
    id: 'perfect_lesson',
    title: 'Sempurna!',
    description: 'Selesaikan pelajaran tanpa salah sama sekali.',
    icon: 'stars',
    tier: AchievementTier.bronze,
    metric: AchievementMetric.perfectLessons,
    target: 1,
  ),
  AchievementDef(
    id: 'unit_complete',
    title: 'Lulus Unit',
    description: 'Tamatkan satu unit pelajaran.',
    icon: 'emoji_events',
    tier: AchievementTier.silver,
    metric: AchievementMetric.unitsCompleted,
    target: 1,
  ),
  AchievementDef(
    id: 'path_complete',
    title: 'Wisudawan Ghina',
    description: 'Tamatkan semua pelajaran di jalur belajar.',
    icon: 'workspace_premium',
    tier: AchievementTier.diamond,
    metric: AchievementMetric.pathPercent,
    target: 100,
  ),
  AchievementDef(
    id: 'goal_7_days',
    title: 'Pemburu Target',
    description: 'Capai target harian di 7 hari berbeda.',
    icon: 'track_changes',
    tier: AchievementTier.silver,
    metric: AchievementMetric.goalDays,
    target: 7,
  ),
  AchievementDef(
    id: 'level_10',
    title: 'Naik Kelas',
    description: 'Capai level 10.',
    icon: 'trending_up',
    tier: AchievementTier.gold,
    metric: AchievementMetric.level,
    target: 10,
  ),
  AchievementDef(
    id: 'xp_10000',
    title: 'Kolektor XP',
    description: 'Kumpulkan 10.000 XP.',
    icon: 'bolt',
    tier: AchievementTier.diamond,
    metric: AchievementMetric.totalXp,
    target: 10000,
  ),
];

/// Aggregated numbers derived from data + local progress.
class AchievementStats {
  const AchievementStats(this.values);

  final Map<AchievementMetric, int> values;

  int operator [](AchievementMetric m) => values[m] ?? 0;

  /// Minimum savings rate for a month to count (ignore months without income).
  static int savingsRatePct(double income, double expense) {
    if (income <= 0) return 0;
    final pct = ((income - expense) / income * 100).floor();
    return pct < 0 ? 0 : pct;
  }

  static AchievementStats compute({
    required Iterable<ActivityEvent> events,
    required Iterable<BudgetStatus> budgets,
    required StreakResult streak,
    required XpLedger xp,
    required int level,
    required LearnPathProgress path,
    required Iterable<LessonCompletion> lessons,
    required GameDate today,
  }) {
    var transactions = 0, transfers = 0, health = 0, food = 0;
    final weightDays = <GameDate>{};
    final prayersByDay = <GameDate, Set<String>>{};
    final income = <GameMonth, double>{};
    final expense = <GameMonth, double>{};
    final seenIds = <String>{};

    for (final e in events) {
      if (e.id != null && !seenIds.add('${e.kind.name}:${e.id}')) continue;
      switch (e.kind) {
        case ActivityKind.transaction:
          transactions++;
          final month = GameMonth.of(e.occurredDay);
          final amount = (e.amount ?? 0).abs();
          switch (e.txKind ?? TxKind.expense) {
            case TxKind.transfer:
              transfers++;
            case TxKind.income:
              income[month] = (income[month] ?? 0) + amount;
            case TxKind.expense:
              expense[month] = (expense[month] ?? 0) + amount;
          }
        case ActivityKind.prayer:
          if (e.prayer != null && prayerNames.contains(e.prayer)) {
            prayersByDay.putIfAbsent(e.day, () => {}).add(e.prayer!);
          }
        case ActivityKind.health:
          health++;
          if (e.hasWeight) weightDays.add(e.occurredDay);
        case ActivityKind.food:
          food++;
        case ActivityKind.lesson:
          break;
      }
    }

    // Savings rate: only completed months (the current month is still moving).
    final currentMonth = GameMonth.of(today);
    var bestSavings = 0;
    for (final entry in income.entries) {
      if (entry.key.compareTo(currentMonth) >= 0) continue;
      final pct = savingsRatePct(entry.value, expense[entry.key] ?? 0);
      if (pct > bestSavings) bestSavings = pct;
    }

    // Budgets.
    final budgetMonths = <GameMonth, bool>{}; // month -> any over?
    final budgetKeys = <String>{};
    for (final b in budgets) {
      budgetKeys.add('${b.categoryId}:${b.year}-${b.month}');
      final m = GameMonth(b.year, b.month);
      budgetMonths[m] = (budgetMonths[m] ?? false) || b.isOver;
    }
    final cleanMonths = budgetMonths.entries
        .where((e) => e.key.compareTo(currentMonth) < 0 && !e.value)
        .length;

    // Prayers: full days and best consecutive run of full days.
    final fullDays = [
      for (final e in prayersByDay.entries)
        if (e.value.length >= prayerNames.length) e.key,
    ]..sort();
    var bestRun = 0, run = 0;
    GameDate? prev;
    for (final d in fullDays) {
      run = (prev != null && d.difference(prev) == 1) ? run + 1 : 1;
      if (run > bestRun) bestRun = run;
      prev = d;
    }

    final completedLessonIds = {for (final c in lessons) c.lessonId};
    final perfect = {
      for (final c in lessons)
        if (c.perfect) c.lessonId,
    };

    return AchievementStats({
      AchievementMetric.totalTransactions: transactions,
      AchievementMetric.transfers: transfers,
      AchievementMetric.longestStreak: streak.longest,
      AchievementMetric.budgetsCreated: budgetKeys.length,
      AchievementMetric.cleanBudgetMonths: cleanMonths,
      AchievementMetric.bestSavingsRatePct: bestSavings,
      AchievementMetric.allPrayerDays: fullDays.length,
      AchievementMetric.bestAllPrayerRun: bestRun,
      AchievementMetric.weightDays: weightDays.length,
      AchievementMetric.healthEntries: health,
      AchievementMetric.foodLogs: food,
      AchievementMetric.lessonsCompleted: completedLessonIds.length,
      AchievementMetric.perfectLessons: perfect.length,
      AchievementMetric.unitsCompleted: path.completedUnits,
      AchievementMetric.pathPercent: (path.fraction * 100).floor(),
      AchievementMetric.level: level,
      AchievementMetric.totalXp: xp.total,
      AchievementMetric.goalDays: xp.goalDays,
    });
  }
}

class AchievementProgress {
  const AchievementProgress({
    required this.def,
    required this.current,
    required this.seen,
  });

  final AchievementDef def;

  /// Raw metric value (may exceed the target).
  final int current;
  final bool seen;

  String get id => def.id;
  int get target => def.target;
  bool get unlocked => current >= def.target;

  /// Unlocked but not yet celebrated in the UI.
  bool get isNew => unlocked && !seen;

  /// Progress clamped to the target (for "3/7").
  int get clampedCurrent => current > target ? target : current;
  double get fraction => target == 0 ? 1 : clampedCurrent / target;
}

class AchievementsState {
  const AchievementsState(this.items);

  final List<AchievementProgress> items;

  List<AchievementProgress> get unlocked =>
      items.where((a) => a.unlocked).toList();
  List<AchievementProgress> get newlyUnlocked =>
      items.where((a) => a.isNew).toList();
  int get unlockedCount => items.where((a) => a.unlocked).length;
  int get total => items.length;

  AchievementProgress? byId(String id) {
    for (final a in items) {
      if (a.id == id) return a;
    }
    return null;
  }

  static AchievementsState evaluate(
    AchievementStats stats,
    Set<String> seen, [
    List<AchievementDef> defs = achievementDefs,
  ]) => AchievementsState([
    for (final d in defs)
      AchievementProgress(
        def: d,
        current: stats[d.metric],
        seen: seen.contains(d.id),
      ),
  ]);
}
