import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/notifications/notification_providers.dart';
import '../task_format.dart';

/// Session flags so the permission explainer isn't shown over and over.
class _ReminderFlags {
  bool asked = false;
}

final _reminderFlagsProvider = Provider<_ReminderFlags>(
  (_) => _ReminderFlags(),
);

bool _isAndroid(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.android;

/// Asks for notification permission in context (the first time a reminder is set
/// this session). Explains first, then shows the OS prompt; if it stays denied,
/// shows how to turn it on in system settings. Returns whether reminders can
/// fire (true on platforms without a permission model).
Future<bool> ensureReminderPermission(
  BuildContext context,
  WidgetRef ref, {
  bool force = false,
}) async {
  final NotificationPermissionState perm;
  try {
    perm = await ref.read(notificationPermissionProvider.future);
  } catch (_) {
    return true;
  }
  if (perm.granted || perm.status.name == 'unsupported') return true;
  final flags = ref.read(_reminderFlagsProvider);
  if (flags.asked && !force) return false;
  flags.asked = true;
  if (!context.mounted) return false;

  final go = await showChunkyConfirm(
    context,
    title: 'Boleh Ghina ngingetin? 🔔',
    message:
        'Biar tugasmu nggak kelewat, Ghina perlu izin kirim notifikasi. '
        'Cuma buat pengingat tugas, kok.',
    confirmLabel: 'Izinkan',
    cancelLabel: 'Nanti saja',
    mood: MascotMood.waving,
  );
  if (!go || !context.mounted) return false;
  final notifier = ref.read(notificationPermissionProvider.notifier);
  final granted = await notifier.request();
  if (!context.mounted) return granted;
  if (granted) {
    if (_isAndroid(context)) await showBatteryTip(context);
    return true;
  }
  await showEnableInSettings(context, ref);
  return false;
}

/// "Notifikasi masih mati" + a button to the app's system settings.
Future<void> showEnableInSettings(BuildContext context, WidgetRef ref) =>
    showChunkyDialog<void>(
      context,
      builder: (c) => ChunkyDialog(
        title: 'Notifikasi masih mati',
        mood: MascotMood.thinking,
        message: _isAndroid(context)
            ? 'Buka Pengaturan → Aplikasi → Ghina → Notifikasi, lalu nyalakan '
                  '"Izinkan notifikasi".'
            : 'Buka Pengaturan → Notifikasi → Ghina, lalu nyalakan '
                  '"Izinkan Notifikasi".',
        actions: [
          ChunkyButton(
            label: 'Buka pengaturan',
            icon: Icons.settings_rounded,
            onPressed: () {
              Navigator.of(c).pop();
              ref
                  .read(notificationPermissionProvider.notifier)
                  .openSystemSettings();
            },
          ),
          ChunkyButton(
            label: 'Nanti saja',
            variant: ChunkyButtonVariant.ghost,
            color: GhinaColors.blue,
            onPressed: () => Navigator.of(c).pop(),
          ),
        ],
      ),
    );

/// Tips for phones that kill background alarms (Infinix/Tecno/itel, Xiaomi, …).
const batteryTipSteps = [
  'Izinkan Auto-start (Phone Master → App auto-start → Ghina).',
  'Set baterai ke "Tanpa batasan" (Pengaturan → Aplikasi → Ghina → Baterai).',
  'Matikan "Power Marathon" / "Ultra power saving" untuk Ghina.',
  'Kunci Ghina di layar Recents biar nggak ikut dibersihkan.',
];

/// One-time explainer shown right after reminders get permission on Android.
Future<void> showBatteryTip(BuildContext context) => showChunkyDialog<void>(
  context,
  builder: (c) => ChunkyDialog(
    title: 'Satu tips lagi 🔋',
    message:
        'Di HP Infinix, Tecno, itel, Xiaomi, Oppo atau Vivo, pengingat bisa '
        'telat kalau aplikasi ditutup paksa. Biar aman:',
    content: const BatteryTipList(),
    actions: [
      ChunkyButton(label: 'Siap!', onPressed: () => Navigator.of(c).pop()),
    ],
  ),
);

class BatteryTipList extends StatelessWidget {
  const BatteryTipList({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in batteryTipSteps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: GhinaType.bodyS.w(900).copyWith(color: g.textPrimary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The "Pengingat" settings sheet (Tugas tab overflow menu).
Future<void> showReminderSettingsSheet(BuildContext context) =>
    showChunkyBottomSheet<void>(
      context,
      title: 'Pengingat tugas',
      showClose: true,
      builder: (_) => const ReminderSettingsPanel(),
    );

class ReminderSettingsPanel extends ConsumerWidget {
  const ReminderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final settings = ref.watch(notificationSettingsProvider).value;
    final perm = ref.watch(notificationPermissionProvider).value;
    final ctrl = ref.read(notificationSettingsProvider.notifier);
    final android = _isAndroid(context);
    if (settings == null) return const SkeletonList(count: 3);
    final unsupported = perm?.status.name == 'unsupported';
    final granted = perm?.granted ?? false;

    Widget switchRow({
      required Key key,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) => Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text(title, style: GhinaType.h3.copyWith(color: g.textPrimary)),
        subtitle: Text(
          subtitle,
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switchRow(
          key: const ValueKey('reminders-enabled'),
          title: 'Pengingat aktif',
          subtitle: settings.enabled
              ? 'Ghina kirim notifikasi sebelum tugas jatuh tempo'
              : 'Semua pengingat dimatikan',
          value: settings.enabled,
          onChanged: (v) async {
            await ctrl.setEnabled(v);
            if (v && context.mounted) {
              await ensureReminderPermission(context, ref, force: true);
            }
          },
        ),
        const SizedBox(height: 8),
        const FieldLabel('Default untuk tugas baru'),
        ChunkyChoiceChips<int>(
          options: [
            for (final m in const [0, 10, 30, 60])
              ChunkyChoice(value: m, label: remindChip(m)),
          ],
          selected: {settings.defaultRemindBefore},
          onChanged: (s) => ctrl.setDefaultRemindBefore(s.first),
        ),
        if (android) ...[
          const SizedBox(height: 8),
          switchRow(
            key: const ValueKey('reminders-precise'),
            title: 'Pengingat presisi',
            subtitle: settings.preciseReminders
                ? (perm?.exactAlarms ?? false)
                      ? 'Tepat di menitnya'
                      : 'Butuh izin "Alarm & pengingat"'
                : 'Hemat baterai, bisa telat beberapa menit',
            value: settings.preciseReminders,
            onChanged: (v) async {
              await ctrl.setPreciseReminders(v);
              if (v && !(perm?.exactAlarms ?? false)) {
                await ref
                    .read(notificationPermissionProvider.notifier)
                    .requestExactAlarms();
              }
            },
          ),
        ],
        const SizedBox(height: 12),
        if (!unsupported)
          ChunkyCard(
            key: const ValueKey('reminders-permission'),
            tinted: granted ? GhinaColors.green : GhinaColors.orange,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  granted
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: granted
                      ? GhinaColors.green.base
                      : GhinaColors.orange.base,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    granted
                        ? 'Izin notifikasi aktif'
                        : 'Izin notifikasi belum ada',
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                ),
                if (!granted)
                  ChunkyButton(
                    label: 'Izinkan',
                    size: ChunkyButtonSize.small,
                    onPressed: () =>
                        ensureReminderPermission(context, ref, force: true),
                  ),
              ],
            ),
          ),
        if (android) ...[
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Pengingat suka telat? 🔋',
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
              subtitle: Text(
                'Tips untuk HP Infinix, Tecno, Xiaomi & lainnya',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              children: const [BatteryTipList()],
            ),
          ),
        ],
      ],
    );
  }
}
