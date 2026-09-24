/// Pure task rules — a port of the server's `src/lib/tasks.ts` (`docs/tasks.md`).
/// Constants and algorithms must match it exactly.
library;

import '../../core/dates.dart';
import '../../core/formatters.dart';
import '../entities/entities.dart';

// ---------------------------------------------------------------- constants

const taskTitleMax = 200;
const taskNoteMax = 2000;
const areaNameMax = 40;
const areaCodeMax = 8;
final areaCodeRe = RegExp(r'^[A-Z0-9]{1,8}$');

/// `seriesId` + `_YYYYMMDD` must fit the 64-char sync id limit.
final seriesIdRe = RegExp(r'^[A-Za-z0-9_-]{1,55}$');

/// Reminder presets offered by the UI (minutes before due; 0 = at due time).
const remindBeforeOptions = [0, 10, 30, 60];

/// Largest accepted `remindBefore` (7 days).
const remindBeforeMax = 7 * 24 * 60;

/// Max local notifications scheduled (soonest first).
const maxTaskNotifications = 60;

/// Completed tasks counted for XP per local day (gamification).
const taskXpDailyCap = 20;
const defaultAreaColor = '#58CC02';
const defaultAreaIcon = 'briefcase';
const mepetLabel = 'Mepet';
const overdueLabel = 'Terlambat';

/// ARGB of the "Terlambat" label (`#FF4B4B`).
const overdueColor = 0xFFFF4B4B;

// ---------------------------------------------------------------- date keys

/// `YYYY-MM-DD` + [n] days.
String addDaysKey(String key, int n) {
  final d = parseDateKey(key);
  return dateKey(DateTime(d.year, d.month, d.day + n));
}

/// ISO weekday of a date key: 1 = Monday … 7 = Sunday.
int isoWeekdayOfKey(String key) => parseDateKey(key).weekday;

/// Local `HH:mm` of [d].
String hmOf(DateTime d) => formatHm(d.hour, d.minute);

// ---------------------------------------------------------------- recurrence

/// Fills the rule's defaults from the due date so later occurrences never drift
/// (31 → 28 → 28 …): weekly gets `weekdays` = [due weekday], monthly gets
/// `monthDay` = due day.
Recurrence normalizeRecurrence(Recurrence r, String dueDate) =>
    switch (r.freq) {
      RecurrenceFreq.daily => Recurrence(freq: r.freq, interval: r.interval),
      RecurrenceFreq.weekly => Recurrence(
        freq: r.freq,
        interval: r.interval,
        weekdays: r.weekdays != null && r.weekdays!.isNotEmpty
            ? (r.weekdays!.toSet().toList()..sort())
            : [isoWeekdayOfKey(dueDate)],
      ),
      RecurrenceFreq.monthly => Recurrence(
        freq: r.freq,
        interval: r.interval,
        monthDay: r.monthDay ?? int.parse(dueDate.substring(8, 10)),
      ),
    };

/// Next due date after [dueDate] under [rule], computed from the current due date
/// (not today). weekly: the next listed weekday later in the same ISO week, else
/// the first listed weekday `interval` weeks later. monthly: `monthDay` later in
/// the same month if still ahead, else `interval` months later — clamped to the
/// month's last day (31 → 30/28/29).
String nextDueDate(Recurrence rule, String dueDate) {
  final r = normalizeRecurrence(rule, dueDate);
  switch (r.freq) {
    case RecurrenceFreq.daily:
      return addDaysKey(dueDate, r.interval);
    case RecurrenceFreq.weekly:
      final days = r.weekdays!;
      final wd = isoWeekdayOfKey(dueDate);
      for (final d in days) {
        if (d > wd) return addDaysKey(dueDate, d - wd);
      }
      final weekStart = addDaysKey(dueDate, -(wd - 1));
      return addDaysKey(weekStart, 7 * r.interval + (days.first - 1));
    case RecurrenceFreq.monthly:
      final md = r.monthDay!;
      final d = parseDateKey(dueDate);
      final sameMonth = md < daysInMonth(d.year, d.month)
          ? md
          : daysInMonth(d.year, d.month);
      if (sameMonth > d.day) {
        return dateKey(DateTime(d.year, d.month, sameMonth));
      }
      final idx = d.year * 12 + (d.month - 1) + r.interval;
      final ny = idx ~/ 12, nm = idx % 12 + 1;
      final dim = daysInMonth(ny, nm);
      return dateKey(DateTime(ny, nm, md < dim ? md : dim));
  }
}

