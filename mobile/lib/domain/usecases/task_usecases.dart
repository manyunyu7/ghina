/// Tasks (to-do) use cases — `docs/tasks.md`. Rules: `task_rules.dart`.
library;

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'category_usecases.dart' show categoryIcons;
import 'task_rules.dart';
import 'transaction_usecases.dart';
import 'validation.dart';

/// A source of "now" that emits right away and then every minute (see
/// `minuteTicks` in `core/clock.dart`). Tests pass a controllable stream.
typedef TickSource = Stream<DateTime> Function();

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ================================================================ areas

/// Form data of an area.
final class TaskAreaInput {
  const TaskAreaInput({
    required this.name,
    required this.code,
    this.color = defaultAreaColor,
    this.icon = defaultAreaIcon,
    this.schedule,
  });

  final String name;

  /// Uppercased before validation (`kerja` → `KERJA`).
  final String code;
  final String color;

  /// One of `categoryIcons`.
  final String icon;

  /// Null = no schedule ("anytime").
  final AreaSchedule? schedule;
}

AreaSchedule? _validSchedule(AreaSchedule? s) {
  if (s == null) return null;
  final days = s.days.toSet().toList()..sort();
  if (days.isEmpty || days.any((d) => d < 1 || d > 7)) {
    throw const ValidationFailure('Pilih minimal satu hari', field: 'schedule');
  }
  if (!isHm(s.start) || !isHm(s.end)) {
    throw const ValidationFailure('Jam tidak valid', field: 'schedule');
  }
  if (s.start.compareTo(s.end) >= 0) {
    throw const ValidationFailure(
      'Jam mulai harus sebelum jam selesai',
      field: 'schedule',
    );
  }
  return AreaSchedule(days: days, start: s.start, end: s.end);
}

Future<TaskArea> _buildArea(
  TaskAreaRepository repo,
  String id,
  TaskAreaInput i, {
  required int sortOrder,
  required bool archived,
  required DateTime createdAt,
  required DateTime now,
}) async {
  final name = requireName(i.name, max: areaNameMax);
  final code = i.code.trim().toUpperCase();
  if (!areaCodeRe.hasMatch(code)) {
    throw const ValidationFailure(
      'Kode 1–8 huruf/angka (A–Z, 0–9)',
      field: 'code',
    );
  }
  final all = await repo.getAll();
  if (all.any((a) => a.id != id && a.code == code)) {
    throw const ValidationFailure(
      'Kode sudah dipakai area lain',
      field: 'code',
    );
  }
  if (!categoryIcons.contains(i.icon)) {
    throw const ValidationFailure('Ikon tidak valid', field: 'icon');
  }
  return TaskArea(
    id: id,
    name: name,
    code: code,
    color: requireColor(i.color),
    icon: i.icon,
    schedule: _validSchedule(i.schedule),
    sortOrder: sortOrder,
    archived: archived,
    createdAt: createdAt,
    updatedAt: now,
  );
}

/// Creates an area at the end of the area order.
final class CreateTaskArea {
  const CreateTaskArea(this._repo, this._clock);
  final TaskAreaRepository _repo;
  final Clock _clock;

  Future<Result<TaskArea>> call(TaskAreaInput input) => guard(() async {
    final now = _clock.now();
    final all = await _repo.getAll();
    final order = all.isEmpty
        ? 0
        : all.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final a = await _buildArea(
      _repo,
      newId(),
      input,
      sortOrder: order,
      archived: false,
      createdAt: now,
      now: now,
    );
    await _repo.save(a);
    return a;
  });
}

final class UpdateTaskArea {
  const UpdateTaskArea(this._repo, this._clock);
  final TaskAreaRepository _repo;
  final Clock _clock;

  Future<Result<TaskArea>> call(String id, TaskAreaInput input) =>
      guard(() async {
        final old = await _repo.getById(id);
        if (old == null) throw const NotFoundFailure('Area tidak ditemukan');
        final a = await _buildArea(
          _repo,
          id,
          input,
          sortOrder: old.sortOrder,
          archived: old.archived,
          createdAt: old.createdAt,
          now: _clock.now(),
        );
        await _repo.save(a);
        return a;
      });
}

