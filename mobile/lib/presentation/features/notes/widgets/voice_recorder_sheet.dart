import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';
import 'mic_permission.dart';
import 'note_visuals.dart';

/// "Rekam suara": a sheet with the recorder (live waveform, timer, 10-minute
/// limit, Batal / Simpan). Returns the finished clip, or null when cancelled.
/// [autoStart] starts recording right away (long-press on the Notes FAB).
/// Closing the sheet any other way discards an unfinished clip.
Future<VoiceRecording?> showVoiceRecorderSheet(
  BuildContext context, {
  bool autoStart = false,
}) => showChunkyBottomSheet<VoiceRecording>(
  context,
  title: 'Rekam suara',
  showClose: true,
  builder: (_) => VoiceRecorderPanel(autoStart: autoStart),
);

class VoiceRecorderPanel extends ConsumerStatefulWidget {
  const VoiceRecorderPanel({super.key, this.autoStart = false});

  final bool autoStart;

  @override
  ConsumerState<VoiceRecorderPanel> createState() => _VoiceRecorderPanelState();
}

class _VoiceRecorderPanelState extends ConsumerState<VoiceRecorderPanel> {
  bool _done = false;
  bool _tooShort = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  VoiceRecorderController get _c =>
      ref.read(voiceRecorderControllerProvider.notifier);

  Future<void> _start() async {
    setState(() => _tooShort = false);
    if (!await ensureMicReady(context, ref, MicPurpose.record)) return;
    if (!mounted) return;
    await _c.start();
  }

  void _finish(VoiceRecording rec) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(rec);
  }

  Future<void> _save() async {
    final rec = await _c.stop();
    if (!mounted) return;
    final taken = _c.takeRecording() ?? rec;
    if (taken != null) {
      _finish(taken);
    } else if (ref.read(voiceRecorderControllerProvider).phase ==
        VoiceRecorderPhase.idle) {
      setState(() => _tooShort = true);
    }
  }

  Future<void> _cancel() async {
    await _c.cancel();
    if (mounted && !_done) {
      _done = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = ref.watch(voiceRecorderControllerProvider);
    ref.listen(voiceRecorderControllerProvider, (_, next) {
      if (next.autoStopped && next.lastRecording != null) {
        final rec = _c.takeRecording();
        if (rec != null) {
          showToastBadge(
            context,
            message: 'Sudah 10 menit, rekaman disimpan otomatis',
            icon: Icons.timer_rounded,
            color: GhinaColors.orange,
          );
          _finish(rec);
        }
      }
    });

    final recording = s.phase == VoiceRecorderPhase.recording;
    final busy = s.isBusy;
    final max = s.maxDuration;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: g.surfaceAlt,
            borderRadius: GhinaRadii.rLg,
          ),
          child: CustomPaint(
            key: const ValueKey('rec-waveform'),
            painter: WaveformPainter(
              levels: s.levels,
              color: recording ? GhinaColors.red.base : g.textMuted,
              samples: VoiceRecorderController.waveformSamples,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (recording) ...[const _RecDot(), const SizedBox(width: 8)],
            Text(
              formatClock(s.elapsed),
              key: const ValueKey('rec-timer'),
              style: GhinaType.moneyL.copyWith(color: g.textPrimary),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                busy
                    ? 'sisa ${formatClock(s.remaining)}'
                    : 'maks. ${formatClock(max)}',
                style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ChunkyProgressBar(
          value: s.progress,
          color: s.progress > 0.9 ? GhinaColors.orange : GhinaColors.red,
          height: 10,
        ),
        const SizedBox(height: 14),
        if (s.phase == VoiceRecorderPhase.error)
          _ErrorBox(state: s, onRetry: _start)
        else if (_tooShort)
          _Hint(
            icon: Icons.info_rounded,
            text: 'Rekamannya kependekan. Coba tahan sedikit lebih lama, ya.',
          )
        else
          _Hint(
            icon: recording ? Icons.graphic_eq_rounded : Icons.lock_rounded,
            text: recording
                ? 'Lagi merekam… ketuk Simpan kalau sudah selesai.'
                : 'Rekaman disimpan di HP dulu, nanti ikut tersinkron. '
                      'Mau jadi teks? Pakai "Dikte" di editor.',
          ),
        const SizedBox(height: 16),
        if (!busy)
          ChunkyButton(
            key: const ValueKey('rec-start'),
            label: s.phase == VoiceRecorderPhase.error
                ? 'Coba lagi'
                : 'Mulai rekam',
            icon: Icons.mic_rounded,
            color: GhinaColors.red,
            onPressed: _start,
          )
        else
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('rec-cancel'),
                  label: 'Batal',
                  variant: ChunkyButtonVariant.outline,
                  color: GhinaColors.red,
                  onPressed: s.phase == VoiceRecorderPhase.stopping
                      ? null
                      : _cancel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('rec-save'),
                  label: 'Simpan',
                  loading: s.phase != VoiceRecorderPhase.recording,
                  onPressed: recording ? _save : null,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: g.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends ConsumerWidget {
  const _ErrorBox({required this.state, required this.onRetry});
  final VoiceRecorderState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final permanent = state.permission == MicPermissionStatus.permanentlyDenied;
    final text = switch (state.error) {
      VoiceRecorderErrorKind.permission =>
        permanent
            ? 'Izin mikrofon diblokir. Aktifkan lewat Pengaturan, ya.'
            : 'Izin mikrofon belum diberikan.',
      VoiceRecorderErrorKind.busy =>
        'Mikrofon lagi dipakai aplikasi lain. Tutup dulu, lalu coba lagi.',
      VoiceRecorderErrorKind.unsupported =>
        'Perangkat ini belum bisa merekam suara.',
      _ => 'Ups, rekaman gagal. Coba lagi, yuk.',
    };
    return ChunkyCard(
      tinted: GhinaColors.red,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.mic_off_rounded, color: GhinaColors.red.base),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  key: const ValueKey('rec-error'),
                  style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
                ),
              ),
            ],
          ),
          if (permanent) ...[
            const SizedBox(height: 10),
            ChunkyButton(
              label: 'Buka Pengaturan',
              size: ChunkyButtonSize.small,
              variant: ChunkyButtonVariant.outline,
              icon: Icons.settings_rounded,
              onPressed: () => showMicSettingsGuide(context, ref),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: GhinaColors.red.base,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}

/// Rounded level bars, newest on the right (0..1 levels).
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.levels,
    required this.color,
    this.samples = 48,
  });

  final List<double> levels;
  final Color color;
  final int samples;

  @override
  void paint(Canvas canvas, Size size) {
    final n = samples;
    final gap = 3.0;
    final w = math.max(2.0, (size.width - gap * (n - 1)) / n);
    final paint = Paint()..color = color;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final li = levels.length - n + i;
      final v = li >= 0 ? levels[li] : 0.0;
      final h = math.max(4.0, v.clamp(0.0, 1.0) * size.height);
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, w, h),
          Radius.circular(w / 2),
        ),
        paint..color = li >= 0 ? color : color.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.levels != levels || old.color != color;
}
