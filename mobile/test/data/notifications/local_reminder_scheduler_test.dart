import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/notifications/notifications.dart';
import 'package:ghina/domain/entities/reminder.dart';

import 'fake_notification_gateway.dart';

void main() {
  final now = DateTime(2026, 9, 24, 8);
  late FakeNotificationGateway gw;
  late LocalReminderScheduler scheduler;

  Reminder rem(String key, {int minutes = 60, String title = 'T'}) => Reminder(
    key: key,
    title: '[KERJA-FIRE] $title',
    body: '09:00 · Kerja',
    fireAt: now.add(Duration(minutes: minutes)),
    route: '/tasks/$key',
  );

  int id(String key) => reminderNotificationId(key);

  setUp(() {
    gw = FakeNotificationGateway();
    scheduler = LocalReminderScheduler(gw, now: () => now);
  });

  tearDown(() => scheduler.dispose());

  test('schedules new reminders once, initialises once', () async {
    await scheduler.replaceAll([rem('a'), rem('b')]);
    expect(gw.scheduled.keys, unorderedEquals([id('a'), id('b')]));
    final r = gw.scheduled[id('a')]!;
    expect(r.title, '[KERJA-FIRE] T');
    expect(r.fireAt, now.add(const Duration(hours: 1)));
    expect(r.exact, isFalse);
    expect(ReminderPayload.tryDecode(r.payload)!.route, '/tasks/a');

    gw.log.clear();
    await scheduler.replaceAll([rem('a'), rem('b')]);
    expect(gw.log, isEmpty, reason: 'unchanged set → no platform calls');
    expect(gw.initCount, 1);
  });

  test('cancels stale, reschedules changed, keeps unchanged', () async {
    await scheduler.replaceAll([rem('a'), rem('b'), rem('c')]);
    gw.log.clear();

    await scheduler.replaceAll([
      rem('a'), // unchanged
      rem('b', minutes: 30), // moved
      rem('d'), // new
    ]); // c removed

    expect(
      gw.log,
      unorderedEquals([
        'cancel ${id('c')}',
        'schedule ${id('b')}',
        'schedule ${id('d')}',
      ]),
    );
    expect(gw.scheduled[id('b')]!.fireAt, now.add(const Duration(minutes: 30)));
  });

  test('title change reschedules', () async {
    await scheduler.replaceAll([rem('a')]);
    gw.log.clear();
    await scheduler.replaceAll([rem('a', title: 'renamed')]);
    expect(gw.log, ['schedule ${id('a')}']);
  });

  test('skips past/imminent reminders, dedupes keys', () async {
    await scheduler.replaceAll([
      rem('past', minutes: -5),
      Reminder(
        key: 'now',
        title: 't',
        body: 'b',
        fireAt: now.add(const Duration(seconds: 2)),
        route: '/',
      ),
      rem('a', minutes: 10),
      rem('a', minutes: 20),
    ]);
    expect(gw.scheduled.keys, [id('a')]);
    expect(gw.scheduled[id('a')]!.fireAt, now.add(const Duration(minutes: 10)));
  });

  test('caps to the soonest maxScheduled', () async {
    scheduler = LocalReminderScheduler(gw, now: () => now, maxScheduled: 3);
    await scheduler.replaceAll([
      for (var i = 5; i >= 1; i--) rem('k$i', minutes: i * 10),
    ]);
    expect(gw.scheduled.keys, unorderedEquals([id('k1'), id('k2'), id('k3')]));
  });

  test('never touches foreign notifications, cancels our stale ones', () async {
    gw.foreign[7] = const PendingNotification(id: 7, payload: 'other');
    await scheduler.replaceAll([rem('a')]);
    await scheduler.replaceAll([]);
    expect(gw.log, ['schedule ${id('a')}', 'cancel ${id('a')}']);
    expect(gw.foreign.keys, [7]);
  });

  test('colliding keys get distinct ids', () async {
    const a = 'task-130386', b = 'task-626259';
    await scheduler.replaceAll([rem(a), rem(b)]);
    expect(gw.scheduled.length, 2);
  });

  test(
    'falls back to cancelAll + schedule when pending is unreadable',
    () async {
      await scheduler.replaceAll([rem('a')]);
      gw.failPending = true;
      gw.log.clear();
      await scheduler.replaceAll([rem('b')]);
      expect(gw.log, ['cancelAll', 'schedule ${id('b')}']);
    },
  );

  group('exact alarms', () {
    test('used only when preferred and permitted', () async {
      scheduler.preferExact = true;
      gw.exactAllowed = false;
      await scheduler.replaceAll([rem('a')]);
      expect(gw.scheduled[id('a')]!.exact, isFalse);

      gw.exactAllowed = true;
      await scheduler.replaceAll([rem('a')]);
      expect(
        gw.scheduled[id('a')]!.exact,
        isTrue,
        reason: 'mode change → reschedule',
      );
    });

    test('falls back to inexact when the platform refuses', () async {
      scheduler.preferExact = true;
      gw.rejectExact = true;
      await scheduler.replaceAll([rem('a')]);
      final r = gw.scheduled[id('a')]!;
      expect(r.exact, isFalse);
      expect(ReminderPayload.tryDecode(r.payload)!.exact, isFalse);
    });
  });

  test('time zone change re-arms everything', () async {
    await scheduler.replaceAll([rem('a')]);
    gw.timeZone = 'Asia/Makassar';
    gw.log.clear();
    await scheduler.replaceAll([rem('a')]);
    expect(gw.log, ['schedule ${id('a')}']);
  });

  test('cancelAll', () async {
    await scheduler.replaceAll([rem('a')]);
    await scheduler.cancelAll();
    expect(gw.scheduled, isEmpty);
  });

  test('serialises overlapping calls in order', () async {
    final f1 = scheduler.replaceAll([rem('a')]);
    final f2 = scheduler.cancelAll();
    final f3 = scheduler.replaceAll([rem('b')]);
    await Future.wait([f1, f2, f3]);
    expect(gw.log, ['schedule ${id('a')}', 'cancelAll', 'schedule ${id('b')}']);
  });

  group('openedRoutes', () {
    test(
      'emits launch route once, then taps; ignores foreign payloads',
      () async {
        gw.launch = const ReminderPayload(
          key: 'a',
          route: '/tasks/a',
          fireAt: 'x',
          exact: false,
        ).encode();

        final got = <String>[];
        final sub = scheduler.openedRoutes.listen(got.add);
        await pumpEventQueue();
        gw.tap('not ours');
        gw.tap(
          const ReminderPayload(
            key: 'b',
            route: '/tasks/b',
            fireAt: 'x',
            exact: false,
          ).encode(),
        );
        await pumpEventQueue();
        expect(got, ['/tasks/a', '/tasks/b']);

        final got2 = <String>[];
        final sub2 = scheduler.openedRoutes.listen(got2.add);
        await pumpEventQueue();
        expect(got2, isEmpty, reason: 'launch route is delivered only once');
        await sub.cancel();
        await sub2.cancel();
      },
    );
  });

  test('permission status + request', () async {
    gw.enabled = false;
    expect(
      await scheduler.permissionStatus(),
      NotificationPermissionStatus.denied,
    );
    expect(await scheduler.ensurePermission(), isTrue);
    expect(
      await scheduler.permissionStatus(),
      NotificationPermissionStatus.granted,
    );
    gw.enabled = null;
    expect(
      await scheduler.permissionStatus(),
      NotificationPermissionStatus.unsupported,
    );
  });

  test('NoopReminderScheduler does nothing', () async {
    const s = NoopReminderScheduler();
    await s.replaceAll([rem('a')]);
    await s.cancelAll();
    expect(await s.ensurePermission(), isFalse);
    expect(await s.openedRoutes.isEmpty, isTrue);
  });
}
