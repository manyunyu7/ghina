import 'package:flutter/material.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// Shimmering placeholder block. Compose into layouts or use
/// [SkeletonTile] / [SkeletonList] for lists.
///
/// ```dart
/// Skeleton(width: 120, height: 18);
/// Skeleton.circle(size: 44);
/// const SkeletonList(count: 5);
/// ```
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = GhinaRadii.md,
  });

  const Skeleton.circle({super.key, double size = 44})
    : width = size,
      height = size,
      radius = 999;

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.value * 3 - 1; // -1..2
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2 - 1, 0),
              end: Alignment(1 + t * 2 - 1, 0),
              colors: [g.skeleton, g.skeletonHighlight, g.skeleton],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton shaped like a [ChunkyTile] (avatar + two lines + amount).
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: GhinaRadii.rLg,
        border: Border.all(color: g.border, width: 2),
      ),
      child: const Row(
        children: [
          Skeleton(width: 44, height: 44, radius: 13),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 140, height: 16),
                SizedBox(height: 8),
                Skeleton(width: 90, height: 12),
              ],
            ),
          ),
          Skeleton(width: 70, height: 18),
        ],
      ),
    );
  }
}

/// Column of [SkeletonTile]s for loading lists.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.gap = 10});

  final int count;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: gap),
          const SkeletonTile(),
        ],
      ],
    );
  }
}

/// Sync state shown by [SyncBadge]. The sync layer maps its status to this.
enum SyncIndicatorState {
  /// Online, everything pushed.
  synced,

  /// Currently pushing/pulling.
  syncing,

  /// No connection – changes are queued locally.
  offline,

  /// Last sync failed (will retry).
  error,
}

/// Small pill showing sync status (+ pending change count).
///
/// ```dart
/// SyncBadge(state: SyncIndicatorState.offline, pendingCount: 3, onTap: () => context.push('/sync'));
/// SyncBadge(state: SyncIndicatorState.synced, compact: true);   // icon only
/// ```
class SyncBadge extends StatefulWidget {
  const SyncBadge({
    super.key,
    required this.state,
    this.pendingCount = 0,
    this.compact = false,
    this.onTap,
  });

  final SyncIndicatorState state;
  final int pendingCount;

  /// Icon-only circle.
  final bool compact;
  final VoidCallback? onTap;

  @override
  State<SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends State<SyncBadge>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SyncBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.state == SyncIndicatorState.syncing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final (
      ChunkySwatch sw,
      IconData icon,
      String label,
    ) = switch (widget.state) {
      SyncIndicatorState.synced => (
        GhinaColors.green,
        Icons.cloud_done_rounded,
        'Tersinkron',
      ),
      SyncIndicatorState.syncing => (
        GhinaColors.blue,
        Icons.sync_rounded,
        'Menyinkron',
      ),
      SyncIndicatorState.offline => (
        GhinaColors.gray,
        Icons.cloud_off_rounded,
        'Offline',
      ),
      SyncIndicatorState.error => (
        GhinaColors.red,
        Icons.sync_problem_rounded,
        'Gagal sinkron',
      ),
    };
    final fg = widget.state == SyncIndicatorState.offline
        ? g.textSecondary
        : (g.isDark ? sw.base : sw.edge);
    final bg = widget.state == SyncIndicatorState.offline
        ? g.surfaceAlt
        : sw.tint(g.brightness);
    final border = widget.state == SyncIndicatorState.offline
        ? g.border
        : sw.tintBorder(g.brightness);

    Widget iconW = Icon(icon, size: 18, color: fg);
    if (widget.state == SyncIndicatorState.syncing) {
      iconW = RotationTransition(turns: ReverseAnimation(_spin), child: iconW);
    }
    final text =
        widget.pendingCount > 0 && widget.state != SyncIndicatorState.synced
        ? '$label · ${widget.pendingCount}'
        : label;

    final child = AnimatedContainer(
      duration: GhinaMotion.fast,
      padding: widget.compact
          ? const EdgeInsets.all(6)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: GhinaRadii.rPill,
        border: Border.all(color: border, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconW,
          if (!widget.compact) ...[
            const SizedBox(width: 5),
            Text(text, style: GhinaType.caption.w(900).copyWith(color: fg)),
          ],
        ],
      ),
    );
    return Semantics(
      label: text,
      button: widget.onTap != null,
      child: widget.onTap == null
          ? child
          : GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: child,
            ),
    );
  }
}
