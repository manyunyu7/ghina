import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// Rounded, animated progress bar with the glossy "shine" stripe.
/// Lesson progress, budget usage, daily goal.
///
/// ```dart
/// ChunkyProgressBar(value: 0.6);                                     // green
/// ChunkyProgressBar(value: spent / budget, color: GhinaColors.orange, height: 20,
///                   label: 'Rp 600rb / Rp 1jt');
/// ChunkyProgressBar.budget(used: spent / limit);   // auto green→orange→red
/// ```
class ChunkyProgressBar extends StatelessWidget {
  const ChunkyProgressBar({
    super.key,
    required this.value,
    this.color = GhinaColors.green,
    this.height = 16,
    this.label,
    this.animate = true,
    this.trackColor,
  });

  /// Budget bar: green < 75%, orange < 100%, red when over.
  factory ChunkyProgressBar.budget({
    Key? key,
    required double used,
    double height = 16,
    String? label,
  }) {
    final c = used >= 1
        ? GhinaColors.red
        : used >= 0.75
        ? GhinaColors.orange
        : GhinaColors.green;
    return ChunkyProgressBar(
      key: key,
      value: used,
      color: c,
      height: height,
      label: label,
    );
  }

  /// 0..1 (clamped).
  final double value;
  final ChunkySwatch color;
  final double height;

  /// Text drawn centered inside the bar (use height >= 20).
  final String? label;
  final bool animate;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    Widget bar(double t) => CustomPaint(
      size: Size(double.infinity, height),
      painter: _BarPainter(
        value: t,
        color: color,
        track: trackColor ?? g.border,
      ),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: label == null
            ? null
            : Center(
                child: Text(
                  label!,
                  maxLines: 1,
                  style: GhinaType.caption
                      .w(900)
                      .copyWith(
                        color: t > 0.5 ? color.on : g.textSecondary,
                        fontSize: math.min(13, height * 0.6),
                      ),
                ),
              ),
      ),
    );

    return Semantics(
      value: '${(v * 100).round()}%',
      child: animate
          ? TweenAnimationBuilder<double>(
              tween: Tween(end: v),
              duration: GhinaMotion.progress,
              curve: GhinaMotion.standard,
              builder: (_, t, _) => bar(t),
            )
          : bar(v),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.value, required this.color, required this.track});

  final double value;
  final ChunkySwatch color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    if (value <= 0) return;
    final w = math.max(size.height, size.width * value);
    final fill = Rect.fromLTWH(0, 0, w, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, r),
      Paint()..color = color.base,
    );
    // Shine: a lighter pill along the top third.
    final sh = size.height * 0.26;
    final inset = size.height * 0.36;
    if (w > inset * 2 + sh) {
      final shine = Rect.fromLTWH(inset, size.height * 0.2, w - inset * 2, sh);
      canvas.drawRRect(
        RRect.fromRectAndRadius(shine, Radius.circular(sh / 2)),
        Paint()..color = Colors.white.withValues(alpha: 0.32),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Circular progress ring with rounded caps – the daily goal ring. Put any
/// widget (mascot, icon, number) in the middle.
///
/// ```dart
/// ProgressRing(
///   value: todayXp / goalXp,
///   size: 132,
///   child: Column(mainAxisSize: MainAxisSize.min, children: [
///     Text('30', style: GhinaType.h1), Text('/ 50 XP'),
///   ]),
/// );
/// ```
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 12,
    this.color = GhinaColors.yellow,
    this.child,
    this.animate = true,
  });

  final double value;
  final double size;
  final double stroke;
  final ChunkySwatch color;
  final Widget? child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    Widget ring(double t) => CustomPaint(
      painter: _RingPainter(
        value: t,
        color: color,
        track: g.border,
        stroke: stroke,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
    return Semantics(
      value: '${(v * 100).round()}%',
      child: animate
          ? TweenAnimationBuilder<double>(
              tween: Tween(end: v),
              duration: GhinaMotion.progress,
              curve: GhinaMotion.standard,
              builder: (_, t, _) => ring(t),
            )
          : ring(v),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final ChunkySwatch color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, radius, base..color = track);
    if (value <= 0) return;
    final sweep = 2 * math.pi * value;
    // Edge (darker, offset down) then face – the chunky look.
    canvas.drawArc(
      rect.shift(const Offset(0, 2.5)),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.edge,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.base,
    );
    // Shine on the arc.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius + stroke * 0.18),
      -math.pi / 2 + 0.12,
      math.max(0, sweep - 0.24),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.22
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