/// Sets `sortOrder` = position in [orderedIds] (only rows that change are saved).
final class ReorderTaskAreas {
  const ReorderTaskAreas(this._repo, this._uow, this._clock);
  final TaskAreaRepository _repo;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> orderedIds) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in orderedIds.indexed) {
        final a = await _repo.getById(id);
        if (a == null || a.sortOrder == i) continue;
        await _repo.save(a.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

final class SetTaskAreaArchived {
  const SetTaskAreaArchived(this._repo, this._clock);
  final TaskAreaRepository _repo;
  final Clock _clock;

  Future<Result<TaskArea>> call(String id, bool archived) => guard(() async {
    final a = await _repo.getById(id);
    if (a == null) throw const NotFoundFailure('Area tidak ditemukan');
    final u = a.copyWith(archived: archived, updatedAt: _clock.now());
    await _repo.save(u);
    return u;
  });
}

/// Deletes an area and all its tasks (cascade, mirrored by the server).
final class DeleteTaskArea {
  const DeleteTaskArea(this._repo);
  final TaskAreaRepository _repo;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _repo.getById(id) == null) {
      throw const NotFoundFailure('Area tidak ditemukan');
    }
    await _repo.delete(id);
  });
}

/// Creates the default areas (Kerjaan, Keseharian) with deterministic ids when the
/// user has no area at all. Returns how many were created (0 or 2). The sync
/// engine does this on its own after the first pull; screens may call it for an
/// empty state ("Buat area default").
final class SeedDefaultTaskAreas {
  const SeedDefaultTaskAreas(this._repo, this._uow, this._clock);
  final TaskAreaRepository _repo;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<int>> call(String userId) => guard(
    () => _uow.run(() async {
      if ((await _repo.getAll()).isNotEmpty) return 0;
      final areas = defaultTaskAreas(userId, _clock.now());
      for (final a in areas) {
        await _repo.save(a);
      }
      return areas.length;
    }),
  );
}

final class WatchTaskAreas {
  const WatchTaskAreas(this._repo);
  final TaskAreaRepository _repo;

  /// Sorted by `sortOrder`, then name.
  Stream<List<TaskArea>> call({bool includeArchived = false}) =>
      _repo.watchAll().map(
        (all) => [
          for (final a in all)
            if (includeArchived || !a.archived) a,
        ]..sort(compareAreas),
      );
}

final class WatchTaskArea {
  const WatchTaskArea(this._repo);
  final TaskAreaRepository _repo;

  Stream<TaskArea?> call(String id) => _repo.watchById(id);
}

// ================================================================ tasks

/// Form data of a task.
final class TaskInput {
  const TaskInput({
    required this.areaId,
    required this.title,
    this.note,
    this.bucket = TaskBucket.want,
    this.dueDate,
    this.dueTime,
    this.remindBefore,
    this.recurrence,
    this.amount,
    this.walletId,
    this.categoryId,
  });

  final String areaId;
  final String title;
  final String? note;
  final TaskBucket bucket;

  /// Local day (time part ignored).
  final DateTime? dueDate;

  /// `HH:mm` (use `formatHm(t.hour, t.minute)`); needs [dueDate].
  final String? dueTime;

  /// Minutes before due (0 = at due time, max 7 days); null = no reminder. Only
  /// fires with [dueDate] + [dueTime]. Suggested presets: `remindBeforeOptions`.
  final int? remindBefore;

  /// Needs [dueDate]. Defaults (weekday / day of month) are filled from it.
  final Recurrence? recurrence;

  /// Money link (> 0) with optional wallet and expense category.
  final double? amount;
  final String? walletId;
  final String? categoryId;
}

/// Validated fields of a task (everything the input controls).
typedef _TaskFields = ({
  String areaId,
  String title,
  String? note,
  TaskBucket bucket,
  String? dueDate,
  String? dueTime,
  int? remindBefore,
  Recurrence? recurrence,
  double? amount,
  String? walletId,
  String? categoryId,
});

