/// Game ⇄ tasks glue (`docs/tasks.md` → Gamification) that needs the live task
/// list, not just the done-task events: the "FIRE kosong" daily snapshot and the
/// task-aware mascot line. Kept apart from `game_providers.dart` so the engine's
/// providers (and their tests) never depend on the task repositories.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/game/game.dart';
import 'game_providers.dart';

/// Every task of the non-archived areas, done or not.
const _allTasks = TaskFilter(status: TaskStatusFilter.all);

/// Maps a [Task] for [wasFireClear].
FireCheckTask fireCheckTaskOf(Task t) => FireCheckTask(
  areaId: t.areaId,
  bucket: t.bucket.wire,
  createdAt: t.createdAt,
  done: t.done,
  doneAt: t.done ? (t.doneAt ?? t.updatedAt) : null,
  dueDate: t.dueDate == null ? null : GameDate.tryParse(t.dueDate!),
);

/// Maps a [TaskArea] for [wasFireClear].
FireCheckArea fireCheckAreaOf(TaskArea a) => FireCheckArea(
  id: a.id,
  scheduleDays: a.schedule?.days.toSet(),
  archived: a.archived,
);

/// The "FIRE kosong" snapshot recorder (rules + limitations: `fire_clear.dart`).
///
/// Evaluates *yesterday* whenever the task list, the areas or the hour changes
/// (so the first open of a day and the tick crossing midnight both work) and,
/// when yesterday was FIRE-free, records it in local game state (add-only, once).
/// Returns the day it recorded (or found recorded), else null.
///
/// Home keeps it alive with `ref.listen(fireClearRecorderProvider, …)`; only
/// days on which the app runs get evaluated.
final fireClearRecorderProvider = Provider.autoDispose<GameDate?>((ref) {
  ref.watch(gameTickProvider);
  final tasks = ref.watch(watchTasksProvider(_allTasks)).value;
  final areas = ref.watch(watchTaskAreasProvider).value;
  final local = ref.watch(gameLocalStateProvider).value;
  if (tasks == null || areas == null || local == null) return null;
  final yesterday = GameDate.fromDateTime(
    ref.read(gameClockProvider).now(),
  ).addDays(-1);
  if (local.fireClearDays.contains(yesterday)) return yesterday;
  final clear = wasFireClear(
    yesterday,
    [for (final v in tasks) fireCheckTaskOf(v.task)],
    [for (final a in areas) fireCheckAreaOf(a)],
  );
  if (!clear) return null;
  final controller = ref.read(gameLocalStateProvider.notifier);
  scheduleMicrotask(() {
    controller.apply((s) => const RecordFireClearDay()(s, yesterday)).ignore();
  });
  return yesterday;
});

/// What the home mascot says.
class MascotLine {
  const MascotLine(this.mood, this.message);
  final MascotMood mood;
  final String message;
}

/// The game summary's mascot with task info mixed in (many overdue tasks →
/// worried nudge, open FIRE tasks / FIRE kosong lines). Falls back to the plain
/// summary line while tasks load (or when they fail). Null until the summary
/// is loaded.
final homeMascotProvider = Provider.autoDispose<MascotLine?>((ref) {
  final s = ref.watch(gameSummaryProvider).value;
  if (s == null) return null;
  final home = ref.watch(watchTaskHomeProvider).value;
  final ctx = s.mascot;
  if (home == null || ctx == null) return MascotLine(s.mood, s.message);
  final doneToday = s.xp.dayOf(s.today)?.tasksTotal ?? 0;
  final c = ctx.withTasks(
    overdueTasks: home.overdueCount,
    fireOpen: home.fireTasks.length,
    hasTasks: home.openCount > 0 || doneToday > 0,
  );
  final mood = Mascot.moodFor(c);
  return MascotLine(mood, Mascot.messageFor(mood, c));
});
