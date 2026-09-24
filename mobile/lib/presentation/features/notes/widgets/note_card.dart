import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'note_visuals.dart';

/// Plain-text preview lines of a body (markdown markers stripped, blank lines
/// dropped). Skips the first line when it already serves as the card title.
List<String> bodyPreviewLines(Note n, {int max = 8}) {
  final out = <String>[];
  var skipFirst = (n.title ?? '').trim().isEmpty;
  for (final raw in n.body.split('\n')) {
    final isBullet = RegExp(r'^\s*([-*+]|\d+[.)])\s+').hasMatch(raw);
    final t = stripMarkdown(raw);
    if (t.isEmpty) continue;
    if (skipFirst) {
      skipFirst = false;
      continue;
    }
    out.add(isBullet ? '• $t' : t);
    if (out.length >= max) break;
  }
  return out;
}

/// A note card for the grid/list: color, photo, title, body preview,
/// checklist progress, clip/link indicators, label chips, conversions.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.view,
    required this.onTap,
    this.onLongPress,
    this.compact = false,
    this.showArchived = false,
  });

  final NoteView view;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// List mode: fewer preview lines, photo as a side thumbnail.
  final bool compact;

  /// Marks archived notes (search results that include the archive).
  final bool showArchived;

  @override
  Widget build(BuildContext context) {
    final n = view.note;
    final tone = NoteTone.of(context, n.color);
    final title = n.displayTitle;
    final lines = bodyPreviewLines(n, max: compact ? 2 : 6);
    final photo = n.photos.isEmpty ? null : noteViewerPhotos(n.photos).first;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? 'Catatan tanpa judul' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3
                      .w(900)
                      .copyWith(
                        color: title.isEmpty ? tone.subtle : tone.text,
                        height: 1.2,
                      ),
                ),
              ),
              if (n.pinned) ...[
                const SizedBox(width: 4),
                Icon(Icons.push_pin_rounded, size: 16, color: tone.subtle),
              ],
            ],
          ),
          for (final l in lines) ...[
            const SizedBox(height: 3),
            Text(
              l,
              maxLines: compact ? 1 : 3,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.copyWith(color: tone.subtle, height: 1.3),
            ),
          ],
          if (n.hasChecklist) ...[
            const SizedBox(height: 8),
            _ChecklistPreview(note: n, tone: tone, compact: compact),
          ],
          if (_hasIndicators(n)) ...[
            const SizedBox(height: 8),
            _Indicators(note: n, tone: tone),
          ],
          if (view.labels.isNotEmpty || (showArchived && n.archived)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (showArchived && n.archived)
                  ChunkyPill(
                    label: 'Arsip',
                    color: GhinaColors.gray,
                    soft: true,
                    icon: Icons.archive_rounded,
                  ),
                for (final l in view.labels.take(3))
                  NoteLabelChip(label: l, onCard: !tone.isDefault),
                if (view.labels.length > 3)
                  Text(
                    '+${view.labels.length - 3}',
                    style: GhinaType.caption
                        .w(800)
                        .copyWith(color: tone.subtle),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    final Widget body;
    if (photo == null) {
      body = content;
    } else if (compact) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: content),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
            child: ClipRRect(
              borderRadius: GhinaRadii.rMd,
              child: SizedBox(
                width: 64,
                height: 64,
                child: PhotoImage(photo: photo, cacheWidth: 200),
              ),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: PhotoImage(photo: photo, cacheWidth: 500),
              ),
              if (n.photos.length > 1)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: _CountBubble(
                    icon: Icons.photo_library_rounded,
                    text: '${n.photos.length}',
                  ),
                ),
            ],
          ),
          content,
        ],
      );
    }

    return ChunkySurface(
      key: ValueKey('note-card-${n.id}'),
      color: tone.face,
      edgeColor: tone.edge,
      borderColor: tone.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: title.isEmpty ? 'Catatan' : title,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: body,
      ),
    );
  }
}

bool _hasIndicators(Note n) =>
    n.hasAudio ||
    n.links.isNotEmpty ||
    n.linkedTaskId != null ||
    n.linkedContentId != null ||
    n.linkedTransactionId != null ||
    n.hasPendingUploads;

class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({
    required this.note,
    required this.tone,
    required this.compact,
  });

  final Note note;
  final NoteTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = note.checklist;
    final done = note.checklistDone;
    final open = [
      for (final c in items)
        if (!c.done) c,
    ];
    final shown = compact ? const <ChecklistItem>[] : open.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                Icon(
                  Icons.check_box_outline_blank_rounded,
                  size: 16,
                  color: tone.subtle,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    c.text.isEmpty ? '…' : c.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: tone.text),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Icon(
              done == items.length
                  ? Icons.check_circle_rounded
                  : Icons.checklist_rounded,
              size: 16,
              color: done == items.length
                  ? GhinaColors.green.base
                  : tone.subtle,
            ),
            const SizedBox(width: 6),
            Text(
              '$done/${items.length}',
              style: GhinaType.caption.w(900).copyWith(color: tone.subtle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: GhinaRadii.rPill,
                child: LinearProgressIndicator(
                  value: items.isEmpty ? 0 : done / items.length,
                  minHeight: 6,
                  backgroundColor: tone.isDefault
                      ? context.ghina.surfaceAlt
                      : Colors.black.withValues(alpha: 0.08),
                  color: GhinaColors.green.base,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Indicators extends StatelessWidget {
  const _Indicators({required this.note, required this.tone});

  final Note note;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final n = note;
    final total = n.audio.fold<int>(0, (s, a) => s + a.durationSec);
    final firstLink = n.links.isEmpty ? null : n.links.first;
    Widget ind(IconData icon, String text, {Key? key}) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: tone.subtle),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.w(800).copyWith(color: tone.subtle),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (firstLink != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ind(
              Icons.link_rounded,
              firstLink.title ?? linkHost(firstLink.url),
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            if (n.hasAudio)
              ind(
                Icons.mic_rounded,
                n.audio.length > 1
                    ? '${n.audio.length} · ${formatClock(Duration(seconds: total))}'
                    : formatClock(Duration(seconds: total)),
                key: const ValueKey('ind-audio'),
              ),
            if (n.audio.any((a) => a.hasTranscript))
              ind(Icons.subject_rounded, 'Transkrip'),
            if (n.links.length > 1)
              ind(Icons.link_rounded, '${n.links.length}'),
            if (n.linkedTaskId != null) ind(Icons.task_alt_rounded, 'Tugas'),
            if (n.linkedContentId != null)
              ind(Icons.movie_creation_rounded, 'Konten'),
            if (n.linkedTransactionId != null)
              ind(Icons.receipt_long_rounded, 'Transaksi'),
            if (n.hasPendingUploads)
              ind(Icons.cloud_upload_rounded, 'Belum diunggah'),
          ],
        ),
      ],
    );
  }
}

class _CountBubble extends StatelessWidget {
  const _CountBubble({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: GhinaRadii.rPill,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          text,
          style: GhinaType.caption.w(900).copyWith(color: Colors.white),
        ),
      ],
    ),
  );
}

/// Rough height weight used to balance the two masonry columns.
int noteCardWeight(Note n) {
  var w = 60;
  if (n.hasPhotos) w += 120;
  w += bodyPreviewLines(n, max: 6).length * 22;
  if (n.hasChecklist) {
    w += 24 + n.checklist.where((c) => !c.done).take(3).length * 20;
  }
  if (_hasIndicators(n)) w += 24;
  if (n.hasLabels) w += 26;
  return w;
}
