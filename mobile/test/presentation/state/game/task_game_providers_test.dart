import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/game/task_game_providers.dart';

import '../../../domain/fakes.dart';

/// "FIRE kosong" snapshot recorder + task-aware mascot, with a fake clock,
/// hourly tick and in-memory game store / task repositories.
void main() {
  late FixedClock clock;
  late StreamController<int> hourTick;
  late StreamController<DateTime> minuteTick;
  late InMemoryGameStore store;
  late FakeTaskRepository tasks;
  late FakeTaskAreaRepository areas;
  late ProviderContainer container;

  Task task(
    String id, {
    TaskBucket bucket = TaskBucket.fire,
    DateTime? created,
    DateTime? doneAt,
    String? due,
  }) => Task(
    id: id,
    areaId: 'life',
    title: id,
    bucket: bucket,
    dueDate: due,
    done: doneAt != null,
    doneAt: doneAt,
    createdAt: created ?? DateTime(2026, 9, 1),
    updatedAt: doneAt ?? DateTime(2026, 9, 1),
  );

  GameLocalState saved() =>
      GameLocalState.decode(store.values[GameLocalState.storageKey]);

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void start({GameLocalState local = const GameLocalState()}) {
    store = InMemoryGameStore({GameLocalState.storageKey: local.encode()});
    container = ProviderContainer(
      overrides: [
        gameStoreProvider.overrideWithValue(store),
        gameClockProvider.overrideWithValue(clock),
        clockProvider.overrideWithValue(clock),
        gameTickProvider.overrideWith((ref) => hourTick.stream),
        tickSourceProvider.overrideWithValue(
          () => Stream<DateTime>.multi((c) {
            c.add(clock.now());
            final sub = minuteTick.stream.listen(c.add);
            c.onCancel = sub.cancel;
          }),
        ),
        taskRepositoryProvider.overrideWithValue(tasks),
        taskAreaRepositoryProvider.overrideWithValue(areas),
        activityEventsSourceProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        budgetStatusSourceProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  setUp(() {
    clock = FixedClock(DateTime(2026, 9, 10, 8)); // Thursday morning
    hourTick = StreamController.broadcast();
    minuteTick = StreamController.broadcast();
    tasks = FakeTaskRepository();
    areas = FakeTaskAreaRepository();
    addTearDown(hourTick.close);
    addTearDown(minuteTick.close);
    areas.save(
      TaskArea(
        id: 'life',
        name: 'Keseharian',
        code: 'LIFE',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ),
    );
  });

  group('fireClearRecorderProvider', () {
    test('first open of the day records a FIRE-free yesterday', () async {
      tasks.save(task('a', doneAt: DateTime(2026, 9, 9, 15)));
      tasks.save(task('b', bucket: TaskBucket.should)); // not FIRE
      start();
      container.listen(fireClearRecorderProvider, (_, _) {});
      await flush();
      expect(saved().fireClearDays, {GameDate(2026, 9, 9)});
      expect(container.read(fireClearRecorderProvider), GameDate(2026, 9, 9));
      // The FIRE kosong badge now counts it.
      container.listen(achievementsProvider, (_, _) {});
      final a = (await container.read(
        achievementsProvider.future,
      )).byId('fire_clear_7')!;
      expect(a.current, 1);
    });

    test(
      'an undone FIRE task at the end of yesterday records nothing',
      () async {
        tasks.save(task('a', doneAt: DateTime(2026, 9, 9, 15)));
        tasks.save(task('b', doneAt: DateTime(2026, 9, 10, 7))); // done today
        start();
        container.listen(fireClearRecorderProvider, (_, _) {});
        await flush();
        expect(saved().fireClearDays, isEmpty);
        expect(container.read(fireClearRecorderProvider), isNull);
      },
    );

    test(
      'records are add-only: a later empty task list keeps the day',
      () async {
        final day = GameDate(2026, 9, 9);
        start(local: GameLocalState(fireClearDays: {day}));
        container.listen(fireClearRecorderProvider, (_, _) {});
        await flush();
        expect(saved().fireClearDays, {day});
      },
    );

    test(
      'the tick crossing midnight evaluates the day that just ended',
      () async {
        clock.current = DateTime(2026, 9, 9, 22);
        tasks.save(task('a', doneAt: DateTime(2026, 9, 9, 21)));
        start();
        container.listen(fireClearRecorderProvider, (_, _) {});
        await flush();
        // Sep 8 had no FIRE completed → nothing yet.
        expect(saved().fireClearDays, isEmpty);

        clock.current = DateTime(2026, 9, 10, 0, 1);
        hourTick.add(2026091000);
        minuteTick.add(clock.now());
        await flush();
        expect(saved().fireClearDays, {GameDate(2026, 9, 9)});
      },
    );
  });

  group('homeMascotProvider', () {
    test('many overdue tasks make the mascot worried', () async {
      for (var i = 0; i < 3; i++) {
        tasks.save(task('o$i', due: '2026-09-0${i + 1}'));
      }
      start(local: const GameLocalState(lastSeenLevel: 1));
      container.listen(homeMascotProvider, (_, _) {});
      container.listen(gameSummaryProvider, (_, _) {});
      await container.read(gameSummaryProvider.future);
      await flush();
      final line = container.read(homeMascotProvider)!;
      expect(line.mood, MascotMood.worried);
      expect(line.message, contains('3'));
    });

    test('falls back to the summary line without task trouble', () async {
      start(local: const GameLocalState(lastSeenLevel: 1));
      container.listen(homeMascotProvider, (_, _) {});
      container.listen(gameSummaryProvider, (_, _) {});
      final s = await container.read(gameSummaryProvider.future);
      await flush();
      expect(container.read(homeMascotProvider)!.mood, s.mood);
    });
  });
}
