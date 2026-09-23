import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_button.dart';
import 'chunky_surface.dart';

/// Visual state of a quiz answer.
enum QuizOptionState { idle, selected, correct, wrong, disabled }

/// Quiz answer card (lessons). Selected = blue tint; after checking, show
/// [QuizOptionState.correct] (green) or [QuizOptionState.wrong] (red, shakes).
///
/// ```dart
/// QuizOptionTile(
///   label: 'Dana darurat',
///   index: 1,                         // shows a "1" key badge
///   state: selected == 1 ? QuizOptionState.selected : QuizOptionState.idle,
///   onTap: () => setState(() => selected = 1),
/// );
/// ```
class QuizOptionTile extends StatelessWidget {
  const QuizOptionTile({
    super.key,
    required this.label,
    required this.state,
    this.onTap,
    this.index,
    this.icon,
  });

  final String label;
  final QuizOptionState state;
  final VoidCallback? onTap;
  final int? index;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final b = g.brightness;
    final ChunkySwatch? sw = switch (state) {
      QuizOptionState.selected => GhinaColors.blue,
      QuizOptionState.correct => GhinaColors.green,
      QuizOptionState.wrong => GhinaColors.red,
      _ => null,
    };
    final face = sw?.tint(b) ?? g.surface;
    final border = sw?.tintBorder(b) ?? g.border;
    final fg = state == QuizOptionState.disabled
        ? g.textMuted
        : (sw == null ? g.textPrimary : (g.isDark ? sw.base : sw.edge));

    final tile = ChunkySurface(
      color: face,
      edgeColor: sw == null ? g.borderEdge : border,
      borderColor: border,
      depth: GhinaDepth.md,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabled: state != QuizOptionState.disabled,
      onTap: onTap,
      semanticLabel: label,
      child: Row(
        children: [
          if (index != null) ...[
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: GhinaRadii.rSm,
                border: Border.all(color: border, width: 2),
              ),
              child: Text(
                '$index',
                style: GhinaType.body
                    .w(900)
                    .copyWith(color: sw == null ? g.textMuted : fg),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (icon != null) ...[
            Icon(icon, color: fg),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: GhinaType.bodyL.w(800).copyWith(color: fg),
            ),
          ),
          if (state == QuizOptionState.correct)
            PopIn(
              child: Icon(
                Icons.check_circle_rounded,
                color: GhinaColors.green.base,
                size: 26,
              ),
            ),
          if (state == QuizOptionState.wrong)
            PopIn(
              child: Icon(
                Icons.cancel_rounded,
                color: GhinaColors.red.base,
                size: 26,
              ),
            ),
        ],
      ),
    );
    return Shake(
      trigger: state == QuizOptionState.wrong ? state : null,
      child: tile,
    );
  }
}

/// Bottom feedback banner after checking an answer ("Benar!" / "Kurang
/// tepat"). Slides up; place at the bottom of the lesson screen.
///
/// ```dart
/// AnswerFeedbackBar(
///   correct: false,
///   message: 'Jawaban yang benar: Dana darurat',
///   onContinue: next,
/// );
/// ```
class AnswerFeedbackBar extends StatelessWidget {
  const AnswerFeedbackBar({
    super.key,
    required this.correct,
    required this.onContinue,
    this.title,
    this.message,
    this.buttonLabel,
  });

  final bool correct;
  final VoidCallback onContinue;

  /// Defaults: "Mantap, benar!" / "Kurang tepat".
  final String? title;
  final String? message;

