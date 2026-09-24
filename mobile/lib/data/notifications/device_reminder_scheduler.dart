import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/reminder.dart';
import 'notification_gateway.dart';
import 'reminder_codec.dart';

/// Permission state of local notifications on this device.
enum NotificationPermissionStatus {
  granted,
  denied,

  /// Platform without local notifications (tests, desktop, web).
  unsupported,
}

/// [ReminderScheduler] plus the device controls the settings UI needs.
abstract interface class DeviceReminderScheduler implements ReminderScheduler {
  /// Current permission, without prompting.
  Future<NotificationPermissionStatus> permissionStatus();

  /// Android: whether exact alarms may be used (always true elsewhere).
  Future<bool> canScheduleExact();

  /// Android 14+: sends the user to "Alarms & reminders". Returns the new state.
  Future<bool> requestExactAlarms();

  /// Opens the OS notification settings for the app (e.g. after a denial).
  Future<void> openSystemSettings();

  /// Use exact alarms when permitted ("precise reminders"). Takes effect on the
  /// next [ReminderScheduler.replaceAll].
  bool get preferExact;
  set preferExact(bool value);
}

/// Schedules task reminders through a [NotificationGateway].
///
/// * Initialises the plugin once, lazily (first call or first `openedRoutes` listener).
/// * [replaceAll] diffs the desired set against the OS's pending notifications:
///   unchanged ones are left alone, stale ones cancelled, new/changed ones
///   (re)scheduled. Only notifications carrying our payload are touched.
/// * Calls are serialised, so overlapping `replaceAll`/`cancelAll` never interleave.
/// * Exact alarms are used only when [preferExact] and permitted; a platform
///   refusal falls back to an inexact alarm.
class LocalReminderScheduler implements DeviceReminderScheduler {
  LocalReminderScheduler(
    this._gateway, {
    DateTime Function()? now,
    this.maxScheduled = 60,
  }) : _now = now ?? DateTime.now;

  final NotificationGateway _gateway;
  final DateTime Function() _now;

  /// OS limits (iOS keeps 64 pending; Samsung caps alarms) — docs/tasks.md says 60.
  final int maxScheduled;

  /// Reminders due sooner than this are skipped (the plugin rejects past dates).
  static const minLeadTime = Duration(seconds: 5);

  @override
  bool preferExact = false;

  Future<void>? _init;
  Future<void> _queue = Future.value();
  final _taps = StreamController<String>.broadcast();
  String? _launchRoute;

  Future<void> _ensureInit() => _init ??= _doInit();

  Future<void> _doInit() async {
    await _gateway.initialize(_onTap);
    try {
      _launchRoute = ReminderPayload.tryDecode(
        await _gateway.launchPayload(),
      )?.route;
    } catch (e) {
      debugPrint('Reminder launch details failed: $e');
    }
  }

  void _onTap(String? payload) {
    final route = ReminderPayload.tryDecode(payload)?.route;
    if (route != null && !_taps.isClosed) _taps.add(route);
  }