Future<_TaskFields> _validateTask(
  TaskInput i,
  TaskAreaRepository areas,
  WalletRepository wallets,
  CategoryRepository categories,
) async {
  final title = i.title.trim();
  if (title.isEmpty) {
    throw const ValidationFailure('Judul wajib diisi', field: 'title');
  }
  if (title.length > taskTitleMax) {
    throw const ValidationFailure(
      'Judul terlalu panjang (maks $taskTitleMax karakter)',
      field: 'title',
    );
  }
  final note = optionalText(i.note, max: taskNoteMax);
  if (i.areaId.isEmpty || await areas.getById(i.areaId) == null) {
    throw const ValidationFailure('Pilih area dulu', field: 'areaId');
  }
  final due = i.dueDate == null ? null : dateKey(i.dueDate!);
  final time = i.dueTime == null || i.dueTime!.isEmpty ? null : i.dueTime;
  if (time != null && !isHm(time)) {
    throw const ValidationFailure('Jam tidak valid', field: 'dueTime');
  }
  if (time != null && due == null) {
    throw const ValidationFailure(
      'Isi tanggal dulu sebelum jam',
      field: 'dueTime',
    );
  }
  final rb = i.remindBefore;
  if (rb != null && (rb < 0 || rb > remindBeforeMax)) {
    throw const ValidationFailure(
      'Pengingat maksimal 7 hari sebelumnya',
      field: 'remindBefore',
    );
  }
  Recurrence? rec;
  if (i.recurrence != null) {
    if (due == null) {
      throw const ValidationFailure(
        'Tugas berulang butuh tanggal',
        field: 'recurrence',
      );
    }
    final r = i.recurrence!;
    if (r.interval < 1 || r.interval > 365) {
      throw const ValidationFailure('Interval 1–365', field: 'recurrence');
    }
    if (r.weekdays != null && r.weekdays!.any((d) => d < 1 || d > 7)) {
      throw const ValidationFailure('Hari tidak valid', field: 'recurrence');
    }
    if (r.monthDay != null && (r.monthDay! < 1 || r.monthDay! > 31)) {
      throw const ValidationFailure('Tanggal 1–31', field: 'recurrence');
    }
    rec = normalizeRecurrence(r, due);
  }
  double? amount;
  String? walletId, categoryId;
  if (i.amount != null) {
    amount = requirePositiveAmount(i.amount);
    walletId = optionalId(i.walletId);
    categoryId = optionalId(i.categoryId);
    if (walletId != null && await wallets.getById(walletId) == null) {
      throw const NotFoundFailure('Dompet tidak ditemukan');
    }
    if (categoryId != null) {
      final c = await categories.getById(categoryId);
      if (c == null) throw const NotFoundFailure('Kategori tidak ditemukan');
      if (c.type != CategoryType.expense) {
        throw const ValidationFailure(
          'Pilih kategori pengeluaran',
          field: 'categoryId',
        );
      }
    }
  }
  return (
    areaId: i.areaId,
    title: title,
    note: note,
    bucket: i.bucket,
    dueDate: due,
    dueTime: time,
    remindBefore: rb,
    recurrence: rec,
    amount: amount,
    walletId: walletId,
    categoryId: categoryId,
  );
}

/// Sort order that puts a task at the end of its (area, bucket) cell.
Future<double> _endOfCell(
  TaskRepository tasks,
  String areaId,
  TaskBucket bucket, {
  String? exceptId,
}) async {
  double? max;
  for (final t in await tasks.getAll(areaId: areaId)) {
    if (t.bucket != bucket || t.done || t.id == exceptId) continue;
    if (max == null || t.sortOrder > max) max = t.sortOrder;
  }
  return sortOrderBetween(max, null);
}

/// Creates a task at the end of its (area, bucket) cell. Quick add = just
/// `TaskInput(areaId:, title:, bucket:, dueDate:)`.
final class CreateTask {
  const CreateTask(
    this._tasks,
    this._areas,
    this._wallets,
    this._categories,
    this._clock,
  );
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<Task>> call(TaskInput input) => guard(() async {
    final f = await _validateTask(input, _areas, _wallets, _categories);
    final now = _clock.now();
    final id = newId();
    final t = Task(
      id: id,
      areaId: f.areaId,
      title: f.title,
      note: f.note,
      bucket: f.bucket,
      dueDate: f.dueDate,
      dueTime: f.dueTime,
      remindBefore: f.remindBefore,
      recurrence: f.recurrence,
      seriesId: f.recurrence == null ? null : id,
      sortOrder: await _endOfCell(_tasks, f.areaId, f.bucket),
      amount: f.amount,
      walletId: f.walletId,
      categoryId: f.categoryId,
      createdAt: now,
      updatedAt: now,
    );
    await _tasks.save(t);
    return t;
  });
}

