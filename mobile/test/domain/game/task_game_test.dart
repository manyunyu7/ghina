import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart' show TaskBucket;
import 'package:ghina/domain/game/game.dart';
import 'package:ghina/domain/usecases/task_rules.dart' show taskXpDailyCap;

final now = DateTime(2026, 9, 10, 14); // Thursday
final today = GameDate.fromDateTime(now);
DateTime at(int day, [int hour = 12, int minute = 0]) =>
    DateTime(2026, 9, day, hour, minute);

ActivityEvent task(
  String id, {
  int day = 10,
  int minute = 0,
  String bucket = 'fire',
  String? series,
}) => ActivityEvent.task(
  id: id,
  doneAt: at(day, 9, minute),
  bucket: bucket,
  seriesId: series,
  areaId: 'life',
);

ActivityEvent tx(int day, String id) =>
    ActivityEvent.transaction(id: id, createdAt: at(day));

GameSnapshot snap(
  List<ActivityEvent> events, {
  GameLocalState local = const GameLocalState(lastSeenLevel: 1),
}) => const ComputeGameSnapshot()(
  events: events,
  budgets: const [],
  local: local,
  now: now,
);

void main() {
  group('Task XP', () {
    test('rules mirror the task spec constants', () {
      for (final b in TaskBucket.values) {
        expect(XpRules.taskXp(b.wire), b.xp, reason: b.wire);
      }
      expect(XpRules.taskDailyCap, taskXpDailyCap);
    });

    test('XP by bucket, counted on the doneAt day, toward the daily goal', () {
      final s = snap([
        task('a', bucket: 'fire'),
        task('b', bucket: 'want'),
        task('c', bucket: 'should'),
        task('d', day: 9),
      ]).summary;
      final day = s.xp.dayOf(today)!;
      expect(day.breakdown[XpSource.task], 10 + 8 + 5);
      expect(day.tasksCounted, 3);
      expect(s.goal.done, 3);
      expect(s.goal.isMet, isTrue);
      expect(day.breakdown[XpSource.dailyGoal], XpRules.dailyGoalMet);
      expect(s.xp.dayOf(today.addDays(-1))!.breakdown[XpSource.task], 10);
      expect(s.xp.history(count: 2).map((e) => e.$2), [10, 23 + 20]);
    });

    test('at most 20 tasks a day count (earliest first)', () {
      final events = [
        for (var i = 0; i < 25; i++)
          task('t$i', minute: i, bucket: i < 20 ? 'should' : 'fire'),
      ];
      final day = snap(events).summary.xp.dayOf(today)!;
      expect(day.tasksTotal, 25);
      expect(day.tasksCounted, 20);
      // The 20 earliest are SHOULD (5 XP); the later FIRE ones are capped.
      expect(day.breakdown[XpSource.task], 20 * 5);
      expect(day.activities, 20);
    });

    test('un-completing removes the XP (derived)', () {
      final done = snap([task('a'), task('b')]).summary;
      final undone = snap([task('a')]).summary;
      expect(done.totalXp - undone.totalXp, 10);
      expect(undone.goal.done, 1);
    });

    test('tasks never extend the transaction streak', () {
      final s = snap([
        tx(8, 'x1'),
        tx(9, 'x2'),
        task('a'), // today: task only
      ]).summary;
      expect(s.streak.loggedToday, isFalse);
      expect(s.streak.current, 2);
      expect(s.streak.atRisk, isTrue);
    });
  });

  group('Task achievements', () {
    int metric(GameSnapshot s, AchievementMetric m) => s.stats[m];

    test('first task, 10 FIRE, 100 tasks', () {
      final one = snap([task('a', bucket: 'want')]);
      expect(one.achievements.byId('first_task')!.unlocked, isTrue);
      expect(one.achievements.byId('fire_tasks_10')!.unlocked, isFalse);

      final many = snap([
        for (var i = 0; i < 100; i++)
          task('t$i', day: 1 + i % 10, bucket: i < 10 ? 'fire' : 'should'),
      ]);
      expect(metric(many, AchievementMetric.tasksDone), 100);
      expect(metric(many, AchievementMetric.fireTasksDone), 10);
      expect(many.achievements.byId('fire_tasks_10')!.unlocked, isTrue);
      expect(many.achievements.byId('tasks_100')!.unlocked, isTrue);
    });

    test('a recurring series completed 10 times', () {
      final events = [
        // The first occurrence can carry the series id as its own id.
        task('s1', day: 1),
        for (var i = 2; i <= 9; i++) task('s1_$i', day: i, series: 's1'),
        task('other_1', day: 1, series: 'other'),
      ];
      var s = snap(events);
      expect(metric(s, AchievementMetric.bestSeriesCompletions), 9);
      expect(s.achievements.byId('series_10')!.unlocked, isFalse);
      s = snap([...events, task('s1_10', day: 10, series: 's1')]);
      expect(metric(s, AchievementMetric.bestSeriesCompletions), 10);
      expect(s.achievements.byId('series_10')!.unlocked, isTrue);
    });

    test('FIRE kosong counts the recorded snapshot days', () {
      final days = {for (var i = 1; i <= 7; i++) GameDate(2026, 9, i)};
      final six = snap(
        const [],
        local: GameLocalState(
          lastSeenLevel: 1,
          fireClearDays: days.skip(1).toSet(),
        ),
      );
      expect(six.achievements.byId('fire_clear_7')!.current, 6);
      expect(six.achievements.byId('fire_clear_7')!.unlocked, isFalse);
      final seven = snap(
        const [],
        local: GameLocalState(lastSeenLevel: 1, fireClearDays: days),
      );
      final a = seven.achievements.byId('fire_clear_7')!;
      expect(a.unlocked, isTrue);
      expect(a.isNew, isTrue);
      expect(seven.summary.celebrations.newAchievements, contains(a));
    });

    test('new task badges celebrate once, then are seen', () {
      final s = snap([task('a')]);
      expect(
        s.summary.celebrations.newAchievements.map((a) => a.id),
        contains('first_task'),
      );
      final acked = const AcknowledgeCelebrations()(
        const GameLocalState(lastSeenLevel: 1),
        s.summary.celebrations,
        today,
      );
      expect(
        snap([task('a')], local: acked).summary.celebrations.newAchievements,
        isEmpty,
      );
    });
  });

  group('FIRE kosong snapshot rules', () {
    final day = GameDate(2026, 9, 9); // Wednesday
    const life = FireCheckArea(id: 'life');
    const work = FireCheckArea(id: 'work', scheduleDays: {1, 2, 3, 4, 5});
    const weekend = FireCheckArea(id: 'wk', scheduleDays: {6, 7});
    FireCheckTask t({
      String area = 'life',
      String bucket = 'fire',
      DateTime? created,
      DateTime? doneAt,
      String? due,
    }) => FireCheckTask(
      areaId: area,
      bucket: bucket,
      createdAt: created ?? at(1),
      done: doneAt != null,
      doneAt: doneAt,
      dueDate: due == null ? null : GameDate.tryParse(due),
    );

    test('clear when every FIRE task was done that day', () {
      expect(wasFireClear(day, [t(doneAt: at(9, 15))], [life]), isTrue);
    });

    test('needs at least one FIRE completed that day', () {
      expect(wasFireClear(day, [], [life]), isFalse);
      expect(wasFireClear(day, [t(doneAt: at(8, 15))], [life]), isFalse);
      expect(
        wasFireClear(day, [t(bucket: 'want', doneAt: at(9))], [life]),
        isFalse,
      );
    });

    test('an undone FIRE task at the end of the day breaks it', () {
      final tasks = [t(doneAt: at(9, 10)), t()];
      expect(wasFireClear(day, tasks, [life]), isFalse);
      // Completed the next day = still undone at the end of the day.
      final late = [t(doneAt: at(9, 10)), t(doneAt: at(10, 0, 30))];
      expect(wasFireClear(day, late, [life]), isFalse);
    });

    test('ignores tasks created later, due later, or not FIRE', () {
      final tasks = [
        t(doneAt: at(9, 10)),
        t(created: at(10, 8)), // created the next morning
        t(due: '2026-09-10'), // next occurrence of a recurring task
        t(bucket: 'should'),
      ];
      expect(wasFireClear(day, tasks, [life]), isTrue);
      expect(
        wasFireClear(day, [...tasks, t(due: '2026-09-09')], [life]),
        isFalse,
      );
    });

    test("focus areas of the day: unscheduled + scheduled on that weekday", () {
      final undoneWork = t(area: 'work');
      final undoneWeekend = t(area: 'wk');
      final done = t(doneAt: at(9, 10));
      expect(wasFireClear(day, [done, undoneWork], [life, work]), isFalse);
      expect(wasFireClear(day, [done, undoneWeekend], [life, weekend]), isTrue);
      expect(
        wasFireClear(
          day,
          [done, t(area: 'arch')],
          [life, const FireCheckArea(id: 'arch', archived: true)],
        ),
        isTrue,
      );
    });

    test('RecordFireClearDay is add-only and idempotent', () {
      const s0 = GameLocalState();
      final s1 = const RecordFireClearDay()(s0, day);
      expect(s1.fireClearDays, {day});
      expect(identical(const RecordFireClearDay()(s1, day), s1), isTrue);
      final back = GameLocalState.decode(s1.encode());
      expect(back.fireClearDays, {day});
      // Old blobs without the field still decode.
      expect(
        GameLocalState.decode('{"onboardingDone":true}').fireClearDays,
        isEmpty,
      );
    });
  });

  group('Task-aware mascot', () {
    MascotContext base({int hour = 10, bool logged = true}) => MascotContext(
      now: DateTime(2026, 9, 10, hour),
      streak: 5,
      loggedToday: logged,
      goalMet: false,
      goalRemaining: 2,
      hearts: 5,
      maxHearts: 5,
      longestStreak: 5,
    );

    test('many overdue tasks → worried nudge with the count', () {
      final c = base().withTasks(overdueTasks: 4, fireOpen: 1, hasTasks: true);
      final mood = Mascot.moodFor(c);
      expect(mood, MascotMood.worried);
      for (var seed = 0; seed < 6; seed++) {
        final m = Mascot.messageFor(mood, c, seed: seed);
        expect(m, contains('4'));
        expect(
          m.toLowerCase(),
          anyOf(contains('terlambat'), contains('lewat')),
        );
      }
    });

    test('a streak at risk still wins over overdue tasks', () {
      final c = base(
        hour: 20,
        logged: false,
      ).withTasks(overdueTasks: 4, fireOpen: 0, hasTasks: true);
      expect(Mascot.moodFor(c), MascotMood.worried);
      final m = Mascot.messageFor(MascotMood.worried, c, seed: 0);
      expect(m, isNot(contains('tugas')));
    });

    test('open FIRE tasks / FIRE kosong lines join the pool', () {
      final fire = base().withTasks(
        overdueTasks: 0,
        fireOpen: 2,
        hasTasks: true,
      );
      final fireLines = {
        for (var seed = 0; seed < 20; seed++)
          Mascot.messageFor(MascotMood.happy, fire, seed: seed),
      };
      expect(
        fireLines,
        contains('Masih ada 2 tugas FIRE 🔥 Beresin dulu, baru santai!'),
      );

      final clear = base().withTasks(
        overdueTasks: 0,
        fireOpen: 0,
        hasTasks: true,
      );
      final clearLines = {
        for (var seed = 0; seed < 20; seed++)
          Mascot.messageFor(MascotMood.happy, clear, seed: seed),
      };
      expect(clearLines.any((l) => l.contains('FIRE')), isTrue);

      final none = base();
      final plain = {
        for (var seed = 0; seed < 20; seed++)
          Mascot.messageFor(MascotMood.happy, none, seed: seed),
      };
      expect(plain.any((l) => l.contains('FIRE')), isFalse);
    });

    test('few overdue tasks keep the normal mood', () {
      final c = base().withTasks(overdueTasks: 2, fireOpen: 0, hasTasks: true);
      expect(Mascot.moodFor(c), MascotMood.happy);
    });
  });
}
