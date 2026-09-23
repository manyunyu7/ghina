import 'package:flutter/material.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'mascot_painter.dart';

export 'mascot_painter.dart' show MascotMood;

/// Ghina the mascot, animated (idle bounce, blink, wave, sparkles, Zzz).
///
/// ```dart
/// const MascotView(mood: MascotMood.waving, size: 160);
/// MascotView(mood: overBudget ? MascotMood.sad : MascotMood.happy);
/// const MascotView(mood: MascotMood.excited, animate: false); // static
/// ```
///
/// Changing [mood] pops the mascot with a quick squash.
class MascotView extends StatefulWidget {
  const MascotView({
    super.key,
    this.mood = MascotMood.happy,
    this.size = 120,
    this.animate = true,
    this.showShadow = true,
    this.color,
    this.semanticLabel = 'Ghina',
  });

  final MascotMood mood;
  final double size;
  final bool animate;
  final bool showShadow;

  /// Optional recolor (defaults to leaf green).
  final ChunkySwatch? color;
  final String semanticLabel;

  @override
  State<MascotView> createState() => _MascotViewState();
}

class _MascotViewState extends State<MascotView> with TickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  );
  late final _pop = AnimationController(
    vsync: this,
    duration: GhinaMotion.slow,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _loop.repeat();
  }

  @override
  void didUpdateWidget(covariant MascotView old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_loop.isAnimating) _loop.repeat();
    if (!widget.animate && _loop.isAnimating) _loop.stop();
    if (old.mood != widget.mood && widget.animate) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final shadow = widget.showShadow
        ? (g.isDark
              ? Colors.black.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.08))
        : null;
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_loop, _pop]),
          builder: (context, _) {
            final p = GhinaMotion.bounce.transform(_pop.value.clamp(0.0, 1.0));
            return Transform.scale(
              scale: 0.85 + 0.15 * p,
              alignment: Alignment.bottomCenter,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: MascotPainter(
                  mood: widget.mood,
                  phase: _loop.value,
                  color: widget.color ?? GhinaColors.green,
                  shadowColor: shadow,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Mascot + speech bubble – for tips, greetings, encouragement.
///
/// ```dart
/// MascotSpeech(
///   mood: MascotMood.waving,
///   message: 'Halo! Yuk catat pengeluaran pertamamu hari ini 💪',
/// );
/// MascotSpeech(mood: MascotMood.thinking, title: 'Tips', message: '...', mascotSize: 80);
/// ```
class MascotSpeech extends StatelessWidget {
  const MascotSpeech({
    super.key,
    required this.message,
    this.title,
    this.mood = MascotMood.happy,
    this.mascotSize = 96,
    this.bubbleColor,
    this.action,
  });

  final String message;
  final String? title;
  final MascotMood mood;
  final double mascotSize;

  /// Tinted bubble (e.g. `GhinaColors.blue`); null = neutral.
  final ChunkySwatch? bubbleColor;

  /// Optional widget under the text (e.g. a small ChunkyButton).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final fill = bubbleColor?.tint(g.brightness) ?? g.surface;
    final border = bubbleColor?.tintBorder(g.brightness) ?? g.border;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        MascotView(mood: mood, size: mascotSize),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: mascotSize * 0.3),
            child: CustomPaint(
              painter: _BubblePainter(fill: fill, border: border),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: GhinaType.h3
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: GhinaType.body
                          .w(700)
                          .copyWith(color: g.textPrimary),
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 10),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.fill, required this.border});

  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    const tail = 12.0;
    const r = 18.0;
    final body = RRect.fromLTRBR(
      tail,
      0,
      size.width,
      size.height,
      const Radius.circular(r),
    );
    final path = Path()..addRRect(body);
    final ty = size.height - 26;
    final t = Path()
      ..moveTo(tail + 1, ty - 10)
      ..lineTo(0, ty + 6)
      ..lineTo(tail + 1, ty + 6)
      ..close();
    final shape = Path.combine(PathOperation.union, path, t);
    canvas.drawPath(shape, Paint()..color = fill);
    canvas.drawPath(
      shape,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fill != fill || old.border != border;
}
