import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/notifications/notifications.dart';
import 'package:ghina/domain/entities/reminder.dart';
import 'package:ghina/presentation/state/notifications/notification_providers.dart';
import 'package:ghina/presentation/state/notifications/reminder_sync_controller.dart';

class RecordingScheduler implements DeviceReminderScheduler {
  final calls = <String>[];
  final replaced = <List<Reminder>>[];

  @override
  bool preferExact = false;

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    calls.add('replaceAll(${reminders.map((r) => r.key).join(',')})');
    replaced.add(reminders);
  }

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Stream<String> get openedRoutes => const Stream.empty();

  @override
  Future<NotificationPermissionStatus> permissionStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<bool> requestExactAlarms() async => true;

  @override
  Future<void> openSystemSettings() async {}
}

void main() {
  const debounce = Duration(milliseconds: 30);
  Future<void> settle() => Future<void>.delayed(debounce * 3);

  late RecordingScheduler scheduler;
  late StreamController<List<Reminder>> source;
  late InMemoryNotificationSettingsStore store;
  late ProviderContainer container;
  late bool signedIn;

  Reminder rem(String key) => Reminder(
    key: key,
    title: 't',
    body: 'b',
    fireAt: DateTime(2030, 1, 1),
    route: '/tasks/$key',
  );

  ProviderContainer make() {
    final c = ProviderContainer(
      overrides: [
        reminderSchedulerProvider.overrideWithValue(scheduler),
        remindersSourceProvider.overrideWith((ref) => source.stream),
        reminderSessionActiveProvider.overrideWith((ref) => signedIn),
        reminderSyncDebounceProvider.overrideWithValue(debounce),
        notificationSettingsStoreProvider.overrideWithValue(store),
      ],
    );
    c.listen(reminderSyncControllerProvider, (_, _) {});
    return c;
  }

  setUp(() {
    scheduler = RecordingScheduler();
    source = StreamController<List<Reminder>>.broadcast();
    store = InMemoryNotificationSettingsStore();
    signedIn = true;
    container = make();
  });

  tearDown(() async {
    container.dispose();
    await source.close();
  });

  test('debounces bursts into one replaceAll with the latest set', () async {
    await settle();
    source.add([rem('a')]);
    source.add([rem('a'), rem('b')]);
    await Future<void>.delayed(debounce ~/ 3);
    source.add([rem('c')]);
    expect(scheduler.calls, isEmpty, reason: 'still debouncing');
    await settle();
    expect(scheduler.calls, ['replaceAll(c)']);
    expect(
      container.read(reminderSyncControllerProvider),
      ReminderSyncStatus.scheduled,
    );
  });

  test(
    'master switch off cancels and drops pending debounce; on resumes',
    () async {
      await settle();
      source.add([rem('a')]);
      await container
          .read(notificationSettingsProvider.notifier)
          .setEnabled(false);
      await settle();
      expect(scheduler.calls, ['cancelAll']);
      expect(store.value.enabled, isFalse, reason: 'persisted');
      expect(
        container.read(reminderSyncControllerProvider),
        ReminderSyncStatus.off,
      );

      source.add([rem('b')]);
      await settle();
      expect(scheduler.calls, ['cancelAll'], reason: 'ignored while off');

      await container
          .read(notificationSettingsProvider.notifier)
          .setEnabled(true);
      await settle();
      // Re-enabling schedules the current set right away (no new emission needed).
      expect(scheduler.calls, ['cancelAll', 'replaceAll(b)']);
      source.add([rem('c')]);
      await settle();
      expect(scheduler.calls.last, 'replaceAll(c)');
    },
  );

  test('sign-out cancels everything', () async {
    await settle();
    source.add([rem('a')]);
    await settle();
    signedIn = false;
    container.invalidate(reminderSessionActiveProvider);
    await settle();
    expect(scheduler.calls, ['replaceAll(a)', 'cancelAll']);
  });

  test('starting signed out cancels stale reminders once', () async {
    container.dispose();
    signedIn = false;
    container = make();
    await settle();
    source.add([rem('a')]);
    await settle();
    expect(scheduler.calls, ['cancelAll']);
  });

  test('toggling precise reminders reschedules the last set', () async {
    await settle();
    source.add([rem('a')]);
    await settle();
    await container
        .read(notificationSettingsProvider.notifier)
        .setPreciseReminders(true);
    await settle();
    expect(scheduler.preferExact, isTrue);
    expect(scheduler.calls, ['replaceAll(a)', 'replaceAll(a)']);
  });

  test('settings persist and validate remindBefore', () async {
    final n = container.read(notificationSettingsProvider.notifier);
    await container.read(notificationSettingsProvider.future);
    await n.setDefaultRemindBefore(30);
    expect(store.value.defaultRemindBefore, 30);
    expect(() => n.setDefaultRemindBefore(15), throwsArgumentError);
  });

  test('permission provider reflects the scheduler', () async {
    final p = await container.read(notificationPermissionProvider.future);
    expect(p.granted, isTrue);
    expect(p.exactAlarms, isTrue);
  });
}
