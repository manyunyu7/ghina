/// Level curve and Indonesian level titles.
///
/// XP needed to go from level L to L+1 is `100 + 50 * (L - 1)` (100, 150, 200, …),
/// so the cumulative XP to reach level L is `100(L-1) + 25(L-1)(L-2)`.
class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.title,
    required this.totalXp,
    required this.levelStartXp,
    required this.nextLevelXp,
    required this.nextTitle,
  });

  final int level;
  final String title;
  final int totalXp;

  /// Cumulative XP at which [level] started.
  final int levelStartXp;

  /// Cumulative XP needed for level + 1.
  final int nextLevelXp;

  /// Title of the next level if it differs from [title], else null.
  final String? nextTitle;

  int get xpIntoLevel => totalXp - levelStartXp;
  int get xpForLevel => nextLevelXp - levelStartXp;
  int get xpToNext => nextLevelXp - totalXp;

  /// 0.0 – 1.0 progress within the current level.
  double get progress => xpForLevel == 0 ? 0 : xpIntoLevel / xpForLevel;
}

abstract final class LevelCurve {
  /// (minimum level, title) — ascending.
  static const titles = <(int, String)>[
    (1, 'Receh Pemula'),
    (3, 'Pencatat Cilik'),
    (5, 'Penabung Rajin'),
    (8, 'Pejuang Anggaran'),
    (11, 'Ahli Hemat'),
    (14, 'Pemburu Promo Bijak'),
    (17, 'Juragan Celengan'),
    (20, 'Master Budget'),
    (25, 'Investor Muda'),
    (30, 'Bos Finansial'),
    (40, 'Konglomerat Cerdas'),
    (50, 'Sultan Bijak'),
  ];

  /// Cumulative XP needed to reach [level] (level 1 = 0).
  static int xpToReach(int level) {
    if (level <= 1) return 0;
    final n = level - 1;
    return 100 * n + 25 * n * (n - 1);
  }

  static int levelForXp(int xp) {
    var level = 1;
    while (xpToReach(level + 1) <= xp) {
      level++;
    }
    return level;
  }

  static String titleFor(int level) {
    var title = titles.first.$2;
    for (final (min, t) in titles) {
      if (level >= min) title = t;
    }
    return title;
  }

  static LevelInfo forXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    final level = levelForXp(safeXp);
    final title = titleFor(level);
    final next = titleFor(level + 1);
    return LevelInfo(
      level: level,
      title: title,
      totalXp: safeXp,
      levelStartXp: xpToReach(level),
      nextLevelXp: xpToReach(level + 1),
      nextTitle: next == title ? null : next,
    );
  }
}
