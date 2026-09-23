import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// Animated flickering flame, optionally with the streak count.
/// Gray when [active] is false (no activity logged today yet).
///
/// ```dart
/// StreakFlame(count: 12);                       // flame + "12"
/// StreakFlame(count: 0, active: false);          // gray, streak at risk
/// StreakFlame(count: 30, size: 96, showCount: false);   // hero flame
/// ```
class StreakFlame extends StatefulWidget {
  const StreakFlame({
    super.key,
    required this.count,
    this.active = true,
    this.size = 28,
    this.showCount = true,
    this.animate = true,
  });

  final int count;
  final bool active;
  final double size;
  final bool showCount;
  final bool animate;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate && widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant StreakFlame old) {
    super.didUpdateWidget(old);
    final run = widget.animate && widget.active;
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final flame = AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        size: Size(widget.size * 0.86, widget.size),
        painter: FlamePainter(
          phase: _c.value,
          active: widget.active,
          inactiveColor: g.border,
          inactiveInner: g.isDark ? g.textMuted : GhinaColors.swanEdge,
        ),
      ),
    );
    if (!widget.showCount) {
      return Semantics(label: 'Streak ${widget.count} hari', child: flame);
    }
    return Semantics(
      label: 'Streak ${widget.count} hari',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          flame,
          SizedBox(width: widget.size * 0.18),
          Pulse(
            trigger: widget.count,
            child: Text(
              '${widget.count}',
              style: GhinaType.h3
                  .w(900)
                  .copyWith(
                    fontSize: widget.size * 0.68,
                    color: widget.active
                        ? GhinaColors.orange.base
                        : g.textMuted,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the Ghina streak flame (outer orange, inner yellow, highlight).
class FlamePainter extends CustomPainter {
  FlamePainter({
    this.phase = 0,
    this.active = true,
    this.inactiveColor = GhinaColors.swan,
    this.inactiveInner = GhinaColors.swanEdge,
  });

  final double phase;
  final bool active;
  final Color inactiveColor;
  final Color inactiveInner;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = phase * 2 * math.pi;
    final flick = active ? math.sin(t) * 0.035 : 0.0;
    final sway = active ? math.sin(t * 2) * 0.025 : 0.0;

    Offset p(double x, double y) =>
        Offset(w * (x + sway * (1 - y)), h * (1 - (1 - y) * (1 + flick)));

    // Each path: start point then cubic segments as (c1, c2, end) triples,
    // in unit coordinates (0..1), y down.
    Path build(List<List<double>> pts) {
      final path = Path();
      final s = p(pts[0][0], pts[0][1]);
      path.moveTo(s.dx, s.dy);
      for (var i = 1; i + 2 < pts.length; i += 3) {
        final a = p(pts[i][0], pts[i][1]);
        final b = p(pts[i + 1][0], pts[i + 1][1]);
        final c = p(pts[i + 2][0], pts[i + 2][1]);
        path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
      }
      return path..close();
    }

    final outer = build(const [
      [0.5, 1],
      [0.16, 1],
      [0.02, 0.78],
      [0.08, 0.55],
      [0.13, 0.38],
      [0.26, 0.32],
      [0.3, 0.16],
      [0.42, 0.26],
      [0.45, 0.34],
      [0.46, 0.42],
      [0.54, 0.26],
      [0.62, 0.12],
      [0.58, 0.0],
      [0.84, 0.14],
      [0.99, 0.4],
      [0.94, 0.64],
      [0.9, 0.86],
      [0.74, 1],
      [0.5, 1],
    ]);
    final inner = build(const [
      [0.5, 0.97],
      [0.33, 0.97],
      [0.25, 0.86],
      [0.29, 0.73],
      [0.33, 0.61],
      [0.46, 0.56],
      [0.5, 0.42],
      [0.58, 0.55],
      [0.72, 0.62],
      [0.72, 0.77],
      [0.72, 0.9],
      [0.63, 0.97],
      [0.5, 0.97],
    ]);

    canvas.drawPath(
      outer,
      Paint()..color = active ? GhinaColors.orange.base : inactiveColor,
    );
    canvas.drawPath(
      inner,
      Paint()..color = active ? GhinaColors.yellow.base : inactiveInner,
    );
    if (active) {
      // Highlight on the upper left of the main body.
      final hl = Path()
        ..addOval(
          Rect.fromCenter(
            center: p(0.25, 0.62),
            width: w * 0.1,
            height: h * 0.16,
          ),
        );
      canvas.drawPath(
        hl,
        Paint()..color = Colors.white.withValues(alpha: 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(FlamePainter old) =>
      old.phase != phase || old.active != active;
}

/// XP pill: yellow bolt + "+15 XP" (or "150 XP" when [plus] is false).
///
/// ```dart
/// XpBadge(xp: 15);                 // +15 XP (reward)
/// XpBadge(xp: 1240, plus: false);   // total
/// ```
class XpBadge extends StatelessWidget {
  const XpBadge({
    super.key,
    required this.xp,
    this.plus = true,
    this.large = false,
  });

  final int xp;
  final bool plus;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final fg = g.isDark ? GhinaColors.yellow.base : GhinaColors.yellow.edge;
    final fs = large ? 20.0 : 14.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 7 : 4,
      ),
      decoration: BoxDecoration(
        color: GhinaColors.yellow.tint(g.brightness),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: GhinaColors.yellow.base, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt_rounded,
            size: fs + 6,
            color: GhinaColors.yellow.base,
          ),
          const SizedBox(width: 2),
          Text(
            '${plus ? '+' : ''}$xp XP',
            style: GhinaType.body.w(900).copyWith(fontSize: fs, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Row of hearts (budget health). Filled red up to [hearts], gray after.
/// Lost hearts pop out when the count drops.
///
/// ```dart
/// HeartsRow(hearts: 3);              // ❤❤❤♡♡
/// HeartsRow(hearts: 5, max: 5, size: 20);
/// ```
class HeartsRow extends StatelessWidget {
  const HeartsRow({
    super.key,
    required this.hearts,
    this.max = 5,
    this.size = 26,
  });

  final int hearts;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      label: '$hearts dari $max hati',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Padding(
              padding: EdgeInsets.only(right: i == max - 1 ? 0 : size * 0.12),
              child: AnimatedSwitcher(
                duration: GhinaMotion.medium,
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: GhinaMotion.pop),
                  child: c,
                ),
                child: _Heart(
                  key: ValueKey(i < hearts),
                  filled: i < hearts,
                  size: size,
                  empty: g.border,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({
    super.key,
    required this.filled,
    required this.size,
    required this.empty,
  });

  final bool filled;
  final double size;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HeartPainter(filled ? null : empty),
    );
  }
}

class _HeartPainter extends CustomPainter {
  _HeartPainter(this.emptyColor);

  final Color? emptyColor;

  Path _heart(Size s, [double dy = 0]) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.9 + dy)
      ..cubicTo(
        w * 0.1,
        h * 0.62 + dy,
        w * 0.0,
        h * 0.38 + dy,
        w * 0.1,
        h * 0.22 + dy,
      )
      ..cubicTo(
        w * 0.22,
        h * 0.04 + dy,
        w * 0.44,
        h * 0.08 + dy,
        w * 0.5,
        h * 0.26 + dy,
      )
      ..cubicTo(
        w * 0.56,
        h * 0.08 + dy,
        w * 0.78,
        h * 0.04 + dy,
        w * 0.9,
        h * 0.22 + dy,
      )
      ..cubicTo(
        w * 1.0,
        h * 0.38 + dy,
        w * 0.9,
        h * 0.62 + dy,
        w * 0.5,
        h * 0.9 + dy,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (emptyColor != null) {
      canvas.drawPath(_heart(size), Paint()..color = emptyColor!);
      return;
    }
    canvas.drawPath(
      _heart(size, size.height * 0.06),
      Paint()..color = GhinaColors.red.edge,
    );
    canvas.drawPath(_heart(size), Paint()..color = GhinaColors.red.base);
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.2,
        size.width * 0.16,
        size.height * 0.12,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.emptyColor != emptyColor;
}

/// Level badge: a chunky purple hexagon with the level number.
///
/// ```dart
/// LevelBadge(level: 7);
/// LevelBadge(level: 12, size: 72, color: GhinaColors.yellow);
/// ```
class LevelBadge extends StatelessWidget {
  const LevelBadge({
    super.key,
    required this.level,
    this.size = 44,
    this.color = GhinaColors.purple,
  });

  final int level;
  final double size;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Level $level',
      child: SizedBox(
        width: size,
        height: size * 1.08,
        child: CustomPaint(
          painter: _HexPainter(color),
          child: Padding(
            padding: EdgeInsets.only(bottom: size * 0.1),
            child: Center(
              child: Text(
                '$level',
                style: GhinaType.h2
                    .w(900)
                    .copyWith(color: color.on, fontSize: size * 0.42),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter(this.color);

  final ChunkySwatch color;

  Path _hex(Rect r) {
    final c = r.center;
    final rad = r.width / 2;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i - math.pi / 2;
      final pt = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final face = Rect.fromLTWH(0, 0, s, s);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s * 0.14;
    // Edge
    final edgeRect = face.shift(Offset(0, s * 0.08)).deflate(s * 0.08);
    canvas.drawPath(_hex(edgeRect), Paint()..color = color.edge);
    canvas.drawPath(_hex(edgeRect), stroke..color = color.edge);
    // Face
    final f = face.deflate(s * 0.08);
    canvas.drawPath(_hex(f), Paint()..color = color.base);
    canvas.drawPath(_hex(f), stroke..color = color.base);
    // Inner shine ring
    canvas.drawPath(
      _hex(f.deflate(s * 0.1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s * 0.04
        ..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color;
}

/// Gem counter: blue gem + number (bonus currency / freezes).
///
/// ```dart
/// GemCounter(gems: 120);
/// ```
class GemCounter extends StatelessWidget {
  const GemCounter({super.key, required this.gems, this.size = 24});

  final int gems;
  final double size;

  @override
  Widget build(BuildContext context) => StatPill(
    leading: CustomPaint(size: Size.square(size), painter: _GemPainter()),
    value: '$gems',
    color: GhinaColors.blue,
    size: size,
    semanticLabel: '$gems permata',
  );
}

class _GemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outline = Path()
      ..moveTo(w * 0.22, h * 0.14)
      ..lineTo(w * 0.78, h * 0.14)
      ..lineTo(w * 0.98, h * 0.4)
      ..lineTo(w * 0.5, h * 0.92)
      ..lineTo(w * 0.02, h * 0.4)
      ..close();
    canvas.drawPath(outline, Paint()..color = GhinaColors.blue.base);
    final top = Path()
      ..moveTo(w * 0.22, h * 0.14)
      ..lineTo(w * 0.78, h * 0.14)
      ..lineTo(w * 0.98, h * 0.4)
      ..lineTo(w * 0.02, h * 0.4)
      ..close();
    canvas.drawPath(top, Paint()..color = const Color(0xFF84D8FF));
    final facet = Path()
      ..moveTo(w * 0.3, h * 0.4)
      ..lineTo(w * 0.7, h * 0.4)
      ..lineTo(w * 0.5, h * 0.92)
      ..close();
    canvas.drawPath(
      facet,
      Paint()..color = GhinaColors.blue.edge.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      Offset(w * 0.34, h * 0.26),
      w * 0.06,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Top-bar counter: an icon/graphic followed by a bold colored number.
/// Build the Duolingo-style header row from these.
///
/// ```dart
/// Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
///   StatPill(icon: Icons.bolt_rounded, value: '1.240', color: GhinaColors.yellow),
///   StreakFlame(count: 12),
///   GemCounter(gems: 40),
///   StatPill(icon: Icons.favorite_rounded, value: '5', color: GhinaColors.red),
/// ]);
/// ```
class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    this.icon,
    this.leading,
    required this.value,
    required this.color,
    this.size = 24,
    this.onTap,
    this.semanticLabel,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final Widget? leading;
  final String value;
  final ChunkySwatch color;
  final double size;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final w = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading ?? Icon(icon, color: color.base, size: size + 4),
        SizedBox(width: size * 0.2),
        Pulse(
          trigger: value,
          child: Text(
            value,
            style: GhinaType.h3
                .w(900)
                .copyWith(color: color.base, fontSize: size * 0.72),
          ),
        ),
      ],
    );
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: onTap == null
          ? w
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: w,
            ),
    );
  }
}
