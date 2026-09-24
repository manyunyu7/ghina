// Mirrors ../scripts/test-tasks.mjs (server `src/lib/tasks.ts`, `src/lib/photos.ts`)
// case by case where the rule exists on mobile, plus reminders/sapu bersih.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/data/models/mappers.dart';
import 'package:ghina/data/models/wire.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';

final t0 = DateTime(2026, 9, 1);

Task tk({
  String id = 'x',
  TaskBucket bucket = TaskBucket.want,
  bool done = false,
  String? dueDate,
  String? dueTime,
  String areaId = 'a1',
  int? remindBefore,
  double? amount,
  double sortOrder = 0,
  DateTime? createdAt,
  String title = 'Do it',
}) => Task(
  id: id,
  areaId: areaId,
  title: title,
  bucket: bucket,
  done: done,
  dueDate: dueDate,
  dueTime: dueTime,
  remindBefore: remindBefore,
  amount: amount,
  sortOrder: sortOrder,
  createdAt: createdAt ?? t0,
  updatedAt: createdAt ?? t0,
);

TaskArea area(
  String id, {
  AreaSchedule? schedule,
  bool archived = false,
  int sortOrder = 0,
  String code = 'X',
  String name = 'X',
}) => TaskArea(
  id: id,
  name: name,
  code: code,
  schedule: schedule,
  archived: archived,
  sortOrder: sortOrder,
  createdAt: t0,
  updatedAt: t0,
);

