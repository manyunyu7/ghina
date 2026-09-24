/// Read models for the tasks screens (`docs/tasks.md`).
library;

import 'task.dart';
import 'transaction.dart';

bool _listEq<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A task joined with its area, with its time-dependent flags evaluated at the
/// moment the stream emitted (streams re-evaluate every minute).
final class TaskView {
  const TaskView({
    required this.task,
    required this.area,
    required this.isOverdue,
    required this.isMepet,
    required this.isDueToday,
  });

  final Task task;

  /// Null only if the area row is missing (e.g. mid-sync).
  final TaskArea? area;

  /// Undone and past due → red "Terlambat" label.
  final bool isOverdue;

  /// WANT due today/tomorrow → "Mepet" highlight (fire color accent).
  final bool isMepet;
  final bool isDueToday;

  String get id => task.id;
  String get title => task.title;
  TaskBucket get bucket => task.bucket;
  bool get done => task.done;

  /// `[KERJA-FIRE]`
  String get tag => '[${area?.code ?? 'TUGAS'}-${task.bucket.label}]';

  @override
  bool operator ==(Object other) =>
      other is TaskView &&
      other.task == task &&
      other.area == area &&
      other.isOverdue == isOverdue &&
      other.isMepet == isMepet &&
      other.isDueToday == isDueToday;

  @override
  int get hashCode => Object.hash(task, area, isOverdue, isMepet, isDueToday);

  @override
  String toString() => 'TaskView(${task.id}, ${task.title})';
}

/// Quick filters of the board (web: Hari ini, Mepet, Terlambat, Selesai).
enum TaskStatusFilter {
  /// Undone tasks (the default board).
  open('Semua'),

  /// Undone tasks due today.
  today('Hari ini'),

  /// Undone WANT tasks due today/tomorrow.
  mepet('Mepet'),

  /// Undone tasks past due.
  overdue('Terlambat'),

  /// Completed tasks, most recently completed first.
  done('Selesai'),

  /// Everything (undone first in board order, then done).
  all('Semua + selesai');

  const TaskStatusFilter(this.label);
  final String label;
}

/// What to list. Value-equal, so it can key a Riverpod family.
final class TaskFilter {
  const TaskFilter({
    this.focusAreasOnly = false,
    this.areaIds,
    this.bucket,
    this.status = TaskStatusFilter.open,
    this.search,
  });

  /// Only the current focus areas (re-evaluated every minute). Overrides [areaIds].
  static const focus = TaskFilter(focusAreasOnly: true);

  /// All non-archived areas ("Semua").
  static const everything = TaskFilter();

  /// A single area.
  factory TaskFilter.area(
    String areaId, {
    TaskStatusFilter status = TaskStatusFilter.open,
  }) => TaskFilter(areaIds: [areaId], status: status);

  final bool focusAreasOnly;

  /// Null = every non-archived area. Archived areas are included only when listed
  /// here explicitly.
  final List<String>? areaIds;

  /// Null = all buckets.
  final TaskBucket? bucket;
  final TaskStatusFilter status;

  /// Case-insensitive match on title and note.
  final String? search;

  TaskFilter copyWith({
    bool? focusAreasOnly,
    List<String>? areaIds,
    bool clearAreaIds = false,
    TaskBucket? bucket,
    bool clearBucket = false,
    TaskStatusFilter? status,
    String? search,
  }) => TaskFilter(
    focusAreasOnly: focusAreasOnly ?? this.focusAreasOnly,
    areaIds: clearAreaIds ? null : (areaIds ?? this.areaIds),
    bucket: clearBucket ? null : (bucket ?? this.bucket),
    status: status ?? this.status,
    search: search ?? this.search,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskFilter &&
      other.focusAreasOnly == focusAreasOnly &&
      _listEq(other.areaIds, areaIds) &&
      other.bucket == bucket &&
      other.status == status &&
      other.search == search;

  @override
  int get hashCode => Object.hash(
    focusAreasOnly,
    areaIds == null ? null : Object.hashAll(areaIds!),
    bucket,
    status,
    search,
  );
}

/// One bucket's tasks on the board.
final class TaskSection {
  const TaskSection(this.bucket, this.tasks);
  final TaskBucket bucket;
  final List<TaskView> tasks;

