import 'game_date.dart';

/// "FIRE kosong" (`docs/tasks.md` → Gamification): a day that ended with 0
/// undone FIRE tasks in its focus areas. Unlike everything else in the engine
/// this can't be derived from the done-task events alone (it needs the *undone*
/// tasks at the end of a day), so the app takes a local daily snapshot:
///
/// * On any day D the app is running (first open of the day, or the hourly tick
///   crossing midnight) it evaluates D−1 with [wasFireClear] from the current
///   task list and records the day in `GameLocalState.fireClearDays`
///   (`RecordFireClearDay`). Only yesterday is ever evaluated, so days the app
///   wasn't opened the day after are simply not counted.
/// * Records are add-only: a later evaluation (e.g. before the first sync after
///   signing in again, when the task list is still empty) never removes a day.
/// * Limitations (documented, accepted): the state at the end of D−1 is
///   reconstructed from `createdAt` / `doneAt`, so tasks deleted or moved out of
///   FIRE since then, and area schedule changes, aren't seen; the snapshot is
///   local to this device (not synced; a reinstall starts from 0).
///
/// Rules for day D:
/// * focus areas of D = non-archived areas without a schedule, plus the ones
///   whose schedule includes D's weekday (every area that was "in focus" at some
///   point that day);
/// * a FIRE task in those areas was undone at the end of D when it existed by
///   then (`createdAt` < D+1 00:00), was due by D or has no due date (future
///   occurrences of a recurring task don't count), and was not done by then;
/// * the day counts only when at least one FIRE task of those areas was
///   completed on D, so an empty task list doesn't farm the badge.
bool wasFireClear(
  GameDate day,
  Iterable<FireCheckTask> tasks,
  Iterable<FireCheckArea> areas,
) {
  final focus = {
    for (final a in areas)
      if (!a.archived &&
          (a.scheduleDays == null || a.scheduleDays!.contains(day.weekday)))
        a.id,
  };
  if (focus.isEmpty) return false;
  final start = day.toLocalDateTime();
  final end = day.addDays(1).toLocalDateTime();
  var doneThatDay = false;
  for (final t in tasks) {
    if (!t.isFire || !focus.contains(t.areaId)) continue;
    final doneAt = t.done ? t.doneAt : null;
    if (doneAt != null && !doneAt.isBefore(start) && doneAt.isBefore(end)) {
      doneThatDay = true;
    }
    if (!t.createdAt.isBefore(end)) continue; // didn't exist yet
    final due = t.dueDate;
    if (due != null && due.isAfter(day)) continue; // not due yet
    final undoneAtEnd = doneAt == null || !doneAt.isBefore(end);
    if (undoneAtEnd) return false;
  }
  return doneThatDay;
}

/// The engine's view of a task for [wasFireClear] (mapped from `Task`).
class FireCheckTask {
  const FireCheckTask({
    required this.areaId,
    required this.bucket,
    required this.createdAt,
    this.done = false,
    this.doneAt,
    this.dueDate,
  });

  final String areaId;

  /// `fire | want | should`.
  final String bucket;
  final DateTime createdAt;
  final bool done;
  final DateTime? doneAt;
  final GameDate? dueDate;

  bool get isFire => bucket == 'fire';
}

/// The engine's view of a task area for [wasFireClear] (mapped from `TaskArea`).
class FireCheckArea {
  const FireCheckArea({
    required this.id,
    this.scheduleDays,
    this.archived = false,
  });

  final String id;

  /// ISO weekdays (1 = Monday) of the area's schedule; null = no schedule.
  final Set<int>? scheduleDays;
  final bool archived;
}
