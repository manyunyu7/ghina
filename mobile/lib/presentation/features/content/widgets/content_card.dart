import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../content_format.dart';
import 'content_visuals.dart';

/// A board card: title, format, pillar, sponsor, schedule, checklist progress,
/// account avatars with per-post status dots, and a quick "Lanjut" button.
class ContentCard extends StatelessWidget {
  const ContentCard({
    super.key,
    required this.view,
    required this.pillars,
    required this.now,
    this.onTap,
    this.onMenu,
    this.onAdvance,
  });

  final ContentItemView view;
  final List<ContentPillar> pillars;
  final DateTime now;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final VoidCallback? onAdvance;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final item = view.item;
    final next = nextStage(item.stage);
    final at = view.nextScheduledAt;
    final sponsor = item.sponsor;
    final checklist = item.checklist;
    final meta = <Widget>[
      if (at != null)
        _Meta(
          icon: Icons.event_rounded,
          label: contentWhenLabel(at, now),
          color: at.isBefore(now) ? GhinaColors.red.base : null,
        ),
      if (view.postedCount > 0 && item.stage != ContentStage.tayang)
        _Meta(
          icon: Icons.rocket_launch_rounded,
          label: '${view.postedCount}/${view.posts.length} tayang',
        ),
      if (checklist.isNotEmpty)
        _Meta(
          icon: Icons.checklist_rounded,
          label: '${item.checklistDone}/${checklist.length}',
          color: item.checklistDone == checklist.length
              ? GhinaColors.green.base
              : null,
        ),
    ];
    return ChunkyCard(
      key: ValueKey('content-card-${item.id}'),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      semanticLabel: item.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.h3.copyWith(color: g.textPrimary),
                  ),
                ),
              ),
              if (onMenu != null)
                IconButton(
                  key: ValueKey('content-menu-${item.id}'),
                  tooltip: 'Pindah tahap',
                  visualDensity: VisualDensity.compact,
                  onPressed: onMenu,
                  icon: Icon(Icons.more_vert_rounded, color: g.textMuted),
                ),
            ],
          ),
          if (item.format != null || item.pillar != null || sponsor != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (item.format != null)
                    TagChip(
                      label: item.format!.label,
                      icon: formatIcon(item.format),
                    ),
                  if (item.pillar != null)
                    TagChip(
                      label: item.pillar!,
                      color: pillarColor(context, item.pillar!, pillars),
                    ),
                  if (sponsor != null)
                    ChunkyPill(
                      label: sponsor.paid ? 'Lunas' : 'Sponsor',
                      icon: Icons.handshake_rounded,
                      color: sponsor.paid
                          ? GhinaColors.green
                          : GhinaColors.orange,
                      soft: true,
                    ),
                ],
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 6),
              child: Wrap(spacing: 12, runSpacing: 4, children: meta),
            ),
          if (view.posts.isNotEmpty || (next != null && onAdvance != null))
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 6),
              child: Row(
                children: [
                  AccountAvatarStack(posts: view.posts),
                  const Spacer(),
                  if (next != null && onAdvance != null)
                    _AdvanceButton(
                      key: ValueKey('content-advance-${item.id}'),
                      to: next,
                      onTap: onAdvance!,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.ghina.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 4),
        Text(label, style: GhinaType.bodyS.w(700).copyWith(color: c)),
      ],
    );
  }
}

class _AdvanceButton extends StatelessWidget {
  const _AdvanceButton({super.key, required this.to, required this.onTap});
  final ContentStage to;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = stageSwatch(to);
    return ChunkySurface(
      color: sw.tint(g.brightness),
      edgeColor: sw.base.withValues(alpha: 0.6),
      borderColor: sw.base.withValues(alpha: 0.6),
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rPill,
      onTap: onTap,
      semanticLabel: 'Lanjut ke ${to.label}',
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stageIcon(to), size: 16, color: stageColor(context, to)),
          const SizedBox(width: 4),
          Text(
            to.label,
            style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_forward_rounded, size: 16, color: g.textPrimary),
        ],
      ),
    );
  }
}

/// "Pindah tahap" sheet: every stage, the current one marked. Returns the pick.
Future<ContentStage?> showStagePickerSheet(
  BuildContext context, {
  required ContentItem item,
}) => showChunkyBottomSheet<ContentStage>(
  context,
  title: 'Pindah tahap',
  showClose: true,
  builder: (c) {
    final g = c.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.body.copyWith(color: g.textSecondary),
          ),
        ),
        for (final s in ContentStage.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              key: ValueKey('stage-pick-${s.wire}'),
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: stageSwatch(s).tint(g.brightness),
                  shape: BoxShape.circle,
                ),
                child: Icon(stageIcon(s), color: stageColor(c, s)),
              ),
              title: s.label,
              subtitle: s == item.stage
                  ? 'Tahap sekarang'
                  : (s.isAfter(item.stage) && moveXp(item, s) > 0
                        ? '+${moveXp(item, s)} XP'
                        : null),
              tinted: s == item.stage ? stageSwatch(s) : null,
              trailing: s == item.stage
                  ? Icon(Icons.check_circle_rounded, color: stageSwatch(s).base)
                  : null,
              dense: true,
              onTap: () => Navigator.of(c).pop(s),
            ),
          ),
      ],
    );
  },
);
