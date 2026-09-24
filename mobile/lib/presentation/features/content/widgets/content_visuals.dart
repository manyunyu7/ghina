import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

/// Material icon for a platform's lucide icon name (lucide has no brand logos,
/// so the icon is always paired with the account color and code).
IconData platformIcon(SocialPlatform p) => switch (p.icon) {
  'camera' => Icons.camera_alt_rounded,
  'music-2' => Icons.music_note_rounded,
  'play' => Icons.play_arrow_rounded,
  'at-sign' => Icons.alternate_email_rounded,
  'briefcase' => Icons.work_rounded,
  'users' => Icons.groups_rounded,
  _ => Icons.public_rounded,
};

/// A user color that stays visible on the current surface: near-black brand
/// colors (X, Threads) turn light gray in dark mode.
Color readableColor(BuildContext context, String? hex) {
  final c = CategoryColors.parse(hex);
  if (context.ghina.isDark && c.computeLuminance() < 0.03) {
    return const Color(0xFFD0D4D8);
  }
  return c;
}

ChunkySwatch readableSwatch(BuildContext context, String? hex) =>
    ChunkySwatch.fromColor(readableColor(context, hex));

ChunkySwatch stageSwatch(ContentStage s) => CategoryColors.swatch(s.color);

/// Stage → icon (chips, badges, the "Lanjut" button).
IconData stageIcon(ContentStage s) => switch (s) {
  ContentStage.ide => Icons.lightbulb_rounded,
  ContentStage.naskah => Icons.edit_note_rounded,
  ContentStage.produksi => Icons.movie_creation_rounded,
  ContentStage.siap => Icons.check_circle_rounded,
  ContentStage.terjadwal => Icons.event_rounded,
  ContentStage.tayang => Icons.rocket_launch_rounded,
};

/// Stage icon in its color (gray `ide` darkened for contrast on white).
Color stageColor(BuildContext context, ContentStage s) =>
    s == ContentStage.ide && !context.ghina.isDark
    ? const Color(0xFF8A8A8A)
    : stageSwatch(s).base;

ChunkySwatch postStatusSwatch(PostStatus s) => switch (s) {
  PostStatus.draft => GhinaColors.gray,
  PostStatus.scheduled => GhinaColors.yellow,
  PostStatus.posted => GhinaColors.green,
  PostStatus.skipped => GhinaColors.gray,
};

/// Round account badge: platform icon on the account color, with an optional
/// status dot (per-post status on board cards).
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.account,
    this.size = 36,
    this.status,
  });

  final SocialAccount account;
  final double size;
  final PostStatus? status;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = readableColor(context, account.color);
    final on = c.computeLuminance() > 0.55
        ? const Color(0xFF2B2B2B)
        : Colors.white;
    final dot = size * 0.36;
    return Semantics(
      label: '${account.platformLabel} ${account.atHandle}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(color: g.surface, width: size * 0.06),
              ),
              child: Icon(
                platformIcon(account.platform),
                size: size * 0.5,
                color: on,
              ),
            ),
            if (status != null)
              Positioned(
                right: -dot * 0.15,
                bottom: -dot * 0.15,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: postStatusSwatch(status!).base,
                    shape: BoxShape.circle,
                    border: Border.all(color: g.surface, width: 2),
                  ),
                  child: status == PostStatus.posted
                      ? Icon(
                          Icons.check_rounded,
                          size: dot * 0.7,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Overlapping row of account avatars.
class AccountAvatarStack extends StatelessWidget {
  const AccountAvatarStack({
    super.key,
    required this.posts,
    this.size = 28,
    this.max = 4,
  });

  final List<ContentPostView> posts;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final p in posts)
        if (p.account != null) p,
    ].take(max).toList();
    final extra = posts.length - shown.length;
    final step = size * 0.72;
    return SizedBox(
      height: size,
      width: shown.isEmpty
          ? 0
          : step * (shown.length - 1) + size + (extra > 0 ? step : 0),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: AccountAvatar(
                account: shown[i].account!,
                size: size,
                status: shown[i].post.status,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: step * shown.length,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.ghina.surfaceAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.ghina.border, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: context.ghina.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `💡 Ide` pill in the stage color.
class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage, this.soft = true});

  final ContentStage stage;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final sw = stageSwatch(stage);
    final g = context.ghina;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: soft ? sw.tint(g.brightness) : sw.base,
        borderRadius: BorderRadius.circular(GhinaRadii.pill),
      ),
      child: Text(
        '${stage.emoji} ${stage.label}',
        style: GhinaType.caption
            .w(800)
            .copyWith(color: soft ? g.textPrimary : sw.on),
      ),
    );
  }
}

/// Small colored-dot chip for a pillar or format.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: BorderRadius.circular(GhinaRadii.pill),
        border: Border.all(color: g.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 13, color: g.textSecondary),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.w(700).copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status pill of a post (`TERJADWAL`, `TAYANG` …).
class PostStatusPill extends StatelessWidget {
  const PostStatusPill({super.key, required this.status});
  final PostStatus status;

  @override
  Widget build(BuildContext context) => ChunkyPill(
    label: status.label,
    color: postStatusSwatch(status),
    soft: status != PostStatus.posted,
    icon: switch (status) {
      PostStatus.draft => Icons.edit_rounded,
      PostStatus.scheduled => Icons.schedule_rounded,
      PostStatus.posted => Icons.rocket_launch_rounded,
      PostStatus.skipped => Icons.skip_next_rounded,
    },
  );
}

/// Format → icon.
IconData formatIcon(ContentFormat? f) => switch (f) {
  ContentFormat.post => Icons.image_rounded,
  ContentFormat.carousel => Icons.view_carousel_rounded,
  ContentFormat.reel || ContentFormat.short => Icons.slow_motion_video_rounded,
  ContentFormat.story => Icons.amp_stories_rounded,
  ContentFormat.video => Icons.smart_display_rounded,
  ContentFormat.thread => Icons.forum_rounded,
  ContentFormat.live => Icons.sensors_rounded,
  _ => Icons.category_rounded,
};

/// Color of pillar [name] from the pillar list (case-insensitive), else a
/// stable color from the name.
Color pillarColor(
  BuildContext context,
  String name,
  List<ContentPillar> pillars,
) {
  final key = name.toLowerCase();
  for (final p in pillars) {
    if (p.name.toLowerCase() == key) return readableColor(context, p.color);
  }
  return CategoryColors.forKey(name);
}
