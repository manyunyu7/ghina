import 'package:shared_preferences/shared_preferences.dart';

/// User's reminder preferences (docs/tasks.md → Notifications → Settings).
class NotificationSettings {
  const NotificationSettings({
    this.enabled = true,
    this.defaultRemindBefore = 10,
    this.preciseReminders = false,
  });

  /// Allowed values for [defaultRemindBefore] (minutes).
  static const remindBeforeOptions = [0, 10, 30, 60];

  /// Master switch: off cancels every scheduled reminder.
  final bool enabled;

  /// Minutes before the due time, pre-filled for new tasks that have a time.
  final int defaultRemindBefore;

  /// Android: use exact alarms (needs "Alarms & reminders" permission on 14+).
  final bool preciseReminders;

  NotificationSettings copyWith({
    bool? enabled,
    int? defaultRemindBefore,
    bool? preciseReminders,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    defaultRemindBefore: defaultRemindBefore ?? this.defaultRemindBefore,
    preciseReminders: preciseReminders ?? this.preciseReminders,
  );

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.enabled == enabled &&
      other.defaultRemindBefore == defaultRemindBefore &&
      other.preciseReminders == preciseReminders;

  @override
  int get hashCode =>
      Object.hash(enabled, defaultRemindBefore, preciseReminders);
}

abstract interface class NotificationSettingsStore {
  Future<NotificationSettings> load();
  Future<void> save(NotificationSettings settings);
}

/// Device-local (not synced) — reminders are a per-device concern.
class SharedPrefsNotificationSettingsStore
    implements NotificationSettingsStore {
  SharedPrefsNotificationSettingsStore([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static const _enabled = 'notif.enabled';
  static const _remindBefore = 'notif.defaultRemindBefore';
  static const _precise = 'notif.precise';

  @override
  Future<NotificationSettings> load() async {
    final p = await _prefs;
    const d = NotificationSettings();
    final before = p.getInt(_remindBefore);
    return NotificationSettings(
      enabled: p.getBool(_enabled) ?? d.enabled,
      defaultRemindBefore:
          NotificationSettings.remindBeforeOptions.contains(before)
          ? before!
          : d.defaultRemindBefore,
      preciseReminders: p.getBool(_precise) ?? d.preciseReminders,
    );
  }

  @override
  Future<void> save(NotificationSettings s) async {
    final p = await _prefs;
    await p.setBool(_enabled, s.enabled);
    await p.setInt(_remindBefore, s.defaultRemindBefore);
    await p.setBool(_precise, s.preciseReminders);
  }
}

class InMemoryNotificationSettingsStore implements NotificationSettingsStore {
  InMemoryNotificationSettingsStore([
    this.value = const NotificationSettings(),
  ]);

  NotificationSettings value;

  @override
  Future<NotificationSettings> load() async => value;

  @override
  Future<void> save(NotificationSettings settings) async => value = settings;
}
