import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/notifications/notifications.dart';
import '../../../domain/entities/reminder.dart';
import 'notification_providers.dart';

enum ReminderSyncStatus {
  /// Settings still loading.
  idle,

  /// Signed out or notifications turned off: everything cancelled.
  off,

  /// Active, waiting for (debounced) reminders.
  pending,

  /// Last `replaceAll` succeeded.
  scheduled,

  /// Last `replaceAll` failed (logged; retried on the next change).
  error,
}

/// Keeps the OS schedule in sync with [remindersSourceProvider].
///
/// * signed in + enabled: every emission → debounced `replaceAll(latest)`;
/// * sign-out or master switch off: pending debounce dropped, `cancelAll()`;
/// * "precise reminders" toggled: reschedules the last set in the new mode.
///
/// Not auto-disposed: activate it once from the app shell,
/// `ref.watch(reminderSyncControllerProvider);` (or `ref.read` at startup).
class ReminderSyncController extends Notifier<ReminderSyncStatus> {
  Timer? _debounce;
  ProviderSubscription<AsyncValue<List<Reminder>>>? _source;
  List<Reminder>? _latest;

  /// Null until the first evaluation, so a stale schedule from a previous run is
  /// cancelled even when the app starts signed out / disabled.
  bool? _on;
  bool? _precise;

  DeviceReminderScheduler get _scheduler => ref.read(reminderSchedulerProvider);

  @override
  ReminderSyncStatus build() {
    ref.watch(reminderSchedulerProvider);
    _on = null;
    _precise = null;
    ref.listen(reminderSessionActiveProvider, (_, _) => _evaluate());
    ref.listen(notificationSettingsProvider, (_, _) => _evaluate());
    ref.onDispose(() {
      _debounce?.cancel();
      _source?.close();
      _source = null;
    });
    Future.microtask(_evaluate);
    return ReminderSyncStatus.idle;
  }

  void _evaluate() {
    if (!ref.mounted) return;
    final settings = ref.read(notificationSettingsProvider).value;
    if (settings == null) return; // loading; re-evaluated when it resolves
    final on = settings.enabled && ref.read(reminderSessionActiveProvider);

    if (!on) {
      _debounce?.cancel();
      _source?.close();
      _source = null;
      _latest = null;
      if (_on != false) {
        _on = false;
        state = ReminderSyncStatus.off;
        unawaited(_run(_scheduler.cancelAll, ReminderSyncStatus.off));
      }
      return;
    }

    final preciseChanged =
        _precise != null && _precise != settings.preciseReminders;
    _precise = settings.preciseReminders;
    _scheduler.preferExact = settings.preciseReminders;

    if (_on != true) {
      _on = true;
      state = ReminderSyncStatus.pending;
    }
    _source ??= ref.listen<AsyncValue<List<Reminder>>>(
      remindersSourceProvider,
      (_, next) => _onReminders(next),
      fireImmediately: true,
    );
    if (preciseChanged && _latest != null) _schedule();
  }

  void _onReminders(AsyncValue<List<Reminder>> next) {
    if (next case AsyncData(:final value)) {
      _latest = value;
      _schedule();
    } else if (next case AsyncError(:final error)) {
      debugPrint('Reminder source failed: $error');
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(ref.read(reminderSyncDebounceProvider), _flush);
  }

  void _flush() {
    final reminders = _latest;
    if (!ref.mounted || _on != true || reminders == null) return;
    unawaited(
      _run(
        () => _scheduler.replaceAll(reminders),
        ReminderSyncStatus.scheduled,
      ),
    );
  }

  Future<void> _run(Future<void> Function() op, ReminderSyncStatus ok) async {
    try {
      await op();
      // Ignore results that were overtaken by an on/off switch meanwhile.
      final stillCurrent = ok == ReminderSyncStatus.off
          ? _on == false
          : _on == true;
      if (ref.mounted && stillCurrent) state = ok;
    } catch (e) {
      debugPrint('Reminder sync failed: $e');
      if (ref.mounted) state = ReminderSyncStatus.error;
    }
  }

  /// Reschedules now (skips the debounce), e.g. after the app resumes.
  void syncNow() {
    _debounce?.cancel();
    _flush();
  }
}

final reminderSyncControllerProvider =
    NotifierProvider<ReminderSyncController, ReminderSyncStatus>(
      ReminderSyncController.new,
    );
