import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';

/// Live "Dikte" panel docked above the editor toolbar: mic level, the live
/// partial text (greyed — final text lands in the body as you speak), the
/// best-effort offline hint, Selesai / Batal.
class DictationBar extends ConsumerWidget {
  const DictationBar({super.key, required this.onStop, required this.onCancel});

  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final d = ref.watch(dictationControllerProvider);
    final status = switch (d.phase) {
      DictationPhase.starting => 'Menyiapkan mikrofon…',
      DictationPhase.restarting => 'Masih mendengarkan…',
      DictationPhase.stopping => 'Merapikan teks…',
      _ => 'Mendengarkan… ngomong aja',
    };
    final bestEffort = d.availability?.offline == OfflineSpeechSupport.unknown;
    return Container(
      key: const ValueKey('dictation-bar'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: GhinaColors.blue.tint(g.brightness),
        borderRadius: GhinaRadii.rLg,
        border: Border.all(
          color: GhinaColors.blue.tintBorder(g.brightness),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _MicLevel(level: d.level),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: GhinaType.bodyS
                          .w(900)
                          .copyWith(color: GhinaColors.blue.base),
                    ),
                    if (d.partial.isNotEmpty)
                      Text(
                        d.partial,
                        key: const ValueKey('dictation-partial'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body.copyWith(
                          color: g.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('dictation-cancel'),
                onPressed: onCancel,
                child: const Text('Batal'),
              ),
              const SizedBox(width: 4),
              ChunkyButton(
                key: const ValueKey('dictation-stop'),
                label: 'Selesai',
                size: ChunkyButtonSize.small,
                color: GhinaColors.blue,
                expand: false,
                onPressed: d.phase == DictationPhase.stopping ? null : onStop,
              ),
            ],
          ),
          if (bestEffort && d.hint != null) ...[
            const SizedBox(height: 6),
            Text(
              d.hint!,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _MicLevel extends StatelessWidget {
  const _MicLevel({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final v = level.clamp(0.0, 1.0);
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28 + 12 * v,
            height: 28 + 12 * v,
            decoration: BoxDecoration(
              color: GhinaColors.blue.base.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GhinaColors.blue.base,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Explains why "Dikte" can't start here (offline pack missing, no speech
/// service…) with "Unduh" when the OS can fetch the id-ID model.
Future<void> showDictationUnavailable(
  BuildContext context,
  WidgetRef ref,
  SpeechAvailability availability,
) async {
  final canDownload = availability.offline == OfflineSpeechSupport.downloadable;
  final download = await showChunkyDialog<bool>(
    context,
    builder: (c) => ChunkyDialog(
      title: 'Dikte belum bisa dipakai',
      message:
          availability.hint ??
          'Pengenalan suara belum tersedia di perangkat ini.',
      mood: MascotMood.thinking,
      content: Text(
        'Tenang, "Rekam suara" tetap bisa dipakai kapan saja.',
        textAlign: TextAlign.center,
        style: GhinaType.bodyS.copyWith(color: c.ghina.textSecondary),
      ),
      actions: [
        if (canDownload)
          ChunkyButton(
            key: const ValueKey('dictation-download'),
            label: 'Unduh paket suara',
            icon: Icons.download_rounded,
            onPressed: () => Navigator.of(c).pop(true),
          ),
        ChunkyButton(
          label: 'Oke',
          variant: canDownload
              ? ChunkyButtonVariant.ghost
              : ChunkyButtonVariant.primary,
          onPressed: () => Navigator.of(c).pop(false),
        ),
      ],
    ),
  );
  if (download != true) return;
  final ok = await ref
      .read(dictationControllerProvider.notifier)
      .downloadOfflineModel();
  if (!context.mounted) return;
  showToastBadge(
    context,
    message: ok
        ? 'Paket suara lagi diunduh. Coba Dikte lagi sebentar lagi, ya'
        : 'Unduh lewat Google › Pengenalan ucapan offline › Bahasa Indonesia',
    icon: Icons.download_rounded,
    color: GhinaColors.blue,
  );
}