  /// Runs [op] after every previously queued op (errors don't break the chain).
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) async {
      await _ensureInit();
      return op();
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Emits the launch route (app opened from a notification) to the first
  /// listener, then every tap while the app runs.
  @override
  Stream<String> get openedRoutes => Stream.multi((c) {
    final sub = _taps.stream.listen(c.add);
    _ensureInit().then((_) {
      final r = _launchRoute;
      _launchRoute = null;
      if (r != null) c.add(r);
    }, onError: (Object e) => debugPrint('Reminder init failed: $e'));
    c.onCancel = sub.cancel;
  });

  @override
  Future<bool> ensurePermission() => _serial(_gateway.requestPermission);

  @override
  Future<NotificationPermissionStatus> permissionStatus() => _serial(() async {
    return switch (await _gateway.areEnabled()) {
      true => NotificationPermissionStatus.granted,
      false => NotificationPermissionStatus.denied,
      null => NotificationPermissionStatus.unsupported,
    };
  });

  @override
  Future<bool> canScheduleExact() => _serial(_gateway.canScheduleExact);

  @override
  Future<bool> requestExactAlarms() => _serial(_gateway.requestExactAlarms);

  @override
  Future<void> openSystemSettings() => _serial(_gateway.openSettings);

  @override
  Future<void> cancelAll() => _serial(_gateway.cancelAll);

  @override
  Future<void> replaceAll(List<Reminder> reminders) =>
      _serial(() => _replaceAll(reminders));

  Future<void> _replaceAll(List<Reminder> reminders) async {
    final cutoff = _now().add(minLeadTime);
    final seen = <String>{};
    final desired =
        reminders
            .where((r) => r.fireAt.isAfter(cutoff) && seen.add(r.key))
            .toList()
          ..sort((a, b) {
            final c = a.fireAt.compareTo(b.fireAt);
            return c != 0 ? c : a.key.compareTo(b.key);
          });
    if (desired.length > maxScheduled) desired.length = maxScheduled;

    final ids = assignReminderIds(desired.map((r) => r.key));
    final exact = preferExact && await _gateway.canScheduleExact();
    final requests = [
      for (final r in desired) _request(r, ids[r.key]!, exact: exact),
    ];

    List<PendingNotification>? pending;
    try {
      pending = await _gateway.pending();
    } catch (e) {
      debugPrint('Reading pending reminders failed, rescheduling all: $e');
    }

    if (pending == null) {
      await _gateway.cancelAll();
    } else {
      final ours = {
        for (final p in pending)
          if (ReminderPayload.tryDecode(p.payload) != null) p.id: p,
      };
      final wanted = {for (final r in requests) r.id};
      for (final id in ours.keys) {
        if (!wanted.contains(id)) await _gateway.cancel(id);
      }
      requests.removeWhere((r) {
        final p = ours[r.id];
        return p != null &&
            p.title == r.title &&
            p.body == r.body &&
            p.payload == r.payload;
      });
    }

    for (final r in requests) {
      await _schedule(r);
    }
  }

  NotificationRequest _request(Reminder r, int id, {required bool exact}) =>
      NotificationRequest(
        id: id,
        title: r.title,
        body: r.body,
        fireAt: r.fireAt,
        exact: exact,
        payload: ReminderPayload(
          key: r.key,
          route: r.route,
          fireAt: r.fireAt.toIso8601String(),
          exact: exact,
          timeZone: _gateway.timeZone,
        ).encode(),
      );

  Future<void> _schedule(NotificationRequest r) async {
    try {
      await _gateway.schedule(r);
    } catch (e) {
      if (!r.exact) {
        debugPrint('Scheduling reminder ${r.id} failed: $e');
        return;
      }
      // Exact alarm permission revoked between check and schedule: go inexact.
      final p = ReminderPayload.tryDecode(r.payload)!;
      final fallback = NotificationRequest(
        id: r.id,
        title: r.title,
        body: r.body,
        fireAt: r.fireAt,
        exact: false,
        payload: ReminderPayload(
          key: p.key,
          route: p.route,
          fireAt: p.fireAt,
          exact: false,
          timeZone: p.timeZone,
        ).encode(),
      );
      try {
        await _gateway.schedule(fallback);
      } catch (e) {
        debugPrint('Scheduling reminder ${r.id} failed: $e');
      }
    }
  }

  /// Stops tap delivery (tests / provider disposal).
  Future<void> dispose() => _taps.close();
}

/// Does nothing: platforms without local notifications, and tests.
class NoopReminderScheduler implements DeviceReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<String> get openedRoutes => const Stream.empty();

  @override
  Future<NotificationPermissionStatus> permissionStatus() async =>
      NotificationPermissionStatus.unsupported;

  @override
  Future<bool> canScheduleExact() async => false;

  @override
  Future<bool> requestExactAlarms() async => false;

  @override
  Future<void> openSystemSettings() async {}

  @override
  bool get preferExact => false;

  @override
  set preferExact(bool value) {}
}
