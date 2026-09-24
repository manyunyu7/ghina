import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/app/router.dart';
import 'package:ghina/data/notifications/notifications.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/shell/app_shell.dart';
import 'package:ghina/presentation/features/shell/notification_navigation.dart';
import 'package:ghina/presentation/features/tasks/pages/task_area_form_page.dart';
import 'package:ghina/presentation/features/tasks/pages/task_areas_page.dart';
import 'package:ghina/presentation/features/tasks/pages/task_form_page.dart';
import 'package:ghina/presentation/features/tasks/pages/tasks_page.dart';
import 'package:ghina/presentation/features/tasks/task_draft.dart';
import 'package:ghina/presentation/features/tasks/task_format.dart';
import 'package:ghina/presentation/state/notifications/notification_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '_tasks_harness.dart';

List<RouteBase> get taskRoutes => [
  GoRoute(path: '/tasks', builder: (_, _) => const TasksPage()),
  GoRoute(path: '/tasks/areas', builder: (_, _) => const TaskAreasPage()),
  GoRoute(
    path: '/tasks/areas/new',
    builder: (_, _) => const TaskAreaFormPage(),
  ),
  GoRoute(
    path: '/tasks/areas/:id',
    builder: (_, s) => TaskAreaFormPage(id: s.pathParameters['id']),
  ),
  GoRoute(
    path: '/tasks/new',
    builder: (_, s) => TaskFormPage(draft: s.extra as TaskDraft?),
  ),
  GoRoute(
    path: '/tasks/:id',
    builder: (_, s) => TaskFormPage(id: s.pathParameters['id']),
  ),
];

