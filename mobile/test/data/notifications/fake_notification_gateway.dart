import 'package:ghina/data/notifications/notifications.dart';

/// In-memory [NotificationGateway] that records every call.
class FakeNotificationGateway implements NotificationGateway {
  final Map<int, NotificationRequest> scheduled = {};
  final List<String> log = [];
  void Function(String? payload)? onTap;
  String? launch;
  int initCount = 0;
  bool? enabled = true;
  bool exactAllowed = true;
  bool permissionResult = true;

  @override
  String timeZone = 'Asia/Jakarta';

  /// Throw on `schedule` for exact requests (exact alarm permission revoked).
  bool rejectExact = false;

  /// Throw on `pending()` (platform can't list).
  bool failPending = false;

  /// Pending notifications that are not ours (another feature).
  final Map<int, PendingNotification> foreign = {};

  void tap(String? payload) => onTap?.call(payload);

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    initCount++;
    this.onTap = onTap;
  }

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<List<PendingNotification>> pending() async {
    if (failPending) throw StateError('no pending api');
    return [
      ...foreign.values,
      for (final r in scheduled.values)
        PendingNotification(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: r.payload,
        ),
    ];
  }

  @override
  Future<void> schedule(NotificationRequest r) async {
    if (r.exact && rejectExact) throw StateError('exact alarms not permitted');
    log.add('schedule ${r.id}');
    scheduled[r.id] = r;
  }

  @override
  Future<void> cancel(int id) async {
    log.add('cancel $id');
    scheduled.remove(id);
    foreign.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    log.add('cancelAll');
    scheduled.clear();
    foreign.clear();
  }

  @override
  Future<bool?> areEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async {
    enabled = permissionResult;
    return permissionResult;
  }

  @override
  Future<bool> canScheduleExact() async => exactAllowed;

  @override
  Future<bool> requestExactAlarms() async => exactAllowed = true;

  @override
  Future<void> openSettings() async => log.add('openSettings');
}
