import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/home/pages/home_page.dart';

import '../../design_system/_helpers.dart';
import '../shell/test_utils.dart';
import '_task_harness.dart';

/// Renders Beranda in light/dark (viewport + full length) and on a small phone with
/// large text. Set GHINA_SHOTS_DIR to write PNGs.
void main() {
  setUpAll(loadGhinaFonts);
  group('tasks', taskShots);
  const key = ValueKey('shot');

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('home renders ($mode)', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: withTasks(pageOverrides(events: streakEvents(6))),
        dark: dark,
        boundaryKey: key,
      );
      await settle(tester, 10);
      final error = tester.takeException();
      await saveShot(tester, key, 'home_$mode');
      expect(error, isNull);
    });

    testWidgets('home full length ($mode)', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: withTasks(pageOverrides(events: streakEvents(6))),
        dark: dark,
        size: const Size(390, 2150),
        boundaryKey: key,
      );
      await settle(tester, 10);
      final error = tester.takeException();
      await saveShot(tester, key, 'home_full_$mode');
      expect(error, isNull);
    });
  }

  testWidgets('home empty account (light)', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: withTasks(
        pageOverrides(
          dashboard: sampleDashboard(empty: true),
          budgets: sampleBudgets(empty: true),
        ),
      ),
      size: const Size(390, 1700),
      boundaryKey: key,
    );
    await settle(tester, 10);
    final error = tester.takeException();
    await saveShot(tester, key, 'home_empty_light');
    expect(error, isNull);
  });

  testWidgets('home fits a small phone with large text', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: withTasks(pageOverrides(events: streakEvents(12))),
      size: const Size(360, 2400),
      textScale: 1.3,
      boundaryKey: key,
    );
    await settle(tester, 10);
    final error = tester.takeException();
    await saveShot(tester, key, 'home_small_text130');
    expect(error, isNull);
  });
}

/// Beranda with tasks: FIRE card (money link, overdue, recurring), Sunday
/// "Sapu bersih", and the FIRE kosong empty state.
HomeTaskFixture taskFixture({DateTime? now, bool empty = false}) {
  final fx = HomeTaskFixture(now: now)
    ..life()
    ..area(
      'work',
      'Kerjaan',
      'KERJA',
      schedule: AreaSchedule.workHours,
      sortOrder: -1,
    )
    ..wallet('w1', 'Tunai', 350000);
  if (empty) return fx;
  fx
    ..task('f1', 'Kirim revisi desain ke klien A', areaId: 'work')
    ..task(
      'f2',
      'Bayar tagihan listrik bulan ini',
      areaId: 'work',
      amount: 245000,
      walletId: 'w1',
      dueDate: '2026-09-23',
      sortOrder: 1,
    )
    ..task(
      'f3',
      'Balas email HRD',
      areaId: 'work',
      dueDate: '2026-09-21',
      sortOrder: 2,
    )
    ..task('s1', 'Rapikan lemari', bucket: TaskBucket.should)
    ..task('s2', 'Cuci sepatu putih', bucket: TaskBucket.should);
  return fx;
}

void taskShots() {
  const key = ValueKey('shot');
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('home tasks card ($mode)', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: withTasks(
          pageOverrides(events: streakEvents(6)),
          taskFixture(),
        ),
        dark: dark,
        size: const Size(390, 1500),
        boundaryKey: key,
      );
      await settle(tester, 10);
      final error = tester.takeException();
      await saveShot(tester, key, 'home_tasks_$mode');
      expect(error, isNull);
    });
  }

  testWidgets('home tasks: Sunday sapu bersih + FIRE kosong', (tester) async {
    final fx = taskFixture(now: DateTime(2026, 9, 27, 9));
    fx.tasks.s.items.removeWhere((id, _) => id.startsWith('f'));
    await pumpPage(
      tester,
      const HomePage(),
      overrides: withTasks(pageOverrides(events: streakEvents(6)), fx),
      size: const Size(390, 1700),
      boundaryKey: key,
    );
    await settle(tester, 10);
    final error = tester.takeException();
    await saveShot(tester, key, 'home_tasks_sunday');
    expect(error, isNull);
  });

  testWidgets('home tasks fit 360×640 at 1.3× text', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: withTasks(
        pageOverrides(events: streakEvents(6)),
        taskFixture(),
      ),
      size: const Size(360, 1800),
      textScale: 1.3,
      boundaryKey: key,
    );
    await settle(tester, 10);
    final error = tester.takeException();
    await saveShot(tester, key, 'home_tasks_small_text130');
    expect(error, isNull);
  });
}
