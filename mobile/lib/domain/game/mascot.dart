/// Mascot mood + Duolingo-style Indonesian nudges.
enum MascotMood {
  /// Goal met / milestone: party time.
  celebrating,

  /// All good, streak safe.
  happy,

  /// Morning / midday nudge to log something.
  encouraging,

  /// Streak at risk late in the day, or hearts low.
  worried,

  /// Streak lost or no hearts left.
  sad,

  /// Night and nothing urgent.
  sleeping,
}

/// Everything the mascot looks at.
class MascotContext {
  const MascotContext({
    required this.now,
    required this.streak,
    required this.loggedToday,
    required this.goalMet,
    required this.goalRemaining,
    required this.hearts,
    required this.maxHearts,
    this.longestStreak = 0,
    this.hasAnyActivity = true,
    this.name,
    this.overdueTasks = 0,
    this.fireOpen = 0,
    this.hasTasks = false,
  });

  final DateTime now;
  final int streak;
  final bool loggedToday;
  final bool goalMet;
  final int goalRemaining;
  final int hearts;
  final int maxHearts;
  final int longestStreak;

  /// False for brand-new users (no transaction ever).
  final bool hasAnyActivity;

  /// Optional first name for personal messages.
  final String? name;

  /// Undone overdue tasks (any area). 0 when task info isn't known.
  final int overdueTasks;

  /// Undone FIRE tasks in the current focus areas.
  final int fireOpen;

  /// Task info is known and the user has tasks at all (enables task lines).
  final bool hasTasks;

  /// Enough overdue tasks for a worried nudge.
  bool get manyOverdue => overdueTasks >= Mascot.manyOverdue;

  /// The same context with task info (from the home's task summary).
  MascotContext withTasks({
    required int overdueTasks,
    required int fireOpen,
    required bool hasTasks,
  }) => MascotContext(
    now: now,
    streak: streak,
    loggedToday: loggedToday,
    goalMet: goalMet,
    goalRemaining: goalRemaining,
    hearts: hearts,
    maxHearts: maxHearts,
    longestStreak: longestStreak,
    hasAnyActivity: hasAnyActivity,
    name: name,
    overdueTasks: overdueTasks,
    fireOpen: fireOpen,
    hasTasks: hasTasks,
  );

  bool get atRisk => streak > 0 && !loggedToday;
  bool get isNight => now.hour >= 22 || now.hour < 5;
  bool get isLateInDay => now.hour >= 18;
}

abstract final class Mascot {
  /// Overdue tasks from which the mascot gets worried.
  static const manyOverdue = 3;

  static MascotMood moodFor(MascotContext c) {
    if (c.atRisk && (c.isLateInDay || c.isNight)) return MascotMood.worried;
    if (c.isNight) return MascotMood.sleeping;
    if (c.goalMet) return MascotMood.celebrating;
    if (c.hearts == 0) return MascotMood.sad;
    if (c.hasAnyActivity &&
        c.streak == 0 &&
        c.longestStreak > 0 &&
        !c.loggedToday) {
      return MascotMood.sad;
    }
    if (c.hearts <= 1) return MascotMood.worried;
    if (c.manyOverdue) return MascotMood.worried;
    if (!c.loggedToday) return MascotMood.encouraging;
    return MascotMood.happy;
  }

  /// Message variants per mood. Placeholders: {streak}, {remaining}, {hearts}, {name}.
  static const messages = <MascotMood, List<String>>{
    MascotMood.celebrating: [
      'Target harian beres! Kamu keren banget 🎉',
      'Goal hari ini tercapai! Dompetmu bangga sama kamu 💸',
      'Mantap {name}! Streak {streak} hari dan target aman 🔥',
      'Wih, rajin banget! Besok gas lagi ya 🚀',
      'Checklist hari ini: lengkap! Waktunya rebahan dengan tenang 😌',
    ],
    MascotMood.happy: [
      'Streak {streak} hari! Tinggal {remaining} aktivitas lagi buat target 💪',
      'Udah nyatet hari ini, mantul! Yuk kejar targetnya 🎯',
      'Keuanganmu makin rapi nih. Lanjutkan! ✨',
      'Satu langkah kecil tiap hari = dompet sehat. Keren!',
      'Aku senang banget lihat kamu konsisten 😄',
    ],
    MascotMood.encouraging: [
      'Belum nyatet hari ini? Dompetmu kangen lho 👀',
      'Yuk catat satu transaksi, cuma 10 detik kok ⏱️',
      'Kopi pagi tadi udah dicatat belum? ☕',
      'Streak {streak} hari menunggumu. Jangan dicuekin ya!',
      'Hari baru, catatan baru! Mulai dari satu transaksi aja 🌱',
      'Uang yang dicatat nggak akan hilang tanpa jejak 🕵️',
    ],
    MascotMood.worried: [
      'Streak {streak} harimu dalam bahaya! Catat sekarang sebelum tengah malam 😱',
      'Aku deg-degan nih… belum ada catatan hari ini 🥺',
      'Tinggal beberapa jam lagi! Satu transaksi aja bisa selamatkan streak 🔥',
      'Hati tinggal {hearts}… yuk rem dulu belanjanya 🫣',
      'Jangan biarin streak {streak} hari hangus gitu aja 😭',
    ],
    MascotMood.sad: [
      'Streak-nya putus… tapi nggak apa-apa, mulai lagi hari ini yuk 🌤️',
      'Hatiku habis… anggaran bulan ini jebol semua 💔',
      'Aku sedih, tapi aku percaya kamu bisa bangkit! 💪',
      'Rekor terbaikmu {longest} hari. Yuk pecahkan lagi!',
    ],
    MascotMood.sleeping: [
      'Zzz… udah malam, besok kita nyatet lagi ya 😴',
      'Selamat istirahat! Streak kamu aman kok 🌙',
      'Ngantuk… tapi bangga sama kamu hari ini 💤',
      'Tidur yang nyenyak, dompetmu juga lagi istirahat 🛌',
    ],
  };

