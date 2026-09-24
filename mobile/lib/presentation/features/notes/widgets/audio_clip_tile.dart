import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';
import 'note_visuals.dart';

/// Player key of a clip (local file or server path).
String clipKey(NoteAudio a) => a.localPath ?? a.url ?? '';

/// One saved voice clip: play/pause, scrubbing slider, duration, pending
/// upload badge, transcript (if any) and a delete button.
class AudioClipTile extends ConsumerWidget {
  const AudioClipTile({
    super.key,
    required this.clip,
    required this.index,
    this.onDelete,
    this.onInsertTranscript,
  });

  final NoteAudio clip;
  final int index;
  final VoidCallback? onDelete;
  final VoidCallback? onInsertTranscript;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final p = ref.watch(voicePlayerControllerProvider);
    final c = ref.read(voicePlayerControllerProvider.notifier);
    final key = clipKey(clip);
    final active = p.key == key;
    final playing = p.isPlaying(key);
    final loading = active && p.status == PlaybackStatus.loading;
    final failed = active && p.status == PlaybackStatus.error;
    final total = active && p.duration != null && p.duration! > Duration.zero
        ? p.duration!
        : Duration(seconds: clip.durationSec);
    final pos = p.positionOf(key);
    final max = total.inMilliseconds.toDouble();
    final value = max <= 0 ? 0.0 : pos.inMilliseconds.clamp(0, max).toDouble();

    return ChunkyCard(
      key: ValueKey('clip-$index'),
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: ChunkySurface(
                  key: ValueKey('clip-play-$index'),
                  color: GhinaColors.red.base,
                  edgeColor: GhinaColors.red.edge,
                  depth: GhinaDepth.sm,
                  borderRadius: GhinaRadii.rPill,
                  semanticLabel: playing ? 'Jeda' : 'Putar',
                  onTap: () => c.toggle(
                    key,
                    filePath: clip.localPath,
                    url: AppConfig.resolveUrl(clip.url),
                  ),
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 5,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Slider(
                          key: ValueKey('clip-slider-$index'),
                          value: value,
                          max: max <= 0 ? 1 : max,
                          activeColor: GhinaColors.red.base,
                          inactiveColor: g.surfaceAlt,
                          onChanged: active && max > 0
                              ? (v) => c.seek(Duration(milliseconds: v.round()))
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Text(
                            active
                                ? '${formatClock(pos)} / ${formatClock(total)}'
                                : formatClock(total),
                            style: GhinaType.caption
                                .w(800)
                                .copyWith(color: g.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: failed
                                ? Text(
                                    'Gagal diputar',
                                    textAlign: TextAlign.end,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GhinaType.caption
                                        .w(800)
                                        .copyWith(color: GhinaColors.red.base),
                                  )
                                : clip.isPending
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Icon(
                                        Icons.cloud_upload_rounded,
                                        size: 14,
                                        color: g.textMuted,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          'Belum diunggah',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GhinaType.caption
                                              .w(700)
                                              .copyWith(color: g.textMuted),
                                        ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  key: ValueKey('clip-delete-$index'),
                  tooltip: 'Hapus rekaman',
                  icon: Icon(Icons.delete_outline_rounded, color: g.textMuted),
                  onPressed: onDelete,
                ),
            ],
          ),
          if (clip.hasTranscript) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                clip.transcript!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.bodyS.copyWith(
                  color: g.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            if (onInsertTranscript != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onInsertTranscript,
                  icon: const Icon(Icons.subdirectory_arrow_left_rounded),
                  label: const Text('Masukkan ke catatan'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