  bool get isEmpty => tasks.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TaskSection &&
      other.bucket == bucket &&
      _listEq(other.tasks, tasks);

  @override
  int get hashCode => Object.hash(bucket, Object.hashAll(tasks));
}

/// The Tugas tab: always three sections in bucket order (fire, want, should).
final class TaskBoard {
  const TaskBoard({required this.sections, required this.areas});

  final List<TaskSection> sections;

  /// The areas the board shows (resolved focus areas, the selected ones, or all
  /// non-archived), in area order.
  final List<TaskArea> areas;

  TaskSection section(TaskBucket b) => sections[b.index];
  int get total => sections.fold(0, (s, x) => s + x.tasks.length);
  bool get isEmpty => total == 0;

  @override
  bool operator ==(Object other) =>
      other is TaskBoard &&
      _listEq(other.sections, sections) &&
      _listEq(other.areas, areas);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(sections), Object.hashAll(areas));
}

/// Focus mode at a moment (`docs/tasks.md` → Focus mode).
final class FocusAreas {
  const FocusAreas({required this.areas, required this.bySchedule});

  /// Non-archived areas whose schedule contains now; if none, the unscheduled ones.
  final List<TaskArea> areas;

  /// True when [areas] were picked because their schedule is active now (e.g.
  /// "Jam kerja"), false for the unscheduled fallback.
  final bool bySchedule;

  List<String> get ids => [for (final a in areas) a.id];

  @override
  bool operator ==(Object other) =>
      other is FocusAreas &&
      other.bySchedule == bySchedule &&
      _listEq(other.areas, areas);

  @override
  int get hashCode => Object.hash(bySchedule, Object.hashAll(areas));
}

/// What the home screen shows about tasks.
final class TaskHome {
  const TaskHome({
    required this.focus,
    required this.fireTasks,
    required this.showSapuBersih,
    required this.sapuBersih,
    required this.overdueCount,
    required this.openCount,
  });

  final FocusAreas focus;

  /// Undone FIRE tasks of the focus areas, in board order.
  final List<TaskView> fireTasks;

  /// Sunday before 12:00 → show the "Sapu bersih SHOULD 🧹" card.
  final bool showSapuBersih;

  /// Undone SHOULD tasks of unscheduled areas (computed every time; show only
  /// when [showSapuBersih]).
  final List<TaskView> sapuBersih;

  /// Undone overdue tasks in any non-archived area.
  final int overdueCount;

  /// Undone tasks in any non-archived area.
  final int openCount;

  @override
  bool operator ==(Object other) =>
      other is TaskHome &&
      other.focus == focus &&
      _listEq(other.fireTasks, fireTasks) &&
      other.showSapuBersih == showSapuBersih &&
      _listEq(other.sapuBersih, sapuBersih) &&
      other.overdueCount == overdueCount &&
      other.openCount == openCount;

  @override
  int get hashCode => Object.hash(
    focus,
    Object.hashAll(fireTasks),
    showSapuBersih,
    Object.hashAll(sapuBersih),
    overdueCount,
    openCount,
  );
}

/// The expense recorded when completing a task with a money link. [walletId] is
/// required to actually record it; the draft from `expenseDraftFor(task)` may
/// have none (let the user pick).
final class TaskExpense {
  const TaskExpense({
    required this.amount,
    this.walletId,
    this.categoryId,
    this.note,
    this.date,
  });

  final double amount;
  final String? walletId;

  /// Expense category (optional).
  final String? categoryId;

  /// Defaults to the task title.
  final String? note;

  /// Defaults to now (today).
  final DateTime? date;

  TaskExpense copyWith({
    double? amount,
    String? walletId,
    String? categoryId,
    String? note,
    DateTime? date,
  }) => TaskExpense(
    amount: amount ?? this.amount,
    walletId: walletId ?? this.walletId,
    categoryId: categoryId ?? this.categoryId,
    note: note ?? this.note,
    date: date ?? this.date,
  );
}

/// Result of completing a task.
final class TaskCompletion {
  const TaskCompletion({required this.task, this.next, this.transaction});

  /// The completed task (`done`, `doneAt`, maybe `transactionId`).
  final Task task;

  /// The next occurrence of a recurring task (created now, or already present).
  final Task? next;

  /// The expense recorded for the money link, if accepted.
  final Transaction? transaction;
}