  /// Task-aware lines (`docs/tasks.md`). Placeholders: {overdue}, {fire}.
  static const taskMessages = <String, List<String>>{
    // Worried because many tasks are overdue (replaces the worried pool).
    'overdue': [
      'Ada {overdue} tugas yang terlambat nih 😬 Yuk beresin satu-satu!',
      'Tugasnya numpuk, {overdue} udah lewat tenggat… mulai dari yang FIRE dulu ya 🔥',
      '{overdue} tugas terlambat. Aku semangatin, kamu yang eksekusi 💪',
    ],
    // Mixed into the encouraging/happy pool while FIRE tasks are open.
    'fire': [
      'Masih ada {fire} tugas FIRE 🔥 Beresin dulu, baru santai!',
      'Satu tugas FIRE selesai = satu beban hilang. Gas! 🔥',
    ],
    // Mixed into the happy/celebrating pool when FIRE is empty.
    'fireClear': [
      'FIRE kosong! Fokusmu hari ini juara 🧯',
      'Nggak ada tugas FIRE tersisa. Tenang banget rasanya 😌',
    ],
  };

  /// A message for [mood]. Deterministic for a given [seed] (defaults to the
  /// day + hour, so the line doesn't flicker on every rebuild).
  static String messageFor(MascotMood mood, MascotContext c, {int? seed}) {
    var pool = messages[mood]!;
    // Skip lines that make no sense for the current numbers.
    pool = pool.where((m) {
      if (m.contains('{streak}') && c.streak == 0) return false;
      if (m.contains('{remaining}') && c.goalRemaining == 0) return false;
      if (m.contains('{name}') && (c.name == null || c.name!.isEmpty)) {
        return false;
      }
      if (m.contains('{longest}') && c.longestStreak == 0) return false;
      if (mood == MascotMood.worried) {
        final heartLine = m.contains('{hearts}');
        final heartsLow = c.hearts <= 1;
        if (heartLine != (heartsLow && !c.atRisk)) return false;
      }
      if (mood == MascotMood.sad &&
          m.contains('Hatiku habis') &&
          c.hearts > 0) {
        return false;
      }
      if (mood == MascotMood.sad &&
          !m.contains('Hatiku habis') &&
          c.hearts == 0 &&
          c.streak > 0) {
        return false;
      }
      return true;
    }).toList();
    if (pool.isEmpty) pool = [messages[mood]!.first];
    if (mood == MascotMood.worried &&
        c.manyOverdue &&
        !c.atRisk &&
        c.hearts > 1) {
      // Worried only because of the overdue tasks.
      pool = taskMessages['overdue']!;
    } else if (c.hasTasks) {
      if (c.fireOpen > 0 &&
          (mood == MascotMood.encouraging || mood == MascotMood.happy)) {
        pool = [...pool, ...taskMessages['fire']!];
      } else if (c.fireOpen == 0 &&
          (mood == MascotMood.happy || mood == MascotMood.celebrating)) {
        pool = [...pool, ...taskMessages['fireClear']!];
      }
    }
    final s =
        seed ??
        (c.now.year * 10000 + c.now.month * 100 + c.now.day) * 24 + c.now.hour;
    final line = pool[s.abs() % pool.length];
    return line
        .replaceAll('{streak}', '${c.streak}')
        .replaceAll('{remaining}', '${c.goalRemaining}')
        .replaceAll('{hearts}', '${c.hearts}')
        .replaceAll('{longest}', '${c.longestStreak}')
        .replaceAll('{overdue}', '${c.overdueTasks}')
        .replaceAll('{fire}', '${c.fireOpen}')
        .replaceAll('{name}', c.name ?? '');
  }
}
