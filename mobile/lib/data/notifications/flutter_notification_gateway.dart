import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_gateway.dart';

/// [NotificationGateway] backed by `flutter_local_notifications` (Android + iOS).
class FlutterNotificationGateway implements NotificationGateway {
  FlutterNotificationGateway([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const channelId = 'task_reminders';
  static const channelName = 'Pengingat tugas';
  static const channelDescription =
      'Pengingat sebelum tenggat tugas yang punya jam.';

  /// `android/app/src/main/res/drawable-*/ic_stat_ghina.png` (kept by res/raw/keep.xml).
  static const smallIcon = 'ic_stat_ghina';
  static const _accent = Color(0xFF58CC02);

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    await _initTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(smallIcon),
        // Ask for permission explicitly (ensurePermission), not at init.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      ),
    );
  }

  Future<void> _initTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Unknown identifier / plugin failure: pick a zone with the device's
      // current offset so wall-clock times still line up.
      debugPrint('Reminder tz fallback: $e');
      tz.setLocalLocation(locationForOffset(DateTime.now().timeZoneOffset));
    }
  }

  /// A location with a fixed [offset] (Indonesian zones preferred).
  @visibleForTesting
  static tz.Location locationForOffset(Duration offset) {
    final minutes = offset.inMinutes;
    const indonesia = {
      420: 'Asia/Jakarta',
      480: 'Asia/Makassar',
      540: 'Asia/Jayapura',
    };
    final name =
        indonesia[minutes] ??
        (minutes % 60 == 0 && minutes != 0
            // Etc/GMT signs are inverted: UTC+7 is Etc/GMT-7.
            ? 'Etc/GMT${minutes > 0 ? '-' : '+'}${(minutes ~/ 60).abs()}'
            : 'UTC');
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.UTC;
    }
  }

  @override
  String get timeZone => tz.local.name;

  @override
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload;
  }

  @override
  Future<List<PendingNotification>> pending() async => [
    for (final p in await _plugin.pendingNotificationRequests())
      PendingNotification(
        id: p.id,
        title: p.title,
        body: p.body,
        payload: p.payload,
      ),
  ];

  @override
  Future<void> schedule(NotificationRequest r) => _plugin.zonedSchedule(
    id: r.id,
    title: r.title,
    body: r.body,
    payload: r.payload,
    scheduledDate: r.fireAt.isUtc
        ? tz.TZDateTime.from(r.fireAt, tz.local)
        : tz.TZDateTime(
            tz.local,
            r.fireAt.year,
            r.fireAt.month,
            r.fireAt.day,
            r.fireAt.hour,
            r.fireAt.minute,
            r.fireAt.second,
          ),
    androidScheduleMode: r.exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: smallIcon,
        color: _accent,
        styleInformation: BigTextStyleInformation(r.body),
      ),
      iOS: const DarwinNotificationDetails(threadIdentifier: channelId),
    ),
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<bool?> areEnabled() async {
    if (_android case final a?) return a.areNotificationsEnabled();
    if (_ios case final i?) return (await i.checkPermissions())?.isEnabled;
    return null;
  }

  @override
  Future<bool> requestPermission() async {
    if (_android case final a?) {
      return await a.requestNotificationsPermission() ??
          await a.areNotificationsEnabled() ??
          false;
    }
    if (_ios case final i?) {
      return await i.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  @override
  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? true;

  @override
  Future<bool> requestExactAlarms() async {
    final a = _android;
    if (a == null) return true;
    await a.requestExactAlarmsPermission();
    return await a.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> openSettings() async {
    try {
      await _plugin.openAppNotificationSettings();
    } catch (e) {
      debugPrint('openAppNotificationSettings failed: $e');
    }
  }
}