void main() {
  group('constants', () {
    test('bucket order fire, want, should', () {
      expect(TaskBucket.values.map((b) => b.wire), ['fire', 'want', 'should']);
    });
    test('bucket colors', () {
      expect(TaskBucket.values.map((b) => b.color), [
        0xFFFF4B4B,
        0xFFCE82FF,
        0xFF1CB0F6,
      ]);
    });
    test('bucket XP 10/8/5', () {
      expect(TaskBucket.values.map((b) => b.xp), [10, 8, 5]);
      expect(TaskBucket.fromWire('should').xp, 5);
    });
    test('daily XP cap 20, 60 notifications', () {
      expect(taskXpDailyCap, 20);
      expect(maxTaskNotifications, 60);
      expect(remindBeforeMax, 10080);
      expect(remindBeforeOptions, [0, 10, 30, 60]);
    });
    test('notification title', () {
      expect(
        taskNotificationTitle(
          'KERJA',
          TaskBucket.fire,
          'Kirim revisi client A',
        ),
        '[KERJA-FIRE] Kirim revisi client A',
      );
    });
    test('unknown bucket → want (server default)', () {
      expect(TaskBucket.fromWire('later'), TaskBucket.want);
    });
  });

  group('date helpers', () {
    test('isoWeekday Mon=1', () {
      expect(isoWeekdayOfKey('2026-09-21'), 1);
      expect(isoWeekdayOfKey('2026-09-27'), 7);
    });
    test('addDaysKey across month/year', () {
      expect(addDaysKey('2026-12-31', 1), '2027-01-01');
      expect(addDaysKey('2026-03-01', -1), '2026-02-28');
    });
  });

  group('recurrence: nextDueDate', () {
    String nd(Recurrence r, String due) => nextDueDate(r, due);
    const daily = Recurrence.daily();
    test('daily +1', () => expect(nd(daily, '2026-09-24'), '2026-09-25'));
    test(
      'daily every 3 days across month',
      () => expect(nd(const Recurrence.daily(3), '2026-09-29'), '2026-10-02'),
    );
    test(
      'weekly default weekday = same weekday next week',
      () => expect(nd(const Recurrence.weekly(), '2026-09-24'), '2026-10-01'),
    );
    test(
      'weekly Mon/Wed/Fri from Mon → Wed',
      () => expect(
        nd(const Recurrence.weekly(weekdays: [1, 3, 5]), '2026-09-21'),
        '2026-09-23',
      ),
    );
    test(
      'weekly Mon/Wed/Fri from Fri → next Mon',
      () => expect(
        nd(const Recurrence.weekly(weekdays: [5, 1, 3]), '2026-09-25'),
        '2026-09-28',
      ),
    );
    test(
      'weekly every 2 weeks Tue/Thu from Thu → Tue in 2 weeks',
      () => expect(
        nd(
          const Recurrence.weekly(interval: 2, weekdays: [2, 4]),
          '2026-09-24',
        ),
        '2026-10-06',
      ),
    );
    test(
      'weekly every 2 weeks Tue/Thu from Tue → Thu same week',
      () => expect(
        nd(
          const Recurrence.weekly(interval: 2, weekdays: [2, 4]),
          '2026-09-22',
        ),
        '2026-09-24',
      ),
    );
    test(
      'weekly Sunday → next Sunday',
      () => expect(
        nd(const Recurrence.weekly(weekdays: [7]), '2026-09-27'),
        '2026-10-04',
      ),
    );
    test(
      'monthly default day',
      () => expect(nd(const Recurrence.monthly(), '2026-09-15'), '2026-10-15'),
    );
    test(
      'monthly 31 clamps to 30',
      () => expect(
        nd(const Recurrence.monthly(monthDay: 31), '2026-08-31'),
        '2026-09-30',
      ),
    );
    test(
      'monthly 31 from Jan 31 → Feb 28',
      () => expect(
        nd(const Recurrence.monthly(monthDay: 31), '2026-01-31'),
        '2026-02-28',
      ),
    );
    test(
      'monthly 31 from Feb 28 (clamped) → Mar 31, no drift',
      () => expect(
        nd(const Recurrence.monthly(monthDay: 31), '2026-02-28'),
        '2026-03-31',
      ),
    );
    test(
      'monthly 29 leap year Feb',
      () => expect(
        nd(const Recurrence.monthly(monthDay: 29), '2028-01-29'),
        '2028-02-29',
      ),
    );
    test(
      'monthly monthDay later in same month',
      () => expect(
        nd(const Recurrence.monthly(monthDay: 20), '2026-09-05'),
        '2026-09-20',
      ),
    );
    test(
      'monthly every 3 months across year',
      () => expect(
        nd(const Recurrence.monthly(interval: 3, monthDay: 10), '2026-11-10'),
        '2027-02-10',
      ),
    );
    test(
      'monthly every 12 months',
      () => expect(
        nd(const Recurrence.monthly(interval: 12), '2026-02-28'),
        '2027-02-28',
      ),
    );
  });

  group('recurrence: nextOccurrence', () {
    final now = DateTime(2026, 1, 31, 10);
    final base = Task(
      id: 'task1',
      areaId: 'a1',
      title: 'Bayar listrik',
      note: 'PLN',
      bucket: TaskBucket.fire,
      dueDate: '2026-01-31',
      dueTime: '09:00',
      remindBefore: 30,
      recurrence: const Recurrence.monthly(),
      sortOrder: 3,
      amount: 250000,
      walletId: 'w1',
      categoryId: 'c1',
      transactionId: 'tx1',
      done: true,
      doneAt: now,
      createdAt: t0,
      updatedAt: t0,
    );
    final n1 = nextOccurrence(base, now)!;

    test('next id = <seriesId>_<YYYYMMDD> (series = first id)', () {
      expect(n1.id, 'task1_20260228');
    });
    test('next copies fields, undone, no transaction', () {
      expect(n1.title, 'Bayar listrik');
      expect(n1.note, 'PLN');
      expect(n1.dueTime, '09:00');
      expect(n1.remindBefore, 30);
      expect(n1.bucket, TaskBucket.fire);
      expect(n1.amount, 250000);
      expect(n1.walletId, 'w1');
      expect(n1.categoryId, 'c1');
      expect(n1.transactionId, isNull);
      expect(n1.done, isFalse);
      expect(n1.doneAt, isNull);
      expect(n1.seriesId, 'task1');
      expect(n1.sortOrder, 3);
      expect(n1.areaId, 'a1');
      expect(n1.createdAt, now);
    });
    test('next materializes monthDay (31) → no drift', () {
      expect(n1.recurrence, const Recurrence.monthly(monthDay: 31));
    });
    test('second next keeps seriesId and returns to 31', () {
      final n2 = nextOccurrence(n1, now)!;
      expect(n2.id, 'task1_20260331');
      expect(n2.seriesId, 'task1');
    });
    test('deterministic: same input → same id', () {
      expect(nextOccurrence(base, DateTime(2027))!.id, n1.id);
    });
    test('recurrence from stored JSON string works', () {
      final r = Recurrence.tryParse(const {'freq': 'daily', 'interval': 2});
      expect(
        nextOccurrence(base.copyWith(recurrence: r), now)!.id,
        'task1_20260202',
      );
    });
    test('one-off → null', () {
      expect(nextOccurrence(base.copyWith(recurrence: null), now), isNull);
    });
    test('no due date → null', () {
      expect(nextOccurrence(base.copyWith(dueDate: null), now), isNull);
    });
    test('occurrenceId', () {
      expect(occurrenceId('abc', '2026-09-01'), 'abc_20260901');
    });
  });

  group('status helpers', () {
    final today = DateTime(2026, 9, 24, 10);
    test(
      'mepet: WANT due today',
      () => expect(isMepet(tk(dueDate: '2026-09-24'), today), isTrue),
    );
    test(
      'mepet: WANT due tomorrow',
      () => expect(isMepet(tk(dueDate: '2026-09-25'), today), isTrue),
    );
    test(
      'not mepet: in 2 days',
      () => expect(isMepet(tk(dueDate: '2026-09-26'), today), isFalse),
    );
    test('not mepet: FIRE / done / overdue / no date', () {
      expect(
        isMepet(tk(bucket: TaskBucket.fire, dueDate: '2026-09-24'), today),
        isFalse,
      );
      expect(isMepet(tk(done: true, dueDate: '2026-09-24'), today), isFalse);
      expect(isMepet(tk(dueDate: '2026-09-23'), today), isFalse);
      expect(isMepet(tk(), today), isFalse);
    });
    test(
      'overdue: yesterday',
      () => expect(isOverdue(tk(dueDate: '2026-09-23'), today), isTrue),
    );
    test('overdue: today 09:59', () {
      expect(
        isOverdue(tk(dueDate: '2026-09-24', dueTime: '09:59'), today),
        isTrue,
      );
    });
    test('not overdue: today 10:00 / today no time / done / none', () {
      expect(
        isOverdue(tk(dueDate: '2026-09-24', dueTime: '10:00'), today),
        isFalse,
      );
      expect(isOverdue(tk(dueDate: '2026-09-24'), today), isFalse);
      expect(isOverdue(tk(dueDate: '2026-09-01', done: true), today), isFalse);
      expect(isOverdue(tk(), today), isFalse);
    });
    test('date-only task becomes overdue once its day ends', () {
      expect(
        isOverdue(tk(dueDate: '2026-09-24'), DateTime(2026, 9, 24, 23, 59)),
        isFalse,
      );
      expect(
        isOverdue(tk(dueDate: '2026-09-24'), DateTime(2026, 9, 25)),
        isTrue,
      );
    });
  });

  group('focus mode', () {
    final work = area('w', schedule: AreaSchedule.workHours);
    final life = area('l', sortOrder: 1);
    final kuliah = area(
      'k',
      sortOrder: 2,
      schedule: const AreaSchedule(days: [6], start: '08:00', end: '12:00'),
    );
    final old = area('o', archived: true, sortOrder: 3);
    final areas = [work, life, kuliah, old];
    List<String> ids(List<TaskArea> xs) => [for (final a in xs) a.id];

    test('Thu 10:00 → Kerjaan', () {
      expect(ids(focusAreas(areas, DateTime(2026, 9, 24, 10))), ['w']);
    });
    test('Thu 17:00 (end exclusive) → unscheduled', () {
      expect(ids(focusAreas(areas, DateTime(2026, 9, 24, 17))), ['l']);
    });
    test('Sat 09:00 → Kuliah (schedule stored as JSON)', () {
      final stored = TaskArea(
        id: 'k',
        name: 'Kuliah',
        code: 'KUL',
        schedule: AreaSchedule.tryParse(const {
          'days': [6],
          'start': '08:00',
          'end': '12:00',
        }),
        createdAt: t0,
        updatedAt: t0,
      );
      expect(
        ids(focusAreas([work, life, stored, old], DateTime(2026, 9, 26, 9))),
        ['k'],
      );
    });
    test('Sun → unscheduled non-archived', () {
      expect(ids(focusAreas(areas, DateTime(2026, 9, 27, 9))), ['l']);
    });
    test('archived scheduled area never focus', () {
      expect(
        ids(
          focusAreas([
            work.copyWith(archived: true),
            life,
          ], DateTime(2026, 9, 24, 10)),
        ),
        ['l'],
      );
    });
    test('Sunday before 12:00 is sapu bersih time', () {
      expect(isSapuBersihTime(DateTime(2026, 9, 27, 11, 59)), isTrue);
      expect(isSapuBersihTime(DateTime(2026, 9, 27, 12)), isFalse);
      expect(isSapuBersihTime(DateTime(2026, 9, 26, 9)), isFalse);
    });
    test('sapu bersih = undone SHOULD of unscheduled non-archived areas', () {
      final tasks = [
        tk(id: '1', areaId: 'l', bucket: TaskBucket.should, sortOrder: 2),
        tk(id: '2', areaId: 'l', bucket: TaskBucket.should, sortOrder: 1),
        tk(id: '3', areaId: 'l', bucket: TaskBucket.should, done: true),
        tk(id: '4', areaId: 'l', bucket: TaskBucket.want),
        tk(id: '5', areaId: 'w', bucket: TaskBucket.should),
        tk(id: '6', areaId: 'o', bucket: TaskBucket.should),
      ];
      expect(sapuBersihTasks(tasks, areas).map((t) => t.id), ['2', '1']);
    });
  });

  group('schedules / recurrence parsing', () {
    test('schedule ok, days deduped/sorted', () {
      expect(
        AreaSchedule.tryParse(const {
          'days': [5, 1, 1],
          'start': '09:00',
          'end': '17:00',
        })!.days,
        [1, 5],
      );
    });
    test('schedule bad time → null', () {
      expect(
        AreaSchedule.tryParse(const {
          'days': [1],
          'start': '9:00',
          'end': '10:00',
        }),
        isNull,
      );
      expect(
        AreaSchedule.tryParse(const {
          'days': [1],
          'start': '09:00',
          'end': '24:00',
        }),
        isNull,
      );
    });
    test('recurrence parse drops fields of other freqs', () {
      expect(
        Recurrence.tryParse(const {
          'freq': 'daily',
          'interval': 1,
          'weekdays': [1],
        }),
        const Recurrence.daily(),
      );
      expect(Recurrence.tryParse(const {'freq': 'yearly'}), isNull);
    });
    test('recurrence toJson (wire) only carries its own fields', () {
      expect(const Recurrence.weekly(weekdays: [4]).toJson(), {
        'freq': 'weekly',
        'interval': 1,
        'weekdays': [4],
      });
      expect(const Recurrence.daily(2).toJson(), {
        'freq': 'daily',
        'interval': 2,
      });
    });
    test('normalizeRecurrence materializes weekday / monthDay', () {
      expect(
        normalizeRecurrence(const Recurrence.weekly(), '2026-09-24'),
        const Recurrence.weekly(weekdays: [4]),
      );
      expect(
        normalizeRecurrence(const Recurrence.monthly(), '2026-01-31'),
        const Recurrence.monthly(monthDay: 31),
      );
    });
  });

  group('area / task validation (use cases)', () {
    late FakeTaskAreaRepository areas;
    late FakeTaskRepository tasks;
    late FakeWalletRepository wallets;
    late FakeCategoryRepository categories;
    final clock = _clock();
    setUp(() async {
      areas = FakeTaskAreaRepository();
      tasks = FakeTaskRepository();
      wallets = FakeWalletRepository();
      categories = FakeCategoryRepository();
      await areas.save(area('a1', code: 'KERJA'));
      await categories.save(
        TxCategory(
          id: 'inc',
          name: 'Gaji',
          type: CategoryType.income,
          color: '#22c55e',
          icon: 'wallet',
          createdAt: t0,
          updatedAt: t0,
        ),
      );
    });
    Future<Result<TaskArea>> createArea(TaskAreaInput i) =>
        CreateTaskArea(areas, clock)(i);
    Future<Result<Task>> createTask(TaskInput i) =>
        CreateTask(tasks, areas, wallets, categories, clock)(i);

    test('area ok, code uppercased', () async {
      final r = await createArea(
        const TaskAreaInput(
          name: 'Kuliah',
          code: ' kul1 ',
          color: '#123456',
          icon: 'graduation-cap',
        ),
      );
      expect(r.valueOrThrow.code, 'KUL1');
      expect(r.valueOrThrow.sortOrder, 1);
    });
    test('area code >8 / symbols / empty rejected', () async {
      for (final c in ['TOOLONGXX', 'A-B', '']) {
        final r = await createArea(TaskAreaInput(name: 'X', code: c));
        expect(r.failureOrNull, isA<ValidationFailure>(), reason: c);
      }
    });
    test('area code taken rejected (unique per user)', () async {
      final r = await createArea(
        const TaskAreaInput(name: 'Lagi', code: 'kerja'),
      );
      expect((r.failureOrNull as ValidationFailure?)?.field, 'code');
    });
    test('area name >40 rejected', () async {
      final r = await createArea(TaskAreaInput(name: 'x' * 41, code: 'X'));
      expect(r.failureOrNull, isA<ValidationFailure>());
    });
    test('area unknown icon rejected', () async {
      final r = await createArea(
        const TaskAreaInput(name: 'X', code: 'X', icon: 'rocket'),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
    });
    test('area defaults', () async {
      final a = (await createArea(
        const TaskAreaInput(name: 'X', code: 'X'),
      )).valueOrThrow;
      expect(a.color, '#58CC02');
      expect(a.icon, 'briefcase');
      expect(a.schedule, isNull);
      expect(a.archived, isFalse);
    });
    test('schedule start ≥ end / no day rejected', () async {
      for (final s in const [
        AreaSchedule(days: [1], start: '17:00', end: '09:00'),
        AreaSchedule(days: [], start: '09:00', end: '10:00'),
        AreaSchedule(days: [8], start: '09:00', end: '10:00'),
      ]) {
        final r = await createArea(
          TaskAreaInput(name: 'X', code: 'Y', schedule: s),
        );
        expect(r.failureOrNull, isA<ValidationFailure>(), reason: '$s');
      }
    });

    test('task defaults', () async {
      final t = (await createTask(
        const TaskInput(areaId: 'a1', title: ' Do it '),
      )).valueOrThrow;
      expect(t.title, 'Do it');
      expect(t.bucket, TaskBucket.want);
      expect(t.done, isFalse);
      expect(t.doneAt, isNull);
      expect(t.sortOrder, 0);
      expect(t.recurrence, isNull);
      expect(t.seriesId, isNull);
      expect(t.note, isNull);
    });
    test('task title required / ≤200', () async {
      for (final title in [' ', 'x' * 201]) {
        final r = await createTask(TaskInput(areaId: 'a1', title: title));
        expect(r.failureOrNull, isA<ValidationFailure>());
      }
    });
    test('task note ≤2000, blank → null', () async {
      expect(
        (await createTask(
          TaskInput(areaId: 'a1', title: 'x', note: 'x' * 2001),
        )).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await createTask(
          const TaskInput(areaId: 'a1', title: 'x', note: '  '),
        )).valueOrThrow.note,
        isNull,
      );
    });
    test('task unknown area rejected', () async {
      final r = await createTask(const TaskInput(areaId: 'zz', title: 'x'));
      expect((r.failureOrNull as ValidationFailure?)?.field, 'areaId');
    });
    test('task dueTime without dueDate rejected', () async {
      final r = await createTask(
        const TaskInput(areaId: 'a1', title: 'x', dueTime: '09:00'),
      );
      expect((r.failureOrNull as ValidationFailure?)?.field, 'dueTime');
    });
    test('task bad time rejected', () async {
      final r = await createTask(
        TaskInput(
          areaId: 'a1',
          title: 'x',
          dueDate: DateTime(2026, 9, 24),
          dueTime: '9:00',
        ),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
    });
    test('task recurrence without dueDate rejected', () async {
      final r = await createTask(
        const TaskInput(
          areaId: 'a1',
          title: 'x',
          recurrence: Recurrence.daily(),
        ),
      );
      expect((r.failureOrNull as ValidationFailure?)?.field, 'recurrence');
    });
    test('task remindBefore negative / > 7 days rejected', () async {
      for (final rb in [-1, 10081]) {
        final r = await createTask(
          TaskInput(areaId: 'a1', title: 'x', remindBefore: rb),
        );
        expect(r.failureOrNull, isA<ValidationFailure>());
      }
    });
    test('task amount ≤ 0 rejected', () async {
      final r = await createTask(
        const TaskInput(areaId: 'a1', title: 'x', amount: 0),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
    });
    test('task income category rejected (expense only)', () async {
      final r = await createTask(
        const TaskInput(
          areaId: 'a1',
          title: 'x',
          amount: 10,
          categoryId: 'inc',
        ),
      );
      expect((r.failureOrNull as ValidationFailure?)?.field, 'categoryId');
    });
    test('task recurrence interval 0 / 366 rejected', () async {
      for (final i in [0, 366]) {
        final r = await createTask(
          TaskInput(
            areaId: 'a1',
            title: 'x',
            dueDate: DateTime(2026, 9, 24),
            recurrence: Recurrence.daily(i),
          ),
        );
        expect(r.failureOrNull, isA<ValidationFailure>());
      }
    });
    test('task recurrence defaults materialized, seriesId = id', () async {
      final t = (await createTask(
        TaskInput(
          areaId: 'a1',
          title: 'x',
          dueDate: DateTime(2026, 9, 24),
          recurrence: const Recurrence.weekly(),
        ),
      )).valueOrThrow;
      expect(t.recurrence, const Recurrence.weekly(weekdays: [4]));
      expect(t.seriesId, t.id);
      expect(seriesIdRe.hasMatch(t.seriesId!), isTrue);
    });
    test("task '' ids → null", () async {
      final t = (await createTask(
        const TaskInput(
          areaId: 'a1',
          title: 'x',
          amount: 5,
          walletId: '',
          categoryId: '',
        ),
      )).valueOrThrow;
      expect(t.walletId, isNull);
      expect(t.categoryId, isNull);
    });
    test('new tasks go to the end of their cell', () async {
      final a = (await createTask(
        const TaskInput(areaId: 'a1', title: 'a', bucket: TaskBucket.fire),
      )).valueOrThrow;
      final b = (await createTask(
        const TaskInput(areaId: 'a1', title: 'b', bucket: TaskBucket.fire),
      )).valueOrThrow;
      expect(b.sortOrder, greaterThan(a.sortOrder));
    });
  });

  group('ordering / defaults', () {
    test('compareTasks bucket then sortOrder then oldest', () {
      final xs = [
        tk(id: 's0', bucket: TaskBucket.should, sortOrder: 0),
        tk(id: 'f2', bucket: TaskBucket.fire, sortOrder: 2),
        tk(id: 'f1', bucket: TaskBucket.fire, sortOrder: 1),
        tk(
          id: 'f1old',
          bucket: TaskBucket.fire,
          sortOrder: 1,
          createdAt: DateTime(2020),
        ),
      ]..sort(compareTasks);
      expect(xs.map((t) => t.id), ['f1old', 'f1', 'f2', 's0']);
    });
    test('sortOrderBetween', () {
      expect(sortOrderBetween(1, 2), 1.5);
      expect(sortOrderBetween(null, 2), 1);
      expect(sortOrderBetween(3, null), 4);
      expect(sortOrderBetween(null, null), 0);
    });
    final defs = defaultTaskAreas('u123', t0);
    test('default area ids deterministic', () {
      expect(defs.map((a) => a.id), ['area-kerjaan-u123', 'area-life-u123']);
    });
    test('default Kerjaan', () {
      expect(defs[0].code, 'KERJA');
      expect(defs[0].name, 'Kerjaan');
      expect(defs[0].color, '#1CB0F6');
      expect(defs[0].icon, 'briefcase');
      expect(defs[0].schedule, AreaSchedule.workHours);
      expect(defs[0].sortOrder, 0);
    });
    test('default Keseharian', () {
      expect(defs[1].code, 'LIFE');
      expect(defs[1].name, 'Keseharian');
      expect(defs[1].color, '#58CC02');
      expect(defs[1].icon, 'home');
      expect(defs[1].schedule, isNull);
      expect(defs[1].sortOrder, 1);
    });
    test('default areas pass the icon list', () {
      expect(defs.every((d) => categoryIcons.contains(d.icon)), isTrue);
    });
  });

  group('reminders', () {
    final now = DateTime(2026, 9, 24, 10);
    final areas = [area('a1', code: 'KERJA', name: 'Kerjaan')];

    test('title/body/route/fireAt of a reminder', () {
      final r = computeReminders(
        [
          tk(
            id: 't1',
            title: 'Kirim revisi client A',
            bucket: TaskBucket.fire,
            dueDate: '2026-09-24',
            dueTime: '14:00',
            remindBefore: 30,
            amount: 50000,
          ),
        ],
        areas,
        now,
      );
      expect(r, hasLength(1));
      expect(r.single.key, 't1');
      expect(r.single.title, '[KERJA-FIRE] Kirim revisi client A');
      expect(r.single.fireAt, DateTime(2026, 9, 24, 13, 30));
      expect(r.single.route, '/tasks/t1');
      expect(r.single.body, 'Hari ini 14.00 · Kerjaan · Rp 50.000');
    });
    test('day label is relative to the fire time', () {
      final r = computeReminders(
        [
          tk(
            id: 't',
            dueDate: '2026-09-25',
            dueTime: '00:10',
            remindBefore: 30,
          ),
        ],
        areas,
        now,
      );
      expect(r.single.body, startsWith('Besok 00.10'));
    });
    test('skips done, past, no time, no remindBefore', () {
      final r = computeReminders(
        [
          tk(
            id: 'done',
            done: true,
            dueDate: '2026-09-24',
            dueTime: '14:00',
            remindBefore: 0,
          ),
          tk(
            id: 'past',
            dueDate: '2026-09-24',
            dueTime: '10:20',
            remindBefore: 30,
          ),
          tk(id: 'notime', dueDate: '2026-09-24', remindBefore: 0),
          tk(id: 'noremind', dueDate: '2026-09-24', dueTime: '14:00'),
          tk(
            id: 'at',
            dueDate: '2026-09-24',
            dueTime: '10:00',
            remindBefore: 0,
          ),
        ],
        areas,
        now,
      );
      expect(r.map((x) => x.key), ['at']); // fires now → not in the past
    });
    test('capped at 60, soonest first', () {
      final tasks = [
        for (var i = 0; i < 80; i++)
          tk(
            id: 'k${i.toString().padLeft(2, '0')}',
            dueDate: addDaysKey('2026-09-25', 79 - i),
            dueTime: '09:00',
            remindBefore: 10,
          ),
      ];
      final r = computeReminders(tasks, areas, now);
      expect(r, hasLength(60));
      expect(r.first.key, 'k79');
      for (var i = 1; i < r.length; i++) {
        expect(r[i].fireAt.isBefore(r[i - 1].fireAt), isFalse);
      }
    });
  });

  group('photos', () {
    test('wire: uploaded only, deduped, invalid dropped, max 5', () {
      expect(
        wirePhotos(const [
          TransactionPhoto.remote('/uploads/a.jpg'),
          TransactionPhoto.local('/data/x.jpg'),
          TransactionPhoto.remote('/uploads/a.jpg'),
          TransactionPhoto.remote('/uploads/b-1.png'),
          TransactionPhoto.remote('/uploads/../.env'),
          TransactionPhoto.remote('https://x.com/a.jpg'),
          TransactionPhoto.remote('/uploads/..'),
        ]),
        ['/uploads/a.jpg', '/uploads/b-1.png'],
      );
      expect(
        wirePhotos([
          for (final x in 'abcdef'.split(''))
            TransactionPhoto.remote('/uploads/$x.jpg'),
        ]),
        hasLength(5),
      );
    });
    test('validatePhotos: max 5, deduped', () {
      expect(
        validatePhotos(const [
          TransactionPhoto.remote('/uploads/a.jpg'),
          TransactionPhoto.remote('/uploads/a.jpg'),
        ]),
        [const TransactionPhoto.remote('/uploads/a.jpg')],
      );
      expect(
        () => validatePhotos([
          for (final x in 'abcdef'.split(''))
            TransactionPhoto.local('/tmp/$x.jpg'),
        ]),
        throwsA(isA<ValidationFailure>()),
      );
    });
    test('stored column: lenient decode, local marker round trip', () {
      expect(decodePhotos('["/uploads/a.jpg",3,"local:/d/x.jpg"]'), const [
        TransactionPhoto.remote('/uploads/a.jpg'),
        TransactionPhoto.local('/d/x.jpg'),
      ]);
      expect(decodePhotos('nope'), isEmpty);
      expect(decodePhotos(null), isEmpty);
      expect(
        encodePhotos(const [
          TransactionPhoto.remote('/uploads/a.jpg'),
          TransactionPhoto.local('/d/x.jpg'),
        ]),
        '["/uploads/a.jpg","local:/d/x.jpg"]',
      );
      expect(encodePhotos(const []), '[]');
    });
  });
}

_FixedClock _clock() => _FixedClock(DateTime(2026, 9, 24, 10));

class _FixedClock implements Clock {
  _FixedClock(this.t);
  final DateTime t;
  @override
  DateTime now() => t;
}
