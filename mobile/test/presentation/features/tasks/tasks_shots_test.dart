// Screenshots of the Tugas screens for visual review:
// GHINA_SHOTS_DIR=/some/dir flutter test test/presentation/features/tasks/tasks_shots_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/tasks/widgets/reminder_settings.dart';

import '../../design_system/_helpers.dart';
import '_tasks_harness.dart';
import 'tasks_test.dart' show taskRoutes;

const _key = ValueKey('shot');

TasksHarness _seeded() {
  final h = TasksHarness()..seedAreas();
  h.wallets.s.put(wallet('w1', 'Tunai'));
  h.tasks.s
    ..put(
      task(
        'a',
        'Kirim revisi desain ke klien',
        bucket: TaskBucket.fire,
        dueDate: '2026-09-23',
        dueTime: '14:00',
        remindBefore: 10,
      ),
    )
    ..put(
      task(
        'b',
        'Bayar tagihan internet kantor',
        bucket: TaskBucket.fire,
        dueDate: '2026-09-22',
        amount: 350000,
        walletId: 'w1',
        sortOrder: 1,
      ),
    )
    ..put(
      task(
        'c',
        'Siapin slide presentasi Q4',
        bucket: TaskBucket.want,
        dueDate: '2026-09-24',
      ),
    )
    ..put(
      task(
        'd',
        'Beli hadiah ultah Ibu',
        areaId: 'life',
        bucket: TaskBucket.want,
        dueDate: '2026-09-28',
        amount: 250000,
        sortOrder: 1,
      ),
    )
    ..put(
      task(
        'e',
        'Laporan mingguan tim',
        bucket: TaskBucket.should,
        dueDate: '2026-09-25',
        dueTime: '16:00',
        recurrence: const Recurrence.weekly(weekdays: [5]),
      ),
    )
    ..put(
      task(
        'f',
        'Rapikan folder dokumen',
        areaId: 'life',
        bucket: TaskBucket.should,
        sortOrder: 1,
      ),
    )
    ..put(task('g', 'Balas email vendor', done: true));
  return h;
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Future<void> Function(WidgetTester t)? act,
}) async {
  await loadGhinaFonts();
  final h = _seeded();
  await pumpTasks(
    tester,
    h,
    location: location,
    routes: taskRoutes,
    dark: dark,
    size: size,
    textScale: textScale,
    boundaryKey: _key,
  );
  if (act != null) await act(tester);
  await saveShot(tester, _key, name);
  expect(tester.takeException(), isNull);
  await settle(tester, 40);
}

Future<void> _all(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const ValueKey('area-all')));
  await t.tap(find.byKey(const ValueKey('area-all')));
  await settle(t, 4);
}

void main() {
  testWidgets('tab focus light', (t) => _shot(t, 'tasks_tab_light', '/tasks'));
  testWidgets(
    'tab all light',
    (t) => _shot(t, 'tasks_tab_all_light', '/tasks', act: _all),
  );
  testWidgets(
    'tab all dark',
    (t) => _shot(t, 'tasks_tab_all_dark', '/tasks', dark: true, act: _all),
  );
  testWidgets(
    'tab small',
    (t) => _shot(
      t,
      'tasks_tab_small',
      '/tasks',
      size: const Size(360, 640),
      textScale: 1.3,
      act: _all,
    ),
  );
  testWidgets(
    'quick add',
    (t) => _shot(
      t,
      'tasks_quick_add',
      '/tasks',
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('task-add')));
        await settle(t, 5);
      },
    ),
  );
  testWidgets(
    'quick add small',
    (t) => _shot(
      t,
      'tasks_quick_add_small',
      '/tasks',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('task-add')));
        await settle(t, 5);
      },
    ),
  );
  testWidgets(
    'expense dialog',
    (t) => _shot(
      t,
      'tasks_expense_dialog',
      '/tasks',
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('task-check-b')));
        await settle(t, 6);
      },
    ),
  );
  testWidgets(
    'reminder settings',
    (t) => _shot(
      t,
      'tasks_reminder_settings',
      '/tasks',
      act: (t) async {
        showReminderSettingsSheet(t.element(find.text('Tugas').first));
        await settle(t, 5);
      },
    ),
  );
  testWidgets('task form', (t) => _shot(t, 'tasks_form', '/tasks/e'));
  testWidgets(
    'task form dark',
    (t) => _shot(t, 'tasks_form_dark', '/tasks/b', dark: true),
  );
  testWidgets(
    'task form small',
    (t) => _shot(
      t,
      'tasks_form_small',
      '/tasks/e',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'task form recurrence',
    (t) => _shot(
      t,
      'tasks_form_recurrence',
      '/tasks/e',
      act: (t) async {
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('recurrence-summary')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await settle(t, 3);
      },
    ),
  );
  testWidgets('areas', (t) => _shot(t, 'tasks_areas', '/tasks/areas'));
  testWidgets(
    'area form',
    (t) => _shot(t, 'tasks_area_form', '/tasks/areas/kerja'),
  );
  testWidgets(
    'area form small dark',
    (t) => _shot(
      t,
      'tasks_area_form_small_dark',
      '/tasks/areas/kerja',
      dark: true,
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'done list',
    (t) => _shot(
      t,
      'tasks_done',
      '/tasks',
      act: (t) async {
        await t.ensureVisible(find.byKey(const ValueKey('status-done')));
        await t.tap(find.byKey(const ValueKey('status-done')));
        await settle(t, 4);
      },
    ),
  );
}
