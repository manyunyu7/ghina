/// Local task reminders: scheduler, settings, permission and the reminder source.
///
/// Wiring (see `lib/data/notifications/README.md`):
/// * override [remindersSourceProvider] with the tasks use case stream;
/// * activate `reminderSyncControllerProvider` once from the app shell;
/// * wrap the shell in `NotificationRouteListener` to navigate on taps.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/notifications/notifications.dart';
import '../../../domain/entities/reminder.dart';
import '../session_controller.dart';

/// The platform scheduler (no-op off Android/iOS and under `flutter test`).
/// Tests override it with a fake / `LocalReminderScheduler(fakeGateway)`.
final reminderSchedulerProvider = Provider<DeviceReminderScheduler>((ref) {
  final s = createDeviceReminderScheduler();
  if (s is LocalReminderScheduler) ref.onDispose(s.dispose);
  return s;
});

/// The full desired set of reminders (already capped/sorted by the tasks use case).
///
/// Seam: throws until overridden, e.g. in DI:
/// ```dart
/// remindersSourceProvider.overrideWith((ref) => ref.watch(watchTaskRemindersProvider)()),
/// ```
final remindersSourceProvider = StreamProvider<List<Reminder>>(
  (ref) => throw UnimplementedError(
    'remindersSourceProvider must be overridden (tasks reminders stream)',
  ),
);

/// Whether a user is signed in; reminders are cancelled when this turns false.
final reminderSessionActiveProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider) != null,
);

/// Delay that coalesces bursts of reminder updates (local edits + sync pulls).
final reminderSyncDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 750),
);

// --- settings ----------------------------------------------------------------

final notificationSettingsStoreProvider = Provider<NotificationSettingsStore>(
  (ref) => SharedPrefsNotificationSettingsStore(),
);

/// Persisted reminder settings (device-local).
///
/// ```dart
/// final s = ref.watch(notificationSettingsProvider).value;   // null while loading
/// ref.read(notificationSettingsProvider.notifier).setEnabled(false);
/// ```
class NotificationSettingsController
    extends AsyncNotifier<NotificationSettings> {
  @override
  Future<NotificationSettings> build() =>
      ref.watch(notificationSettingsStoreProvider).load();

  Future<void> _update(
    NotificationSettings Function(NotificationSettings) change,
  ) async {
    final current = state.value ?? await future;
    final next = change(current);
    if (next == current) return;
    state = AsyncData(next);
    await ref.read(notificationSettingsStoreProvider).save(next);
  }

  /// Master switch. Off cancels every scheduled reminder (via the sync controller).
  Future<void> setEnabled(bool enabled) =>
      _update((s) => s.copyWith(enabled: enabled));

  /// One of [NotificationSettings.remindBeforeOptions] (0/10/30/60 minutes).
  Future<void> setDefaultRemindBefore(int minutes) {
    if (!NotificationSettings.remindBeforeOptions.contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes', 'must be 0, 10, 30 or 60');
    }
    return _update((s) => s.copyWith(defaultRemindBefore: minutes));
  }

  /// Exact alarms (Android). Pair with
  /// `notificationPermissionProvider.notifier.requestExactAlarms()` when turning on;
  /// without the permission reminders silently stay inexact.
  Future<void> setPreciseReminders(bool precise) =>
      _update((s) => s.copyWith(preciseReminders: precise));
}

final notificationSettingsProvider =
    AsyncNotifierProvider<NotificationSettingsController, NotificationSettings>(
      NotificationSettingsController.new,
    );

// --- permission --------------------------------------------------------------

class NotificationPermissionState {
  const NotificationPermissionState({
    required this.status,
    required this.exactAlarms,
  });

  final NotificationPermissionStatus status;

  /// Android: exact alarms allowed ("Alarms & reminders"). True on iOS.
  final bool exactAlarms;

  bool get granted => status == NotificationPermissionStatus.granted;

  @override
  bool operator ==(Object other) =>
      other is NotificationPermissionState &&
      other.status == status &&
      other.exactAlarms == exactAlarms;

  @override
  int get hashCode => Object.hash(status, exactAlarms);
}

/// OS permission state. Call [refresh] when the app resumes (the user may have
/// changed it in system settings).
class NotificationPermissionController
    extends AsyncNotifier<NotificationPermissionState> {
  DeviceReminderScheduler get _scheduler => ref.read(reminderSchedulerProvider);

  @override
  Future<NotificationPermissionState> build() {
    ref.watch(reminderSchedulerProvider);
    return _read();
  }

  Future<NotificationPermissionState> _read() async =>
      NotificationPermissionState(
        status: await _scheduler.permissionStatus(),
        exactAlarms: await _scheduler.canScheduleExact(),
      );

  Future<void> refresh() async => state = AsyncData(await _read());

  /// Shows the OS prompt (Android 13+/iOS) if still undecided. Returns granted.
  /// Once denied permanently, send the user to [openSystemSettings] instead.
  Future<bool> request() async {
    final granted = await _scheduler.ensurePermission();
    await refresh();
    return granted;
  }

  /// Android 14+: opens "Alarms & reminders". Returns whether exact alarms are allowed.
  Future<bool> requestExactAlarms() async {
    final ok = await _scheduler.requestExactAlarms();
    await refresh();
    return ok;
  }

  Future<void> openSystemSettings() => _scheduler.openSystemSettings();
}

final notificationPermissionProvider =
    AsyncNotifierProvider<
      NotificationPermissionController,
      NotificationPermissionState
    >(NotificationPermissionController.new);

// --- taps ----------------------------------------------------------------------

/// Routes (e.g. `/tasks/<id>`) of tapped reminders, including the one that
/// launched the app. Prefer `NotificationRouteListener`; a raw stream (not a
/// StreamProvider) so tapping the same task twice navigates twice.
final notificationRoutesProvider = Provider<Stream<String>>(
  (ref) => ref.watch(reminderSchedulerProvider).openedRoutes,
);
