import 'game_date.dart';

/// User-selectable daily goal: number of counted activities per day.
enum DailyGoalLevel {
  santai(1, 'Santai', 'Santai aja, 1 aktivitas sehari'),
  reguler(3, 'Reguler', '3 aktivitas sehari, pas buat pemula'),
  serius(5, 'Serius', '5 aktivitas sehari, mulai serius nih'),
  intens(8, 'Intens', '8 aktivitas sehari, mode sultan disiplin');

  const DailyGoalLevel(this.target, this.label, this.description);

  final int target;
  final String label;
  final String description;

  static const defaultLevel = DailyGoalLevel.reguler;

  static DailyGoalLevel? byName(String name) {
    for (final l in values) {
      if (l.name == name) return l;
    }
    return null;
  }
}

/// A daily-goal setting that applies from [from] (inclusive) onwards.
class DailyGoalChange {
  const DailyGoalChange(this.from, this.level);
  final GameDate from;
  final DailyGoalLevel level;
}

/// Which goal applied on [date]. Days before the first change use the first
/// chosen level (so the history is consistent after onboarding).
DailyGoalLevel goalLevelOn(GameDate date, List<DailyGoalChange> history) {
  if (history.isEmpty) return DailyGoalLevel.defaultLevel;
  var level = history.first.level;
  var bestFrom = history.first.from;
  for (final c in history) {
    if (!c.from.isAfter(date) && !c.from.isBefore(bestFrom)) {
      level = c.level;
      bestFrom = c.from;
    }
  }
  return level;
}

class DailyGoalProgress {
  const DailyGoalProgress({required this.level, required this.done});

  final DailyGoalLevel level;

  /// Counted activities today.
  final int done;

  int get target => level.target;
  bool get isMet => done >= target;
  int get remaining => isMet ? 0 : target - done;

  /// 0.0 – 1.0 for the goal ring.
  double get fraction => target == 0 ? 1 : (done / target).clamp(0.0, 1.0);
}
