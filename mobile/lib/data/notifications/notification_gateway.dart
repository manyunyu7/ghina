/// Thin seam over the platform notification plugin so the scheduling logic in
/// [LocalReminderScheduler] can be unit-tested with a fake.
library;

/// A notification to schedule once at [fireAt].
class NotificationRequest {
  const NotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.payload,
    required this.exact,
  });

  final int id;
  final String title;
  final String body;

  /// Local wall-clock time (or a UTC instant when `isUtc`).
  final DateTime fireAt;
  final String payload;

  /// Android: exact alarm (`exactAllowWhileIdle`) vs inexact (`inexactAllowWhileIdle`).
  final bool exact;
}

/// A notification the OS still has pending.
class PendingNotification {
  const PendingNotification({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

abstract interface class NotificationGateway {
  /// Initialises the plugin + time zones. [onTap] receives the payload of a
  /// notification tapped while the app is running (foreground/background).
  Future<void> initialize(void Function(String? payload) onTap);

  /// IANA zone the wall-clock times are interpreted in (valid after [initialize]).
  String get timeZone;

  /// Payload of the notification that launched the app (cold start), if any.
  Future<String?> launchPayload();

  Future<List<PendingNotification>> pending();

  /// Schedules (or replaces, same id) a notification. Throws if the platform
  /// refuses (e.g. exact alarms not permitted).
  Future<void> schedule(NotificationRequest request);

  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// Whether notifications may be shown. Null = unknown/unsupported.
  Future<bool?> areEnabled();

  /// Shows the OS permission prompt if needed. Returns whether granted.
  Future<bool> requestPermission();

  /// Android 12+: whether exact alarms are allowed. Always true elsewhere.
  Future<bool> canScheduleExact();

  /// Android 14+: opens the "Alarms & reminders" settings page. Returns the new state.
  Future<bool> requestExactAlarms();

  /// Opens the app's notification settings page (best effort).
  Future<void> openSettings();
}
