import 'game_date.dart';
import 'xp_rules.dart';

/// Status of a single calendar day in the streak history.
enum StreakDayStatus {
  /// At least one transaction was logged that day.
  logged,

  /// Missed, but a streak freeze kept the streak alive.
  frozen,

  /// Missed (streak broken or no streak running).
  missed,

  /// Today, nothing logged yet (streak still alive, maybe at risk).
  pending,

  /// Before the first logged day, or in the future.
  none,
}

/// A streak reaching a milestone length on [date].
class StreakMilestoneHit {
  const StreakMilestoneHit(this.date, this.length);
  final GameDate date;
  final int length;

  @override
  bool operator ==(Object other) =>
      other is StreakMilestoneHit &&
      other.date == date &&
      other.length == length;

  @override
  int get hashCode => Object.hash(date, length);

  @override
  String toString() => 'StreakMilestoneHit($date, $length)';
}

class CalendarDay {
  const CalendarDay(this.date, this.status);
  final GameDate date;
  final StreakDayStatus status;
}

/// Result of simulating the transaction streak day by day up to today.
class StreakResult {
  const StreakResult({
    required this.today,
    required this.current,
    required this.longest,
    required this.loggedToday,
    required this.freezesHeld,
    required this.days,
    required this.milestones,
    required this.freezesEarned,
    required this.newlyFrozenDays,
  });

  static StreakResult empty(GameDate today) => StreakResult(
    today: today,
    current: 0,
    longest: 0,
    loggedToday: false,
    freezesHeld: 0,
    days: const {},
    milestones: const [],
    freezesEarned: const [],
    newlyFrozenDays: const {},
  );

  final GameDate today;

  /// Current streak length (includes today if logged today).
  final int current;
  final int longest;
  final bool loggedToday;

  /// Streak freezes owned right now (0..[XpRules.maxFreezesHeld]).
  final int freezesHeld;
  int get maxFreezes => XpRules.maxFreezesHeld;

  /// Status per day from the first relevant day to today (inclusive).
  final Map<GameDate, StreakDayStatus> days;

  /// Every time the streak reached a milestone length ([XpRules.streakMilestones]).
  final List<StreakMilestoneHit> milestones;

  /// Days on which a freeze was earned from a 7-day milestone.
  final List<GameDate> freezesEarned;

  /// Frozen days that were not yet recorded locally — persist them
  /// (see `RecordUsedFreezes`) so the result stays stable if data changes.
  final Set<GameDate> newlyFrozenDays;

  /// Streak alive but today not logged yet.
  bool get atRisk => current > 0 && !loggedToday;

  bool get isActive => current > 0;

  Set<GameDate> get frozenDays => {
    for (final e in days.entries)
      if (e.value == StreakDayStatus.frozen) e.key,
  };

  /// First day of the current streak (null when no streak).
  GameDate? get currentStart {
    if (current == 0) return null;
    var d = loggedToday ? today : today.addDays(-1);
    GameDate? start;
    while (true) {
      final s = days[d];
      if (s == StreakDayStatus.logged) {
        start = d;
      } else if (s != StreakDayStatus.frozen) {
        break;
      }
      d = d.addDays(-1);
    }
    return start;
  }

  /// A milestone reached today, if any (for the celebration screen).
  StreakMilestoneHit? get milestoneToday {
    for (final m in milestones.reversed) {
      if (m.date == today) return m;
    }
    return null;
  }

  /// Next milestone length above [current], null past the last one.
  int? get nextMilestone {
    for (final m in XpRules.streakMilestones.keys) {
      if (m > current) return m;
    }
    return null;
  }

  StreakDayStatus statusOn(GameDate date) => days[date] ?? StreakDayStatus.none;

  /// Calendar data for one month (every day of the month, in order).
  List<CalendarDay> month(int year, int month) {
    final gm = GameMonth(year, month);
    return [
      for (var d = gm.firstDay; !d.isAfter(gm.lastDay); d = d.addDays(1))
        CalendarDay(d, statusOn(d)),
    ];
  }
}

/// Pure streak simulation.
///
/// Walks every day from the first logged transaction day (or first freeze
/// grant) to [today]:
/// - logged day: streak +1; every [XpRules.freezeEveryDays] days of streak earns a
///   freeze (max [XpRules.maxFreezesHeld] held); milestones are recorded.
/// - missed past day while a streak runs: if the day is in [recordedFrozenDays]
///   it stays frozen (stable); else a held freeze is consumed automatically
///   (up to [XpRules.maxConsecutiveFrozenDays] in a row); else the streak resets.
///   Frozen days keep the streak alive but don't add to its length.
/// - today without a log: pending — the streak is alive but "at risk".
abstract final class StreakCalculator {
  static StreakResult compute({
    required Iterable<GameDate> loggedDays,
    required GameDate today,
    Set<GameDate> recordedFrozenDays = const {},
    Iterable<GameDate> grantedFreezes = const [],
  }) {
    final logged = {
      for (final d in loggedDays)
        if (!d.isAfter(today)) d,
    };
    final grants = <GameDate, int>{};
    for (final g in grantedFreezes) {
      if (!g.isAfter(today)) grants[g] = (grants[g] ?? 0) + 1;
    }
    if (logged.isEmpty && grants.isEmpty) return StreakResult.empty(today);

    GameDate? start;
    for (final d in [...logged, ...grants.keys]) {
      if (start == null || d.isBefore(start)) start = d;
    }

    final days = <GameDate, StreakDayStatus>{};
    final milestones = <StreakMilestoneHit>[];
    final earned = <GameDate>[];
    final newlyFrozen = <GameDate>{};
    var streak = 0, longest = 0, freezes = 0, frozenRun = 0;
    var seenFirstLog = false;

    for (var d = start!; !d.isAfter(today); d = d.addDays(1)) {
      final granted = grants[d];
      if (granted != null) freezes = _cap(freezes + granted);

      if (logged.contains(d)) {
        seenFirstLog = true;
        streak++;
        frozenRun = 0;
        if (streak > longest) longest = streak;
        days[d] = StreakDayStatus.logged;
        if (streak % XpRules.freezeEveryDays == 0) {
          freezes = _cap(freezes + 1);
          earned.add(d);
        }
        if (XpRules.streakMilestones.containsKey(streak)) {
          milestones.add(StreakMilestoneHit(d, streak));
        }
      } else if (d == today) {
        days[d] = seenFirstLog ? StreakDayStatus.pending : StreakDayStatus.none;
      } else if (!seenFirstLog) {
        days[d] = StreakDayStatus.none;
      } else if (streak > 0 && recordedFrozenDays.contains(d)) {
        // Previously recorded: keep it frozen even if freezes no longer add up.
        days[d] = StreakDayStatus.frozen;
        frozenRun++;
        if (freezes > 0) freezes--;
      } else if (streak > 0 &&
          freezes > 0 &&
          frozenRun < XpRules.maxConsecutiveFrozenDays) {
        freezes--;
        frozenRun++;
        days[d] = StreakDayStatus.frozen;
        newlyFrozen.add(d);
      } else {
        streak = 0;
        frozenRun = 0;
        days[d] = StreakDayStatus.missed;
      }
    }

    return StreakResult(
      today: today,
      current: streak,
      longest: longest,
      loggedToday: logged.contains(today),
      freezesHeld: freezes,
      days: days,
      milestones: milestones,
      freezesEarned: earned,
      newlyFrozenDays: newlyFrozen,
    );
  }

  static int _cap(int v) =>
      v > XpRules.maxFreezesHeld ? XpRules.maxFreezesHeld : v;
}