/// Edits every input field. Keeps done/doneAt/transactionId; a new area or bucket
/// moves the task to the end of the new cell.
final class UpdateTask {
  const UpdateTask(
    this._tasks,
    this._areas,
    this._wallets,
    this._categories,
    this._clock,
  );
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<Task>> call(String id, TaskInput input) => guard(() async {
    final old = await _tasks.getById(id);
    if (old == null) throw const NotFoundFailure('Tugas tidak ditemukan');
    final f = await _validateTask(input, _areas, _wallets, _categories);
    final moved = f.areaId != old.areaId || f.bucket != old.bucket;
    final t = old.copyWith(
      areaId: f.areaId,
      title: f.title,
      note: f.note,
      bucket: f.bucket,
      dueDate: f.dueDate,
      dueTime: f.dueTime,
      remindBefore: f.remindBefore,
      recurrence: f.recurrence,
      seriesId: f.recurrence != null ? (old.seriesId ?? old.id) : old.seriesId,
      sortOrder: moved
          ? await _endOfCell(_tasks, f.areaId, f.bucket, exceptId: id)
          : old.sortOrder,
      amount: f.amount,
      walletId: f.walletId,
      categoryId: f.categoryId,
      updatedAt: _clock.now(),
    );
    await _tasks.save(t);
    return t;
  });
}

final class DeleteTask {
  const DeleteTask(this._tasks);
  final TaskRepository _tasks;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _tasks.getById(id) == null) {
      throw const NotFoundFailure('Tugas tidak ditemukan');
    }
    await _tasks.delete(id);
  });
}

/// Marks a task done (`doneAt` = now). A recurring task also gets its next
/// occurrence (deterministic id `<seriesId>_<YYYYMMDD>`; an existing row with that
/// id is kept as is, so completing twice — or on two devices — never duplicates).
///
/// Money link: pass [expense] when the user accepted "Catat pengeluaran Rp X?"
/// (prefill with `expenseDraftFor(task)`); it records an expense through
/// [CreateTransaction] (note defaults to the title, date to now) and stores its id
/// in `transactionId`. Omit it to just complete. Everything is one local
/// transaction: if the expense is invalid nothing changes.
///
/// Completing an already-done task changes nothing (returns it with its next
/// occurrence, if present).
final class CompleteTask {
  const CompleteTask(this._tasks, this._createTx, this._uow, this._clock);
  final TaskRepository _tasks;
  final CreateTransaction _createTx;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<TaskCompletion>> call(String id, {TaskExpense? expense}) =>
      guard(
        () => _uow.run(() async {
          final t = await _tasks.getById(id);
          if (t == null) throw const NotFoundFailure('Tugas tidak ditemukan');
          final now = _clock.now();
          final draft = nextOccurrence(t, now);
          if (t.done) {
            return TaskCompletion(
              task: t,
              next: draft == null ? null : await _tasks.getById(draft.id),
            );
          }
          Transaction? tx;
          if (expense != null) {
            final walletId = optionalId(expense.walletId);
            if (walletId == null) {
              throw const ValidationFailure(
                'Pilih dompet dulu',
                field: 'walletId',
              );
            }
            tx = (await _createTx(
              TransactionInput(
                type: TxType.expense,
                amount: expense.amount,
                walletId: walletId,
                categoryId: expense.categoryId,
                note: expense.note ?? t.title,
                date: expense.date ?? now,
              ),
            )).valueOrThrow;
          }
          final done = t.copyWith(
            done: true,
            doneAt: now,
            transactionId: tx?.id ?? t.transactionId,
            updatedAt: now,
          );
          await _tasks.save(done);
          Task? next;
          if (draft != null) {
            next = await _tasks.getById(draft.id);
            if (next == null) {
              await _tasks.save(draft);
              next = draft;
            }
          }
          return TaskCompletion(task: done, next: next, transaction: tx);
        }),
      );
}

/// Un-completes a task. The next occurrence of a recurring task stays, and a
/// recorded expense stays too (delete it separately if wanted).
final class UncompleteTask {
  const UncompleteTask(this._tasks, this._clock);
  final TaskRepository _tasks;
  final Clock _clock;

  Future<Result<Task>> call(String id) => guard(() async {
    final t = await _tasks.getById(id);
    if (t == null) throw const NotFoundFailure('Tugas tidak ditemukan');
    if (!t.done) return t;
    final u = t.copyWith(done: false, doneAt: null, updatedAt: _clock.now());
    await _tasks.save(u);
    return u;
  });
}

