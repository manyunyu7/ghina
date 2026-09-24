import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';

/// What the mic is for (changes the explanation copy).
enum MicPurpose { record, dictate }

/// Permissions UX before "Rekam suara" / "Dikte": explain → request (the
/// controllers ask the OS) → settings guidance when it's permanently denied.
/// Returns true when the caller may start (granted, or the OS prompt comes
/// next), false when the user backed out.
Future<bool> ensureMicReady(
  BuildContext context,
  WidgetRef ref,
  MicPurpose purpose,
) async {
  final perm = ref.read(microphonePermissionProvider);
  final status = await perm.status();
  if (!context.mounted) return false;
  switch (status) {
    case MicPermissionStatus.granted:
    case MicPermissionStatus.unsupported:
      return true;
    case MicPermissionStatus.permanentlyDenied:
      await showMicSettingsGuide(context, ref);
      return false;
    case MicPermissionStatus.denied:
      final ok = await showChunkyDialog<bool>(
        context,
        builder: (c) => ChunkyDialog(
          title: purpose == MicPurpose.record
              ? 'Izinkan mikrofon, ya'
              : 'Izinkan mikrofon untuk dikte',
          message: purpose == MicPurpose.record
              ? 'Ghina butuh mikrofon buat merekam suaramu. Rekaman disimpan '
                    'di HP dulu, lalu ikut tersinkron.'
              : 'Ghina butuh mikrofon buat mengubah ucapanmu jadi teks. '
                    'Pengenalan suara jalan di perangkat.',
          mood: MascotMood.waving,
          actions: [
            ChunkyButton(
              key: const ValueKey('mic-allow'),
              label: 'Izinkan',
              icon: Icons.mic_rounded,
              onPressed: () => Navigator.of(c).pop(true),
            ),
            ChunkyButton(
              label: 'Nanti saja',
              variant: ChunkyButtonVariant.ghost,
              onPressed: () => Navigator.of(c).pop(false),
            ),
          ],
        ),
      );
      return ok == true;
  }
}

/// "Buka Pengaturan" guidance after a permanent denial.
Future<void> showMicSettingsGuide(BuildContext context, WidgetRef ref) async {
  final open = await showChunkyDialog<bool>(
    context,
    builder: (c) => ChunkyDialog(
      title: 'Mikrofon masih diblokir',
      message: _isIos
          ? 'Buka Pengaturan › Ghina, lalu nyalakan Mikrofon (dan Pengenalan '
                'Ucapan untuk dikte).'
          : 'Buka Pengaturan › Aplikasi › Ghina › Izin, lalu izinkan '
                'Mikrofon.',
      mood: MascotMood.thinking,
      actions: [
        ChunkyButton(
          key: const ValueKey('mic-settings'),
          label: 'Buka Pengaturan',
          icon: Icons.settings_rounded,
          onPressed: () => Navigator.of(c).pop(true),
        ),
        ChunkyButton(
          label: 'Nanti saja',
          variant: ChunkyButtonVariant.ghost,
          onPressed: () => Navigator.of(c).pop(false),
        ),
      ],
    ),
  );
  if (open != true) return;
  final ok = await ref.read(microphonePermissionProvider).openAppSettings();
  if (!ok && context.mounted) {
    showToastBadge(
      context,
      message: 'Buka Pengaturan HP › Ghina › Mikrofon, ya',
      icon: Icons.settings_rounded,
      color: GhinaColors.blue,
    );
  }
}

bool get _isIos {
  try {
    return Platform.isIOS;
  } catch (_) {
    return false;
  }
}
