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

  /// Complete days (all 5 fardhu prayed).
  allPrayerDays,

  /// Longest run of complete days (excused days are neutral).
  bestAllPrayerRun,

  /// Longest run of consecutive days with Subuh in congregation (masjid/jamaah).
  bestSubuhJamaahRun,

  /// Longest run of consecutive days with the same fardhu prayed at the masjid.
  bestMasjidRun,
  tahajudCount,

  /// Days with all 5 rawatib muakkad done.
  fullRawatibDays,
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
    id: 'prayers_complete_30',
    title: 'Tiga Puluh Hari Lengkap',
    description: 'Lengkap lima waktu di 30 hari (boleh nggak berturut-turut).',
    icon: 'event_available',
    tier: AchievementTier.gold,
    metric: AchievementMetric.allPrayerDays,
    target: 30,
  ),
  AchievementDef(
    id: 'subuh_jamaah_7',
    title: 'Pejuang Subuh',
    description: 'Subuh berjamaah 7 hari berturut-turut.',
    icon: 'wb_twilight',
    tier: AchievementTier.silver,
    metric: AchievementMetric.bestSubuhJamaahRun,
    target: 7,
  ),
  AchievementDef(
    id: 'masjid_week',
    title: 'Anak Masjid',
    description:
        'Seminggu penuh salat di masjid untuk satu waktu yang sama (misalnya Isya).',
    icon: 'mosque',
    tier: AchievementTier.gold,
    metric: AchievementMetric.bestMasjidRun,
    target: 7,
  ),
  AchievementDef(
    id: 'tahajud_10',
    title: 'Sahabat Malam',
    description: 'Tahajud 10 kali.',
    icon: 'nights_stay',
    tier: AchievementTier.silver,
    metric: AchievementMetric.tahajudCount,
    target: 10,
  ),
  AchievementDef(
    id: 'rawatib_full_day',
    title: 'Rawatib Komplet',
    description:
        'Kerjakan kelima rawatib muakkad dalam sehari (qobliyah Subuh & Dzuhur, ba\'diyah Dzuhur, Maghrib & Isya).',
    icon: 'auto_awesome',
    tier: AchievementTier.silver,
    metric: AchievementMetric.fullRawatibDays,
    target: 1,
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
    // Prayer rows per day: name → event (deduped by id above).
    final prayersByDay = <GameDate, Map<String, ActivityEvent>>{};
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
          if (e.isFardhu || e.isSunnah) {
            prayersByDay.putIfAbsent(e.day, () => {})[e.prayer!] = e;
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

    final prayers = PrayerStats.compute(prayersByDay);

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
      AchievementMetric.allPrayerDays: prayers.completeDays,
      AchievementMetric.bestAllPrayerRun: prayers.bestCompleteRun,
      AchievementMetric.bestSubuhJamaahRun: prayers.bestSubuhJamaahRun,
      AchievementMetric.bestMasjidRun: prayers.bestMasjidRun,
      AchievementMetric.tahajudCount: prayers.tahajud,
      AchievementMetric.fullRawatibDays: prayers.fullRawatibDays,
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

/// Prayer numbers for achievements (spec `docs/prayer-quality.md`).
class PrayerStats {
  const PrayerStats({
    required this.completeDays,
    required this.bestCompleteRun,
    required this.bestSubuhJamaahRun,
    required this.bestMasjidRun,
    required this.tahajud,
    required this.fullRawatibDays,
  });

  final int completeDays;
  final int bestCompleteRun;
  final int bestSubuhJamaahRun;
  final int bestMasjidRun;
  final int tahajud;
  final int fullRawatibDays;

  /// [byDay]: day → prayer name → row.
  static PrayerStats compute(Map<GameDate, Map<String, ActivityEvent>> byDay) {
    final days = byDay.keys.toList()..sort();
    var complete = 0, tahajud = 0, fullRawatib = 0;
    // Complete-day runs: excused days (≥1 excused, rest prayed) are neutral.
    var bestRun = 0, run = 0;
    GameDate? prev;
    for (final d in days) {
      final rows = byDay[d]!;
      if (rows.containsKey('tahajud')) tahajud++;
      final rawatib = rows.values
          .where((e) => e.isPrayedFardhu)
          .fold(0, (s, e) => s + e.rawatibCount);
      if (rawatib >= rawatibSlotsPerDay) fullRawatib++;

      var prayed = 0, excused = 0;
      for (final name in prayerNames) {
        final e = rows[name];
        if (e == null) continue;
        if (e.isPrayedFardhu) prayed++;
        if (e.prayerStatus == 'excused') excused++;
      }
      final isComplete = prayed == prayerNames.length;
      final isExcused =
          !isComplete && excused > 0 && prayed + excused == prayerNames.length;
      if (isComplete) complete++;
      // A gap of missing days (or an incomplete day) breaks the run; excused
      // days bridge it without counting.
      if (isComplete) {
        run = (prev != null && d.difference(prev) == 1) ? run + 1 : 1;
        if (run > bestRun) bestRun = run;
        prev = d;
      } else if (isExcused) {
        if (prev != null && d.difference(prev) == 1) prev = d;
      } else {
        run = 0;
        prev = null;
      }
    }

    int bestRunWhere(bool Function(Map<String, ActivityEvent> rows) ok) {
      var best = 0, cur = 0;
      GameDate? last;
      for (final d in days) {
        if (!ok(byDay[d]!)) {
          cur = 0;
          last = null;
          continue;
        }
        cur = (last != null && d.difference(last) == 1) ? cur + 1 : 1;
        if (cur > best) best = cur;
        last = d;
      }
      return best;
    }

    final subuh = bestRunWhere((rows) {
      final s = rows['subuh']?.prayerStatus;
      return s == 'masjid' || s == 'jamaah';
    });
    var masjid = 0;
    for (final name in prayerNames) {
      final r = bestRunWhere((rows) => rows[name]?.prayerStatus == 'masjid');
      if (r > masjid) masjid = r;
    }
    return PrayerStats(
      completeDays: complete,
      bestCompleteRun: bestRun,
      bestSubuhJamaahRun: subuh,
      bestMasjidRun: masjid,
      tahajud: tahajud,
      fullRawatibDays: fullRawatib,
    );
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