/// Moves a task to another bucket and/or area (long-press "pindah", drag & drop).
/// [sortOrder] positions it (use `sortOrderBetween(prev, next)`); null = end of the
/// target cell.
final class MoveTask {
  const MoveTask(this._tasks, this._areas, this._clock);
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final Clock _clock;

  Future<Result<Task>> call(
    String id, {
    TaskBucket? bucket,
    String? areaId,
    double? sortOrder,
  }) => guard(() async {
    final t = await _tasks.getById(id);
    if (t == null) throw const NotFoundFailure('Tugas tidak ditemukan');
    final area = areaId ?? t.areaId;
    if (area != t.areaId && await _areas.getById(area) == null) {
      throw const NotFoundFailure('Area tidak ditemukan');
    }
    final b = bucket ?? t.bucket;
    final order =
        sortOrder ??
        (area == t.areaId && b == t.bucket
            ? t.sortOrder
            : await _endOfCell(_tasks, area, b, exceptId: id));
    if (area == t.areaId && b == t.bucket && order == t.sortOrder) return t;
    final u = t.copyWith(
      areaId: area,
      bucket: b,
      sortOrder: order,
      updatedAt: _clock.now(),
    );
    await _tasks.save(u);
    return u;
  });
}

/// Sets `sortOrder` = position in [orderedIds] (one cell's new order after a
/// drag). Only rows that change are saved.
final class ReorderTasks {
  const ReorderTasks(this._tasks, this._uow, this._clock);
  final TaskRepository _tasks;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> orderedIds) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in orderedIds.indexed) {
        final t = await _tasks.getById(id);
        if (t == null || t.sortOrder == i.toDouble()) continue;
        await _tasks.save(t.copyWith(sortOrder: i.toDouble(), updatedAt: now));
      }
    }),
  );
}

// ================================================================ watching

TaskView _view(Task t, Map<String, TaskArea> areas, DateTime now) => TaskView(
  task: t,
  area: areas[t.areaId],
  isOverdue: isOverdue(t, now),
  isMepet: isMepet(t, now),
  isDueToday: isDueToday(t, now),
);

/// Applies [filter] at [now]. Returns the views in board order (done: most
/// recently completed first) plus the areas in scope.
({List<TaskView> views, List<TaskArea> areas}) applyTaskFilter(
  List<Task> tasks,
  List<TaskArea> allAreas,
  TaskFilter filter,
  DateTime now,
) {
  final sortedAreas = [...allAreas]..sort(compareAreas);
  final List<TaskArea> scope;
  if (filter.focusAreasOnly) {
    scope = focusAreas(sortedAreas, now);
  } else if (filter.areaIds != null) {
    final ids = filter.areaIds!.toSet();
    scope = [
      for (final a in sortedAreas)
        if (ids.contains(a.id)) a,
    ];
  } else {
    scope = [
      for (final a in sortedAreas)
        if (!a.archived) a,
    ];
  }
  final scopeIds = {for (final a in scope) a.id};
  final byId = {for (final a in allAreas) a.id: a};
  final q = filter.search?.trim().toLowerCase();
  bool matches(Task t) {
    if (!scopeIds.contains(t.areaId)) return false;
    if (filter.bucket != null && t.bucket != filter.bucket) return false;
    if (q != null && q.isNotEmpty) {
      final hay = '${t.title} ${t.note ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return switch (filter.status) {
      TaskStatusFilter.open => !t.done,
      TaskStatusFilter.today => !t.done && isDueToday(t, now),
      TaskStatusFilter.mepet => isMepet(t, now),
      TaskStatusFilter.overdue => isOverdue(t, now),
      TaskStatusFilter.done => t.done,
      TaskStatusFilter.all => true,
    };
  }

  final list = tasks.where(matches).toList();
  if (filter.status == TaskStatusFilter.done) {
    list.sort((a, b) {
      final x = b.doneAt ?? b.updatedAt, y = a.doneAt ?? a.updatedAt;
      return x.compareTo(y);
    });
  } else {
    list.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      return compareTasks(a, b);
    });
  }
  return (views: [for (final t in list) _view(t, byId, now)], areas: scope);
}

/// Filtered tasks (see [TaskFilter]); re-evaluated on every change and every
/// minute, emitting only when the result changes.
final class WatchTasks {
  const WatchTasks(this._tasks, this._areas, this._ticks);
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final TickSource _ticks;