/// Deterministic id of an occurrence: `<seriesId>_<YYYYMMDD>`.
String occurrenceId(String seriesId, String dueDate) =>
    '${seriesId}_${dueDate.replaceAll('-', '')}';

/// The occurrence that follows [task] when it is completed, or null for a one-off
/// task (or one without a due date). Same fields, `done=false`, next due date,
/// `transactionId` null, deterministic id. Timestamps are [now].
Task? nextOccurrence(Task task, DateTime now) {
  final rule = task.recurrence;
  final due = task.dueDate;
  if (rule == null || due == null || !isDateKey(due)) return null;
  final seriesId = task.seriesId ?? task.id;
  final next = nextDueDate(rule, due);
  return Task(
    id: occurrenceId(seriesId, next),
    areaId: task.areaId,
    title: task.title,
    note: task.note,
    bucket: task.bucket,
    dueDate: next,
    dueTime: task.dueTime,
    remindBefore: task.remindBefore,
    recurrence: normalizeRecurrence(rule, due),
    seriesId: seriesId,
    done: false,
    doneAt: null,
    sortOrder: task.sortOrder,
    amount: task.amount,
    walletId: task.walletId,
    categoryId: task.categoryId,
    transactionId: null,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------- status

/// A WANT task due today or tomorrow — highlighted, never moved automatically.
bool isMepet(Task t, DateTime now) {
  final due = t.dueDate;
  if (t.bucket != TaskBucket.want || t.done || due == null) return false;
  final today = dateKey(now);
  return due.compareTo(today) >= 0 && due.compareTo(addDaysKey(today, 1)) <= 0;
}

/// Undone and past due: a date-only task after its day ends, a timed one after
/// its time (minute precision: due 14:00 is overdue from 14:01).
bool isOverdue(Task t, DateTime now) {
  final due = t.dueDate;
  if (t.done || due == null) return false;
  final today = dateKey(now);
  if (due.compareTo(today) < 0) return true;
  return due == today &&
      t.dueTime != null &&
      t.dueTime!.compareTo(hmOf(now)) < 0;
}

/// Due on [now]'s local day (done or not).
bool isDueToday(Task t, DateTime now) => t.dueDate == dateKey(now);

// ---------------------------------------------------------------- focus mode

/// The area's schedule contains [now] (local).
bool isAreaActive(TaskArea a, DateTime now) =>
    a.schedule?.contains(now) ?? false;

/// Focus areas at [now]: non-archived areas whose schedule contains now; if none
/// match, the non-archived areas without a schedule. Keeps the input order (pass
/// areas sorted with [compareAreas]).
List<TaskArea> focusAreas(List<TaskArea> areas, DateTime now) {
  final live = areas.where((a) => !a.archived).toList();
  final active = live.where((a) => isAreaActive(a, now)).toList();
  if (active.isNotEmpty) return active;
  return live.where((a) => a.schedule == null).toList();
}

/// Sunday before 12:00 → the home shows the "Sapu bersih SHOULD 🧹" card.
bool isSapuBersihTime(DateTime now) =>
    now.weekday == DateTime.sunday && now.hour < 12;

/// Undone SHOULD tasks of non-archived areas without a schedule, in board order.
List<Task> sapuBersihTasks(List<Task> tasks, List<TaskArea> areas) {
  final unscheduled = {
    for (final a in areas)
      if (!a.archived && a.schedule == null) a.id,
  };
  return tasks
      .where(
        (t) =>
            !t.done &&
            t.bucket == TaskBucket.should &&
            unscheduled.contains(t.areaId),
      )
      .toList()
    ..sort(compareTasks);
}

// ---------------------------------------------------------------- ordering

/// sortOrder, then name.
int compareAreas(TaskArea a, TaskArea b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.name.compareTo(b.name);
}

/// Bucket order (fire, want, should), then manual sortOrder, then oldest first.
int compareTasks(Task a, Task b) {
  var c = a.bucket.index.compareTo(b.bucket.index);
  if (c != 0) return c;
  c = a.sortOrder.compareTo(b.sortOrder);
  if (c != 0) return c;
  return a.createdAt.compareTo(b.createdAt);
}

/// A sortOrder between two neighbours (either may be missing) — for drag & drop.
double sortOrderBetween(double? before, double? after) {
  if (before == null && after == null) return 0;
  if (before == null) return after! - 1;
  if (after == null) return before + 1;
  return (before + after) / 2;
}

// ---------------------------------------------------------------- notifications

/// `[KERJA-FIRE] Kirim revisi client A`
String taskNotificationTitle(
  String areaCode,
  TaskBucket bucket,
  String title,
) => '[$areaCode-${bucket.label}] $title';

/// Local notifications for [tasks] at [now] (spec "Notifications"): each undone
/// task with `dueDate + dueTime` and `remindBefore != null` fires at
/// `due − remindBefore`; past ones are skipped. Soonest first, capped at [max].
/// Body: `Hari ini 14.00 · Kerjaan · Rp 50.000` (day relative to the fire time).
List<Reminder> computeReminders(
  List<Task> tasks,
  List<TaskArea> areas,
  DateTime now, {
  String currency = 'IDR',
  int max = maxTaskNotifications,
}) {
  final byId = {for (final a in areas) a.id: a};
  final out = <Reminder>[];
  for (final t in tasks) {
    if (t.done || t.remindBefore == null) continue;
    final due = t.dueAt;
    final fireAt = t.remindAt;
    if (due == null || fireAt == null || fireAt.isBefore(now)) continue;
    final area = byId[t.areaId];
    final body = [
      '${Fmt.relativeDay(due, now: fireAt)} ${Fmt.time(due)}',
      ?area?.name,
      if (t.hasMoneyLink) Fmt.money(t.amount!, currency: currency),
    ].join(' · ');
    out.add(
      Reminder(
        key: t.id,
        title: taskNotificationTitle(area?.code ?? 'TUGAS', t.bucket, t.title),
        body: body,
        fireAt: fireAt,
        route: taskRoute(t.id),
      ),
    );
  }
  out.sort((a, b) {
    final c = a.fireAt.compareTo(b.fireAt);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return out.length > max ? out.sublist(0, max) : out;
}

/// App route of a task (notification tap target).
String taskRoute(String taskId) => '/tasks/$taskId';

// ---------------------------------------------------------------- default areas

/// Deterministic ids so seeding on the server and on two devices never duplicates.
({String kerjaan, String life}) defaultAreaIds(String userId) =>
    (kerjaan: 'area-kerjaan-$userId', life: 'area-life-$userId');

/// Kerjaan (KERJA, Mon–Fri 09:00–17:00) and Keseharian (LIFE, anytime).
List<TaskArea> defaultTaskAreas(String userId, DateTime now) {
  final ids = defaultAreaIds(userId);
  return [
    TaskArea(
      id: ids.kerjaan,
      name: 'Kerjaan',
      code: 'KERJA',
      color: '#1CB0F6',
      icon: 'briefcase',
      schedule: AreaSchedule.workHours,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
    TaskArea(
      id: ids.life,
      name: 'Keseharian',
      code: 'LIFE',
      color: '#58CC02',
      icon: 'home',
      sortOrder: 1,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

// ---------------------------------------------------------------- money link

/// Prefill of "Catat pengeluaran Rp X?" when completing [t] (null without a money
/// link): amount, wallet, category, note = task title (date = today).
TaskExpense? expenseDraftFor(Task t) => t.hasMoneyLink
    ? TaskExpense(
        amount: t.amount!,
        walletId: t.walletId,
        categoryId: t.categoryId,
        note: t.title,
      )
    : null;