  /// Defaults: "Lanjut" / "Oke, paham".
  final String? buttonLabel;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = correct ? GhinaColors.green : GhinaColors.red;
    final fg = g.isDark ? sw.base : sw.edge;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: GhinaMotion.medium,
      curve: GhinaMotion.standard,
      builder: (_, t, child) =>
          FractionalTranslation(translation: Offset(0, t), child: child),
      child: Container(
        width: double.infinity,
        color: sw.tint(g.brightness),
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          18 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                PopIn(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: g.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      correct ? Icons.check_rounded : Icons.close_rounded,
                      color: sw.base,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title ?? (correct ? 'Mantap, benar!' : 'Kurang tepat'),
                  style: GhinaType.h2.w(900).copyWith(color: fg),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: GhinaType.body.w(700).copyWith(color: fg)),
            ],
            const SizedBox(height: 14),
            ChunkyButton(
              label: buttonLabel ?? (correct ? 'Lanjut' : 'Oke, paham'),
              variant: correct
                  ? ChunkyButtonVariant.primary
                  : ChunkyButtonVariant.danger,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

/// State of a lesson node on the learning path.
enum PathNodeState { locked, available, current, completed }

/// Round chunky lesson node for the Duolingo-style path. The current node
/// floats, shows a progress ring and a "MULAI" bubble.
///
/// ```dart
/// PathNode(state: PathNodeState.current, icon: Icons.savings_rounded, progress: 0.4, onTap: open);
/// PathNode(state: PathNodeState.completed, icon: Icons.check_rounded, onTap: review);
/// PathNode(state: PathNodeState.locked, icon: Icons.lock_rounded);
/// ```
class PathNode extends StatelessWidget {
  const PathNode({
    super.key,
    required this.state,
    required this.icon,
    this.onTap,
    this.progress = 0,
    this.color = GhinaColors.green,
    this.size = 72,
    this.bubbleLabel = 'Mulai',
  });

  final PathNodeState state;
  final IconData icon;
  final VoidCallback? onTap;

  /// Ring progress for the current node (0..1).
  final double progress;
  final ChunkySwatch color;
  final double size;
  final String bubbleLabel;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final locked = state == PathNodeState.locked;
    final sw = state == PathNodeState.completed ? GhinaColors.yellow : color;
    final face = locked ? g.disabled : sw.base;
    final edge = locked ? g.disabledEdge : sw.edge;
    final fg = locked ? g.onDisabled : Colors.white;

    Widget node = ChunkySurface(
      color: face,
      edgeColor: edge,
      depth: 8,
      borderRadius: BorderRadius.all(Radius.elliptical(size / 2, size * 0.46)),
      onTap: locked ? null : onTap,
      semanticLabel: switch (state) {
        PathNodeState.locked => 'Terkunci',
        PathNodeState.completed => 'Selesai',
        PathNodeState.current => bubbleLabel,
        PathNodeState.available => 'Tersedia',
      },
      child: SizedBox(
        width: size,
        height: size * 0.9,
        child: Icon(
          state == PathNodeState.completed
              ? Icons.check_rounded
              : (locked ? Icons.lock_rounded : icon),
          color: fg,
          size: size * 0.45,
        ),
      ),
    );

    if (state != PathNodeState.current) return node;

    final ring = size + 26;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Bounce(
          child: _StartBubble(label: bubbleLabel, color: sw),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: ring,
          height: ring,
          child: CustomPaint(
            painter: _NodeRingPainter(
              progress: progress,
              color: sw.base,
              track: g.border,
            ),
            child: Center(child: node),
          ),
        ),
      ],
    );
  }
}

class _StartBubble extends StatelessWidget {
  const _StartBubble({required this.label, required this.color});

  final String label;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: g.surface,
            borderRadius: GhinaRadii.rMd,
            border: Border.all(color: g.border, width: 2),
          ),
          child: Text(
            label.toUpperCase(),
            style: GhinaType.button.copyWith(color: color.base),
          ),
        ),
        CustomPaint(
          size: const Size(16, 8),
          painter: _TailPainter(g.surface, g.border),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.fill, this.border);

  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, -2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, -2);
    canvas.drawPath(p, Paint()..color = fill);
    canvas.drawPath(
      p,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.fill != fill || old.border != border;
}

class _NodeRingPainter extends CustomPainter {
  _NodeRingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - stroke / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0, 1),
        false,
        p..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_NodeRingPainter old) =>
      old.progress != progress || old.color != color;
}