  Stream<List<TaskView>> call([TaskFilter filter = const TaskFilter()]) =>
      combineLatest3(
        _tasks.watchAll(),
        _areas.watchAll(),
        _ticks(),
        (List<Task> t, List<TaskArea> a, DateTime now) =>
            applyTaskFilter(t, a, filter, now).views,
      ).distinct(_listEq);
}

/// The board: [WatchTasks] split into the three bucket sections.
final class WatchTaskBoard {
  const WatchTaskBoard(this._tasks, this._areas, this._ticks);
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final TickSource _ticks;

  Stream<TaskBoard> call([TaskFilter filter = TaskFilter.focus]) =>
      combineLatest3(_tasks.watchAll(), _areas.watchAll(), _ticks(), (
        List<Task> t,
        List<TaskArea> a,
        DateTime now,
      ) {
        final r = applyTaskFilter(t, a, filter, now);
        return TaskBoard(
          sections: [
            for (final b in TaskBucket.values)
              TaskSection(b, [
                for (final v in r.views)
                  if (v.bucket == b) v,
              ]),
          ],
          areas: r.areas,
        );
      }).distinct();
}

/// One task with its area and flags; null when deleted.
final class WatchTask {
  const WatchTask(this._tasks, this._areas, this._ticks);
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final TickSource _ticks;

  Stream<TaskView?> call(String id) => combineLatest3(
    _tasks.watchById(id),
    _areas.watchAll(),
    _ticks(),
    (Task? t, List<TaskArea> a, DateTime now) =>
        t == null ? null : _view(t, {for (final x in a) x.id: x}, now),
  ).distinct();
}

/// Focus areas now (changes when a schedule starts/ends — ticks every minute).
final class WatchFocusAreas {
  const WatchFocusAreas(this._areas, this._ticks);
  final TaskAreaRepository _areas;
  final TickSource _ticks;

  Stream<FocusAreas> call() => combineLatest2(_areas.watchAll(), _ticks(), (
    List<TaskArea> a,
    DateTime now,
  ) {
    final sorted = [...a]..sort(compareAreas);
    final f = focusAreas(sorted, now);
    return FocusAreas(
      areas: f,
      bySchedule: f.isNotEmpty && f.first.schedule != null,
    );
  }).distinct();
}

/// Home screen data: focus-area FIRE tasks and the Sunday "Sapu bersih" card.
final class WatchTaskHome {
  const WatchTaskHome(this._tasks, this._areas, this._ticks);
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final TickSource _ticks;

  Stream<TaskHome> call() => combineLatest3(
    _tasks.watchAll(),
    _areas.watchAll(),
    _ticks(),
    (List<Task> t, List<TaskArea> a, DateTime now) {
      final byId = {for (final x in a) x.id: x};
      final sorted = [...a]..sort(compareAreas);
      final focus = focusAreas(sorted, now);
      final fire = applyTaskFilter(
        t,
        a,
        const TaskFilter(focusAreasOnly: true, bucket: TaskBucket.fire),
        now,
      ).views;
      final live = {
        for (final x in a)
          if (!x.archived) x.id,
      };
      final open = t.where((x) => !x.done && live.contains(x.areaId));
      return TaskHome(
        focus: FocusAreas(
          areas: focus,
          bySchedule: focus.isNotEmpty && focus.first.schedule != null,
        ),
        fireTasks: fire,
        showSapuBersih: isSapuBersihTime(now),
        sapuBersih: [
          for (final x in sapuBersihTasks(t, a)) _view(x, byId, now),
        ],
        overdueCount: open.where((x) => isOverdue(x, now)).length,
        openCount: open.length,
      );
    },
  ).distinct();
}

/// The reminders to schedule (≤ 60, soonest first), recomputed on every task or
/// area change and every minute; emits only when the list changes. Feed it to
/// `ReminderScheduler.replaceAll`.
final class WatchReminders {
  const WatchReminders(this._tasks, this._areas, this._ticks);
  final TaskRepository _tasks;
  final TaskAreaRepository _areas;
  final TickSource _ticks;

  Stream<List<Reminder>> call({String currency = 'IDR'}) => combineLatest3(
    _tasks.watchAll(),
    _areas.watchAll(),
    _ticks(),
    (List<Task> t, List<TaskArea> a, DateTime now) =>
        computeReminders(t, a, now, currency: currency),
  ).distinct(_listEq);
}
