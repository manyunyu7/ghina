# Local notifications (task reminders)

Implements `ReminderScheduler` (`lib/domain/entities/reminder.dart`) on top of
`flutter_local_notifications` + `timezone` + `flutter_timezone`. Spec: `docs/tasks.md` → Notifications.

| File | What |
|---|---|
| `device_reminder_scheduler.dart` | `LocalReminderScheduler` (diffing, serialised, lazy init) + `NoopReminderScheduler`; `DeviceReminderScheduler` adds permission / exact-alarm controls |
| `flutter_notification_gateway.dart` | The only file that talks to the plugin: tz setup, channel, `zonedSchedule`, permissions |
| `reminder_codec.dart` | Stable ids (FNV-1a → 31 bit, linear probing on collision) + JSON payload |
| `notification_settings_store.dart` | `NotificationSettings` (on/off, default remindBefore 0/10/30/60, precise) in shared_preferences |
| `notifications.dart` | Barrel + `createDeviceReminderScheduler()` (no-op off Android/iOS and under `flutter test`) |

State lives in `lib/presentation/state/notifications/`.

## How `replaceAll` works

1. Drop reminders due within 5 s or in the past, dedupe by key, sort by `fireAt`, cap at 60.
2. Ids: `assignReminderIds(keys)`, so the same task always gets the same id.
3. Read the OS's pending notifications and keep only ours (payload `{"kind":"task_reminder",…}`).
   Cancel ours that aren't wanted. (Re)schedule new ones, and ones whose title, body or payload
   changed. The payload holds route, fireAt and exact-mode, so any of those changing counts as a change.
   Leave unchanged ones alone. If pending can't be read, `cancelAll` and schedule everything.
4. Every call goes through one queue, so a `replaceAll` and a `cancelAll` never run at the same time.

## Wiring (still to do)

```dart
// 1. DI: give the sync controller the reminders stream (data agent / di/).
remindersSourceProvider.overrideWith((ref) => /* Stream<List<Reminder>> from tasks use case */),

// 2. App shell: start syncing once (not auto-disposed).
ref.watch(reminderSyncControllerProvider);

// 3. Router: navigate on tap (including cold start from a notification).
MaterialApp.router(
  builder: (context, child) => NotificationRouteListener(
    onRoute: (route) => router.push(route),   // e.g. /tasks/<id>
    child: child!,
  ),
)
```

- `ReminderSyncController` debounces updates by 750 ms (`reminderSyncDebounceProvider`) and then
  calls `replaceAll(latest)`. It calls `cancelAll()` when the user signs out
  (`reminderSessionActiveProvider`, derived from `currentUserProvider`) or turns reminders off.
  Toggling "precise" reschedules the current set. `syncNow()` skips the debounce.
- Settings UI: `notificationSettingsProvider` (`setEnabled`, `setDefaultRemindBefore`,
  `setPreciseReminders`). New tasks with a time should pre-fill `remindBefore` from
  `defaultRemindBefore`.
- Permission UI: `notificationPermissionProvider` gives `status` and `exactAlarms`. Its methods are
  `request()`, `requestExactAlarms()`, `openSystemSettings()` and `refresh()`. Call `refresh()` on
  app resume. Ask for permission in context (for example the first time a reminder is set, or from
  settings), not at startup. The sync controller never prompts.
- Tests: override `reminderSchedulerProvider` with a fake, or use
  `LocalReminderScheduler(FakeNotificationGateway())` (see `test/data/notifications/`).

## Android

- Manifest: `POST_NOTIFICATIONS` (asked at runtime on 13+), `RECEIVE_BOOT_COMPLETED` + the plugin's
  `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` (re-arms alarms after
  reboot and app update), `SCHEDULE_EXACT_ALARM`, `VIBRATE`. `USE_EXACT_ALARM` is **not**
  declared: Play only allows it for alarm-clock and calendar apps.
- By default reminders use `inexactAllowWhileIdle`: no special permission, but Doze can delay them by
  several minutes. With **precise reminders** on and exact alarms allowed, they use
  `exactAllowWhileIdle`. Android 12–13 grants `SCHEDULE_EXACT_ALARM` automatically. On 14+ the
  user must allow "Alarms & reminders" (`requestExactAlarms()` opens that screen). If it is
  missing or revoked, reminders fall back to inexact.
- Channel `task_reminders` / "Pengingat tugas", high importance. After the first launch, the
  user controls its sound and importance in system settings.
- Small icon: `res/drawable-*/ic_stat_ghina.png`, a white tree silhouette. `res/raw/keep.xml`
  keeps R8 from removing it. Core library desugaring is enabled in `app/build.gradle.kts`, as the
  plugin requires.
- **Battery optimisation / OEM app killing** (Infinix, Tecno, itel (Transsion/HiOS/XOS), Xiaomi,
  Oppo, Vivo, Huawei): these phones may drop alarms or block the boot receiver when the app is
  swiped away. On these phones users may need to:
  allow **Auto-start** (Phone Master → App auto-start / "Autostart"), set battery to
  **Unrestricted / No restrictions** (Settings → Battery → App battery saver, or
  Apps → Ghina → Battery), turn off "Power Marathon" / "Ultra power saving" for the app, and lock
  Ghina in Recents. See https://dontkillmyapp.com. Opening the app reschedules everything, because
  the sync controller runs `replaceAll` on start.

## iOS

- `AppDelegate.swift` sets `UNUserNotificationCenter.current().delegate`, so taps and foreground
  banners reach the plugin. No Info.plist keys or background modes are needed for local notifications.
- The permission prompt is **not** shown at init (`request*Permission: false`).
  `ensurePermission()` / `request()` shows it once. After a denial, send the user to
  `openSystemSettings()`.
- iOS keeps at most 64 pending notifications. We cap at 60.
- Times are wall-clock in the device zone (`flutter_timezone`). If the zone can't be read, we fall
  back to a zone with the same offset (WIB/WITA/WIT preferred). The zone is read once per app run.
  It is also stored in the payload, so after a zone change (travelling between WIB, WITA and WIT)
  the next start re-arms every reminder at the new local time.
