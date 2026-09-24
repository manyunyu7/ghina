/// A local notification the app wants scheduled (docs/tasks.md → Notifications).
///
/// Produced by the tasks use cases, consumed by [ReminderScheduler]. Pure data so the
/// domain can compute reminders without knowing the notification plugin.
class Reminder {
  const Reminder({
    required this.key,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.route,
  });

  /// Stable identity (the task id) so rescheduling replaces instead of duplicating.
  final String key;

  /// e.g. `[KERJA-FIRE] Kirim revisi client A`.
  final String title;
  final String body;

  /// Local wall-clock time to fire.
  final DateTime fireAt;

  /// App route opened when the notification is tapped, e.g. `/tasks/<id>`.
  final String route;

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.key == key &&
      other.title == title &&
      other.body == body &&
      other.fireAt == fireAt &&
      other.route == route;

  @override
  int get hashCode => Object.hash(key, title, body, fireAt, route);
}

/// Schedules the full desired set of reminders, replacing whatever was scheduled before.
/// Implemented in `data/` with the platform notification plugin.
abstract interface class ReminderScheduler {
  /// Asks the OS for notification permission if needed. Returns whether it is granted.
  Future<bool> ensurePermission();

  /// Replaces all scheduled task reminders with [reminders] (already capped/sorted).
  Future<void> replaceAll(List<Reminder> reminders);

  /// Cancels every scheduled reminder (sign-out, notifications turned off).
  Future<void> cancelAll();

  /// Routes of notifications tapped while the app was closed/backgrounded.
  Stream<String> get openedRoutes;
}