void main() {
  group('formatting', () {
    final now = DateTime(2026, 9, 23, 10); // Wednesday

    test('recurrence summary', () {
      expect(
        recurrenceSummary(
          const Recurrence.weekly(interval: 2, weekdays: [1, 4]),
        ),
        'Tiap 2 minggu, Sen & Kam',
      );
      expect(recurrenceSummary(const Recurrence.daily()), 'Tiap hari');
      expect(recurrenceSummary(const Recurrence.daily(3)), 'Tiap 3 hari');
      expect(
        recurrenceSummary(const Recurrence.weekly(weekdays: [1, 3, 5])),
        'Tiap minggu, Sen, Rab & Jum',
      );
      expect(
        recurrenceSummary(
          const Recurrence.monthly(),
          dueDay: DateTime(2026, 9, 15),
        ),
        'Tiap bulan, tgl 15',
      );
      expect(
        recurrenceSummary(
          const Recurrence.weekly(),
          dueDay: DateTime(2026, 10, 1),
        ),
        'Tiap minggu, Kam',
      );
    });

    test('due labels', () {
      expect(
        dueLabel(task('a', 'x', dueDate: '2026-09-23', dueTime: '14:00'), now),
        'Hari ini 14.00',
      );
      expect(dueLabel(task('a', 'x', dueDate: '2026-09-24'), now), 'Besok');
      expect(dueLabel(task('a', 'x', dueDate: '2026-09-22'), now), 'Kemarin');
      expect(dueLabel(task('a', 'x', dueDate: '2026-09-28'), now), 'Sen 28/9');
      expect(
        dueLabel(task('a', 'x', dueDate: '2027-01-04'), now),
        'Sen 4/1/27',
      );
      expect(dueLabel(task('a', 'x'), now), isNull);
      expect(shortDate(DateTime(2026, 10, 1)), 'Kam, 1 Okt');
    });

    test('area code + schedule', () {
      expect(sanitizeAreaCode('kuliah s2-ok!'), 'KULIAHS2');
      expect(scheduleSummary(AreaSchedule.workHours), 'Sen–Jum · 09.00–17.00');
      expect(scheduleSummary(null), 'Kapan saja');
      expect(
        notificationPreview('KERJA', TaskBucket.fire, 'Contoh tugas'),
        '[KERJA-FIRE] Contoh tugas',
      );
    });
  });

  group('shell', () {
    test('Tugas tab replaces Belajar; /learn stays a pushed route', () {
      final c = ProviderContainer(
        overrides: [sessionControllerProvider.overrideWith(_SignedOut.new)],
      );
      addTearDown(c.dispose);
      final router = c.read(routerProvider);
      final routes = router.configuration.routes;
      final shell = routes.whereType<StatefulShellRoute>().single;
      final tabPaths = [
        for (final b in shell.branches) (b.routes.single as GoRoute).path,
      ];
      expect(tabPaths, ['/home', '/transactions', '/tasks', '/profile']);
      final top = routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(top, containsAll(['/learn', '/learn/lesson/:lessonId']));
      expect(
        top,
        containsAll([
          '/tasks/new',
          '/tasks/:id',
          '/tasks/areas',
          '/tasks/areas/new',
          '/tasks/areas/:id',
        ]),
      );
      // Literal area routes must win over /tasks/:id.
      expect(top.indexOf('/tasks/areas'), lessThan(top.indexOf('/tasks/:id')));
    });

    testWidgets('nav bar shows Tugas and switches to the tasks branch', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => AppShell(navigationShell: shell),
            branches: [
              for (final p in ['/home', '/transactions', '/tasks', '/profile'])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: p,
                      builder: (_, _) => Scaffold(body: Text('TAB $p')),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await settle(tester, 3);
      expect(find.text('Tugas'), findsOneWidget);
      expect(find.text('Belajar'), findsNothing);
      await tester.tap(find.text('Tugas'));
      await settle(tester, 3);
      expect(find.text('TAB /tasks'), findsOneWidget);
      // The shell started the reminder sync (debounced replaceAll).
      await tester.pump(const Duration(seconds: 1));
      expect(h.scheduler.lastScheduled, isNotNull);
    });
  });

  group('notification taps', () {
    GoRouter makeRouter() => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
        GoRoute(
          path: '/tasks/:id',
          builder: (_, s) => Text('TASK ${s.pathParameters['id']}'),
        ),
      ],
    );

    Future<void> pumpGate(
      WidgetTester tester,
      GoRouter router,
      StreamController<String> taps,
      bool Function() canOpen,
    ) async {
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRoutesProvider.overrideWithValue(taps.stream),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) => NotificationRouteGate(
              router: router,
              canOpen: canOpen,
              child: child!,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('tapping a reminder opens the task', (tester) async {
      final taps = StreamController<String>.broadcast();
      final router = makeRouter();
      await pumpGate(tester, router, taps, () => true);
      taps.add('/tasks/t1');
      await settle(tester, 3);
      expect(find.text('TASK t1'), findsOneWidget);
      // Back returns to where the user was.
      router.pop();
      await settle(tester, 3);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('waits until the app is ready (cold start / signed out)', (
      tester,
    ) async {
      final taps = StreamController<String>.broadcast();
      final router = makeRouter();
      var ready = false;
      await pumpGate(tester, router, taps, () => ready);
      router.go('/login');
      await settle(tester, 2);
      taps.add('/tasks/t9');
      await settle(tester, 3);
      expect(find.text('TASK t9'), findsNothing);
      ready = true;
      router.go('/home'); // the redirect after sign-in
      await settle(tester, 3);
      expect(find.text('TASK t9'), findsOneWidget);
    });
  });

  group('Tugas tab', () {
    testWidgets('focus areas preselected; buckets with counts; Semua', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(
        task(
          'a',
          'Kirim revisi',
          bucket: TaskBucket.fire,
          dueDate: '2026-09-23',
          dueTime: '14:00',
        ),
      );
      h.tasks.s.put(
        task(
          'b',
          'Siapin slide',
          bucket: TaskBucket.want,
          dueDate: '2026-09-24',
        ),
      );
      h.tasks.s.put(
        task('c', 'Beli sabun', areaId: 'life', bucket: TaskBucket.should),
      );
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);

      expect(find.text('Kirim revisi'), findsOneWidget);
      expect(find.text('Hari ini 14.00'), findsOneWidget);
      expect(find.text('Mepet'), findsOneWidget); // WANT due tomorrow
      expect(find.text('Beli sabun'), findsNothing); // not a focus area now
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('count-fire')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Fokus: Kerjaan'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('area-all')));
      await tester.tap(find.byKey(const ValueKey('area-all')));
      await settle(tester, 4);
      expect(find.text('Beli sabun'), findsOneWidget);
      expect(find.text('Keseharian'), findsWidgets); // area name on the tile

      await tester.tap(find.byKey(const ValueKey('area-life')));
      await settle(tester, 4);
      expect(find.text('Kirim revisi'), findsNothing);
      expect(find.text('Beli sabun'), findsOneWidget);
    });

    testWidgets('quick add: title + bucket + Hari ini → saved in focus area', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);
      expect(find.text('Belum ada tugas'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('task-add')));
      await settle(tester, 4);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('quick-title')),
          matching: find.byType(EditableText),
        ),
        'Bayar listrik',
      );
      await tester.tap(find.text('🔥 FIRE').last);
      await tester.tap(find.text('Hari ini').last);
      await settle(tester, 2);
      await tester.tap(find.byKey(const ValueKey('quick-save')));
      await settle(tester, 6);

      final saved = h.tasks.s.items.values.single;
      expect(saved.title, 'Bayar listrik');
      expect(saved.bucket, TaskBucket.fire);
      expect(saved.areaId, 'kerja');
      expect(saved.dueDate, '2026-09-23');
      expect(saved.remindBefore, isNull); // no time → no reminder
      expect(find.text('Bayar listrik'), findsOneWidget);
    });

    testWidgets('quick add validates the title', (tester) async {
      final h = TasksHarness()..seedAreas();
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);
      await tester.tap(find.byKey(const ValueKey('task-add')));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('quick-save')));
      await settle(tester, 3);
      expect(find.text('Tulis tugasnya dulu, ya'), findsOneWidget);
      expect(h.tasks.s.items, isEmpty);
    });

    testWidgets('complete without money link: check → done + toast', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(task('a', 'Kirim revisi', bucket: TaskBucket.fire));
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);

      await tester.tap(find.byKey(const ValueKey('task-check-a')));
      await settle(tester, 20);
      expect(h.tasks.s.items['a']!.done, isTrue);
      expect(h.transactions.s.items, isEmpty);
      expect(find.textContaining('Beres! +10 XP'), findsOneWidget);
      await settle(tester, 30); // toast leaves
    });

    testWidgets('complete with money link → "Ya, catat" records the expense', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.wallets.s.put(wallet('w1', 'Tunai'));
      h.tasks.s.put(
        task(
          'a',
          'Bayar kos',
          bucket: TaskBucket.fire,
          amount: 50000,
          walletId: 'w1',
        ),
      );
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);

      await tester.tap(find.byKey(const ValueKey('task-check-a')));
      await settle(tester, 6);
      expect(find.text('Catat pengeluaran Rp 50.000?'), findsOneWidget);
      await tester.tap(find.text('YA, CATAT'));
      await settle(tester, 20);

      final tx = h.transactions.s.items.values.single;
      expect(tx.amount, 50000);
      expect(tx.walletId, 'w1');
      expect(tx.type, TxType.expense);
      expect(h.tasks.s.items['a']!.done, isTrue);
      expect(h.tasks.s.items['a']!.transactionId, tx.id);
      await settle(tester, 30);
    });

    testWidgets('complete with money link → "Selesai saja" skips the expense', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.wallets.s.put(wallet('w1', 'Tunai'));
      h.tasks.s.put(task('a', 'Bayar kos', amount: 50000));
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);

      await tester.tap(find.byKey(const ValueKey('task-check-a')));
      await settle(tester, 6);
      await tester.tap(find.text('SELESAI SAJA'));
      await settle(tester, 20);
      expect(h.tasks.s.items['a']!.done, isTrue);
      expect(h.transactions.s.items, isEmpty);
      await settle(tester, 30);
    });

    testWidgets('recurring task → toast shows the next occurrence', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(
        task(
          'a',
          'Laporan mingguan',
          dueDate: '2026-09-23',
          recurrence: const Recurrence.weekly(weekdays: [3]),
        ),
      );
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);
      await tester.tap(find.byKey(const ValueKey('task-check-a')));
      await settle(tester, 20);
      expect(find.textContaining('Berikutnya: Rab, 30 Sep'), findsOneWidget);
      expect(h.tasks.s.items.length, 2);
      await settle(tester, 30);
    });

    testWidgets('Selesai filter lists done tasks; tap check reopens', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(task('a', 'Sudah beres', done: true));
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);
      expect(find.text('Sudah beres'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('status-done')));
      await tester.tap(find.byKey(const ValueKey('status-done')));
      await settle(tester, 4);
      expect(find.text('Sudah beres'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-check-a')));
      await settle(tester, 6);
      expect(h.tasks.s.items['a']!.done, isFalse);
      await settle(tester, 30);
    });

    testWidgets('long-press → move to another bucket', (tester) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(task('a', 'Pindahin aku', bucket: TaskBucket.should));
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);
      await tester.longPress(find.text('Pindahin aku'));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('move-fire')));
      await settle(tester, 6);
      expect(h.tasks.s.items['a']!.bucket, TaskBucket.fire);
      await settle(tester, 30);
    });

    testWidgets('swipe left deletes after the undo snackbar', (tester) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(task('a', 'Hapus aku'));
      await pumpTasks(tester, h, location: '/tasks', routes: taskRoutes);
      await tester.drag(find.text('Hapus aku'), const Offset(-500, 0));
      await settle(tester, 6);
      expect(find.text('Hapus aku'), findsNothing);
      expect(find.text('BATAL'), findsOneWidget);
      expect(h.tasks.s.items, isNotEmpty); // not yet
      await settle(tester, 50);
      expect(h.tasks.s.items, isEmpty);
    });
  });

  group('task form', () {
    testWidgets('recurrence builder summary: Tiap 2 minggu, Sen & Kam', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(task('a', 'Standup', dueDate: '2026-09-28')); // a Monday
      await pumpTasks(tester, h, location: '/tasks/a', routes: taskRoutes);
      await tester.scrollUntilVisible(
        find.text('Mingguan'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Mingguan'));
      await settle(tester, 3);
      expect(find.text('Tiap minggu, Sen'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('interval-plus')));
      await tester.tap(find.byKey(const ValueKey('interval-plus')));
      await settle(tester, 2);
      await tester.ensureVisible(find.byKey(const ValueKey('weekday-4')));
      await tester.tap(find.byKey(const ValueKey('weekday-4')));
      await settle(tester, 2);
      expect(find.text('Tiap 2 minggu, Sen & Kam'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('task-save')));
      await settle(tester, 6);
      expect(
        h.tasks.s.items['a']!.recurrence,
        const Recurrence.weekly(interval: 2, weekdays: [1, 4]),
      );
      await settle(tester, 30);
    });

    testWidgets('new task from a draft with time gets the default reminder', (
      tester,
    ) async {
      final h = TasksHarness()..seedAreas();
      h.settings.value = const NotificationSettings(defaultRemindBefore: 30);
      final router = await pumpTasks(
        tester,
        h,
        location: '/tasks',
        routes: taskRoutes,
      );
      router.push(
        '/tasks/new',
        extra: TaskDraft(
          title: 'Meeting klien',
          bucket: TaskBucket.fire,
          areaId: 'kerja',
          dueDate: DateTime(2026, 9, 24),
          dueTime: '15:00',
        ),
      );
      await settle(tester, 6);
      await tester.scrollUntilVisible(
        find.text('30 mnt'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('30 mnt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-save')));
      await settle(tester, 6);
      final t = h.tasks.s.items.values.single;
      expect(t.title, 'Meeting klien');
      expect(t.dueTime, '15:00');
      expect(t.remindBefore, 30);
      await settle(tester, 30);
    });

    testWidgets('setting a reminder without permission explains, then asks', (
      tester,
    ) async {
      final h = TasksHarness(permission: NotificationPermissionStatus.denied)
        ..seedAreas();
      h.scheduler.grantOnRequest = false;
      h.tasks.s.put(
        task('a', 'Rapat', dueDate: '2026-09-24', dueTime: '09:00'),
      );
      await pumpTasks(tester, h, location: '/tasks/a', routes: taskRoutes);
      await tester.scrollUntilVisible(
        find.text('10 mnt'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('10 mnt'));
      await settle(tester, 4);
      expect(find.text('Boleh Ghina ngingetin? 🔔'), findsOneWidget);
      await tester.tap(find.text('IZINKAN'));
      await settle(tester, 4);
      expect(h.scheduler.requests, 1);
      expect(find.text('Notifikasi masih mati'), findsOneWidget);
      await tester.tap(find.text('BUKA PENGATURAN'));
      await settle(tester, 4);
      expect(h.scheduler.settingsOpened, 1);
      await settle(tester, 30);
    });
  });

  group('area form', () {
    test('validateAreaForm', () {
      expect(
        validateAreaForm(
          name: '',
          code: 'kerja',
          scheduled: true,
          days: {},
          start: '09:00',
          end: '08:00',
        ).keys,
        containsAll(['name', 'code', 'schedule']),
      );
      expect(
        validateAreaForm(
          name: 'Kuliah',
          code: 'KULIAH',
          scheduled: true,
          days: {1},
          start: '10:00',
          end: '09:00',
        ),
        {'schedule': 'Jam mulai harus sebelum jam selesai'},
      );
      expect(
        validateAreaForm(
          name: 'Kuliah',
          code: 'KULIAH',
          scheduled: false,
          days: {},
          start: '09:00',
          end: '17:00',
        ),
        isEmpty,
      );
    });

    testWidgets('code preview, validation and duplicate code', (tester) async {
      final h = TasksHarness()..seedAreas();
      await pumpTasks(
        tester,
        h,
        location: '/tasks/areas/new',
        routes: taskRoutes,
      );

      await tester.tap(find.byKey(const ValueKey('area-save')));
      await settle(tester, 3);
      expect(find.text('Kasih nama areanya dulu, ya'), findsOneWidget);

      Finder input(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      );
      await tester.enterText(input('area-name'), 'Kuliah S2');
      await settle(tester, 2);
      expect(find.text('[KULIAHS2-FIRE] Contoh tugas'), findsOneWidget);

      await tester.enterText(input('area-code'), 'kerja!');
      await settle(tester, 2);
      expect(find.text('[KERJA-FIRE] Contoh tugas'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('area-save')));
      await settle(tester, 4);
      expect(find.text('Kode sudah dipakai area lain'), findsOneWidget);

      await tester.enterText(input('area-code'), 'kul');
      await settle(tester, 2);
      await tester.scrollUntilVisible(
        find.text('Terjadwal'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Terjadwal'));
      await settle(tester, 2);
      for (var d = 1; d <= 5; d++) {
        await tester.ensureVisible(find.byKey(ValueKey('area-day-$d')));
        await tester.tap(find.byKey(ValueKey('area-day-$d')));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const ValueKey('area-save')));
      await settle(tester, 3);
      expect(find.text('Pilih minimal satu hari'), findsWidgets);

      await tester.ensureVisible(find.byKey(const ValueKey('area-day-2')));
      await tester.tap(find.byKey(const ValueKey('area-day-2')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('area-save')));
      await settle(tester, 6);
      final created = h.areas.s.items.values.firstWhere((a) => a.code == 'KUL');
      expect(created.name, 'Kuliah S2');
      expect(created.schedule?.days, [2]);
      await settle(tester, 30);
    });

    testWidgets('area manager: delete warns that tasks go too', (tester) async {
      final h = TasksHarness()..seedAreas();
      h.tasks.s.put(task('a', 'Laporan', areaId: 'kerja'));
      await pumpTasks(tester, h, location: '/tasks/areas', routes: taskRoutes);
      expect(find.text('Sen–Jum · 09.00–17.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('area-menu-kerja')));
      await settle(tester, 3);
      await tester.tap(find.text('Hapus').last);
      await settle(tester, 4);
      expect(
        find.textContaining('Semua tugas di area ini ikut terhapus'),
        findsOneWidget,
      );
      await tester.tap(find.text('HAPUS AREA'));
      await settle(tester, 6);
      expect(h.areas.s.items.containsKey('kerja'), isFalse);
      expect(h.tasks.s.items, isEmpty);
      await settle(tester, 30);
    });
  });
}

class _SignedOut extends SessionController {
  @override
  SessionState build() => const SignedOut();
}
