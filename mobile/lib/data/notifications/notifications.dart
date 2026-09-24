/// Local task reminders (see README.md in this folder).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'device_reminder_scheduler.dart';
import 'flutter_notification_gateway.dart';

export 'device_reminder_scheduler.dart';
export 'flutter_notification_gateway.dart' show FlutterNotificationGateway;
export 'notification_gateway.dart';
export 'notification_settings_store.dart';
export 'reminder_codec.dart';

/// The real scheduler on Android/iOS, a no-op everywhere else (including
/// `flutter test`, where `defaultTargetPlatform` pretends to be Android).
DeviceReminderScheduler createDeviceReminderScheduler() {
  final supported =
      !kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  return supported
      ? LocalReminderScheduler(FlutterNotificationGateway())
      : const NoopReminderScheduler();
}
