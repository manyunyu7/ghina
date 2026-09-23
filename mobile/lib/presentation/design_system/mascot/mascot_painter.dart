import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/typography.dart';
import '../tokens/colors.dart';

/// Ghina's moods.
enum MascotMood {
  /// Default friendly smile.
  happy,

  /// Arms up, ^^ eyes, sparkles – rewards, streaks, goals met.
  excited,

  /// Looking up, hand on chin, thought bubbles – tips, loading, quizzes.
  thinking,

  /// Droopy ears, frown, tear – over budget, lost streak, errors.
  sad,

  /// Closed eyes, Zzz – empty states, nothing today, night.
  sleeping,

  /// Waving arm – greetings, onboarding, login.
  waving,
}

/// Paints "Ghina": an original round green piggy-bank creature with a
/// sprout growing from its coin slot (savings that grow!).
///
/// Drawn in a 200×200 design box, scaled to the canvas. [phase] (0..1,
/// looping) drives idle bounce, blinking, waving, sparkles and Zzz.
class MascotPainter extends CustomPainter {
  MascotPainter({
    required this.mood,
    this.phase = 0,
    this.color = GhinaColors.green,
    this.shadowColor,
  });

  final MascotMood mood;
  final double phase;
  final ChunkySwatch color;

  /// Ground shadow color (theme-aware). Null = no ground shadow.
  final Color? shadowColor;

  static const _ink = Color(0xFF3C3C3C);
  static const _snout = Color(0xFFFFB8DF);
  static const _snoutEdge = Color(0xFFF08DC5);
  static const _nostril = Color(0xFFC95A9C);
  static const _cheek = Color(0xFFFF86D0);
  static const _blush = Color(0xFFFFA3DA);
  static const _mouth = Color(0xFF8C2F39);
  static const _tongue = Color(0xFFFF7A8A);
  static const _leaf = Color(0xFF89E219);
  static const _leafEdge = Color(0xFF5BA80F);
  static const _belly = Color(0xFF7BDA1A);

  double get _t => phase * 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 200;
    canvas.save();
    canvas.translate((size.width - 200 * s) / 2, (size.height - 200 * s) / 2);
    canvas.scale(s);

    // --- idle motion -------------------------------------------------------
    double lift = 0, sx = 1, sy = 1;
    switch (mood) {
      case MascotMood.sleeping:
        final b = math.sin(_t);
        sy = 1 + 0.025 * b;
        sx = 1 - 0.012 * b;
      case MascotMood.excited:
        final b = math.sin(_t * 4).abs();
        lift = 14 * b;
        sy = 1 + 0.05 * (b - 0.5);
        sx = 1 - 0.04 * (b - 0.5);
      default:
        final b = math.sin(_t * 2);
        lift = 3 + 3 * b;
        sy = 1 + 0.018 * b;
        sx = 1 - 0.014 * b;
    }

    // Ground shadow (shrinks while airborne).
    if (shadowColor != null) {
      final k = 1 - lift / 40;
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(100, 194),
          width: 118 * k,
          height: 12 * k,
        ),
        Paint()..color = shadowColor!,
      );
    }

    canvas.save();
    canvas.translate(100, 190 - lift);
    canvas.scale(sx, sy);
    canvas.translate(-100, -190);
    canvas.translate(0, -4);

    _drawBackArms(canvas);
    _drawFeet(canvas);
    _drawEars(canvas);
    _drawBody(canvas);
    _drawSprout(canvas);
    _drawFace(canvas);
    canvas.restore();

    _drawExtras(canvas);
    canvas.restore();
  }

  // ---- body parts -----------------------------------------------------------

  void _drawBody(Canvas canvas) {
    const body = Rect.fromLTRB(24, 48, 176, 186);
    final rr = RRect.fromRectAndRadius(body, const Radius.elliptical(72, 66));
    canvas.drawRRect(rr.shift(const Offset(0, 7)), Paint()..color = color.edge);
    canvas.drawRRect(rr, Paint()..color = color.base);
    // Belly
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 176), width: 118, height: 80),
      Paint()..color = _belly,
    );
    canvas.restore();
    // Top-left shine
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(52, 84), width: 20, height: 30),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
    // Coin slot
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(100, 60), width: 34, height: 8),
        const Radius.circular(4),
      ),
      Paint()..color = color.edge,
    );
  }

  void _drawEars(Canvas canvas) {
    final droop = mood == MascotMood.sad
        ? 0.5
        : (mood == MascotMood.sleeping ? 0.25 : 0.0);
    final perk = mood == MascotMood.excited
        ? math.sin(_t * 4).abs() * 0.12
        : 0.0;
    for (final left in [true, false]) {
      final dir = left ? -1.0 : 1.0;
      canvas.save();
      canvas.translate(100 + dir * 44, 64);
      canvas.rotate(dir * (droop - perk));
      final ear = Path()
        ..moveTo(-dir * 18, 8)
        ..quadraticBezierTo(dir * 2, -40, dir * 22, -30)
        ..quadraticBezierTo(dir * 30, -6, dir * 20, 12)
        ..close();
      canvas.drawPath(ear, Paint()..color = color.base);
      canvas.drawPath(
        ear,
        Paint()
          ..color = color.base
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeJoin = StrokeJoin.round,
      );
      final inner = Path()
        ..moveTo(-dir * 6, 2)
        ..quadraticBezierTo(dir * 6, -26, dir * 18, -20)
        ..quadraticBezierTo(dir * 22, -6, dir * 14, 6)
        ..close();
      canvas.drawPath(inner, Paint()..color = _cheek.withValues(alpha: 0.85));
      canvas.restore();
    }
  }

  void _drawSprout(Canvas canvas) {
    final sway = math.sin(_t * 2) * 0.12 + (mood == MascotMood.sad ? 0.5 : 0);
    canvas.save();
    canvas.translate(100, 60);
    canvas.rotate(sway);
    final stem = Paint()
      ..color = _leafEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(-2, -12, 1, -24),
      stem,
    );
    void leaf(Offset c, double angle, double w, double h) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle);
      final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      final p = Path()
        ..moveTo(r.left, 0)
        ..quadraticBezierTo(0, r.top - h * 0.4, r.right, 0)
        ..quadraticBezierTo(0, r.bottom + h * 0.4, r.left, 0)
        ..close();
      canvas.drawPath(p.shift(const Offset(0, 2)), Paint()..color = _leafEdge);
      canvas.drawPath(p, Paint()..color = _leaf);
      canvas.drawLine(
        Offset(r.left + 4, 0),
        Offset(r.right - 6, 0),
        Paint()
          ..color = _leafEdge.withValues(alpha: 0.6)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }

    leaf(const Offset(-11, -24), -0.45, 24, 13);
    leaf(const Offset(13, -30), 0.5, 28, 15);
    canvas.restore();
  }

  void _drawFeet(Canvas canvas) {
    final p = Paint()..color = color.edge;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(70, 190), width: 38, height: 18),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(130, 190), width: 38, height: 18),
      p,
    );
  }

  void _arm(
    Canvas canvas,
    Offset shoulder,
    double angle, {
    bool front = false,
  }) {
    canvas.save();
    canvas.translate(shoulder.dx, shoulder.dy);
    canvas.rotate(angle);
    final rr = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-11, -4, 22, 40),
      const Radius.circular(11),
    );
    if (front) {
      canvas.drawRRect(
        rr.shift(const Offset(0, 2)),
        Paint()..color = color.edge,
      );
    }
    canvas.drawRRect(rr, Paint()..color = front ? color.base : color.edge);
    if (!front) {
      canvas.drawRRect(rr.deflate(3), Paint()..color = color.base);
    }
    canvas.restore();
  }

  static const _lShoulder = Offset(34, 118);
  static const _rShoulder = Offset(166, 118);

  void _drawBackArms(Canvas canvas) {
    switch (mood) {
      case MascotMood.excited:
        final w = math.sin(_t * 8) * 0.18;
        _arm(canvas, _lShoulder.translate(0, -8), 2.5 + w);
        _arm(canvas, _rShoulder.translate(0, -8), -2.5 - w);
      case MascotMood.waving:
        _arm(canvas, _lShoulder, 0.55);
        _arm(
          canvas,
          _rShoulder.translate(0, -6),
          -2.45 + math.sin(_t * 6) * 0.38,
        );
      case MascotMood.thinking:
        _arm(canvas, _lShoulder, 0.55);
        _arm(
          canvas,
          _rShoulder.translate(-2, -10),
          -2.3 + math.sin(_t * 2) * 0.08,
        );
      case MascotMood.sad:
        _arm(canvas, _lShoulder, 0.25);
        _arm(canvas, _rShoulder, -0.25);
      case MascotMood.sleeping:
        _arm(canvas, _lShoulder, 0.35);
        _arm(canvas, _rShoulder, -0.35);
      case MascotMood.happy:
        final w = math.sin(_t * 2) * 0.06;
        _arm(canvas, _lShoulder, 0.6 + w);
        _arm(canvas, _rShoulder, -0.6 - w);
    }
  }

  // ---- face -------------------------------------------------------------------

  double get _blink {
    // Quick blink twice per loop.
    double b(double center) {
      final d = (phase - center).abs();
      return d < 0.025 ? d / 0.025 : 1;
    }

    return math.min(b(0.42), b(0.9));
  }

  void _drawFace(Canvas canvas) {
    const le = Offset(72, 104), re = Offset(128, 104);

    // Cheeks
    final cheek = Paint()
      ..color = _blush.withValues(alpha: mood == MascotMood.sad ? 0.8 : 0.95);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(46, 132), width: 24, height: 14),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(154, 132), width: 24, height: 14),
      cheek,
    );

    switch (mood) {
      case MascotMood.excited:
        _arcEye(canvas, le, up: true);
        _arcEye(canvas, re, up: true);
      case MascotMood.sleeping:
        _arcEye(canvas, le.translate(0, 4), up: false);
        _arcEye(canvas, re.translate(0, 4), up: false);
      case MascotMood.thinking:
        _openEye(canvas, le, const Offset(5, -8), _blink);
        _openEye(canvas, re, const Offset(5, -8), _blink);
      case MascotMood.sad:
        _openEye(canvas, le, const Offset(-1, 6), _blink, lid: true);
        _openEye(canvas, re, const Offset(1, 6), _blink, lid: true);
        _brows(canvas, le, re);
      case MascotMood.happy:
      case MascotMood.waving:
        _openEye(canvas, le, const Offset(1, 2), _blink);
        _openEye(canvas, re, const Offset(-1, 2), _blink);
    }

    _drawSnout(canvas);
    _drawMouth(canvas);

    if (mood == MascotMood.sad) {
      // Tear
      final y = 124 + (phase * 2 % 1) * 18;
      final tear = Path()
        ..moveTo(58, y - 10)
        ..quadraticBezierTo(51, y, 58, y + 5)
        ..quadraticBezierTo(65, y, 58, y - 10)
        ..close();
      canvas.drawPath(
        tear,
        Paint()..color = GhinaColors.blue.base.withValues(alpha: 0.9),
      );
    }
  }

  void _openEye(
    Canvas canvas,
    Offset c,
    Offset look,
    double open, {
    bool lid = false,
  }) {
    final h = 38 * math.max(open, 0.08).toDouble();
    final eye = Rect.fromCenter(center: c, width: 32, height: h);
    canvas.drawOval(
      eye.shift(const Offset(0, 2)),
      Paint()..color = color.edge.withValues(alpha: 0.35),
    );
    canvas.drawOval(eye, Paint()..color = Colors.white);
    if (open < 0.3) return;
    canvas.save();
    canvas.clipPath(Path()..addOval(eye));
    final pc = c + look;
    canvas.drawCircle(pc, 11, Paint()..color = _ink);
    canvas.drawCircle(
      pc + const Offset(-4, -5),
      4.2,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      pc + const Offset(4, 4),
      1.8,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
    if (lid) {
      canvas.drawRect(
        Rect.fromLTWH(eye.left, eye.top, eye.width, h * 0.28),
        Paint()..color = color.base,
      );
    }
    canvas.restore();
  }

  void _arcEye(Canvas canvas, Offset c, {required bool up}) {
    final p = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(c.dx - 13, c.dy + (up ? 5 : -2))
      ..quadraticBezierTo(
        c.dx,
        c.dy + (up ? -14 : 12),
        c.dx + 13,
        c.dy + (up ? 5 : -2),
      );
    canvas.drawPath(path, p);
  }

  void _brows(Canvas canvas, Offset le, Offset re) {
    final p = Paint()
      ..color = color.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(le.translate(-14, -22), le.translate(10, -30), p);
    canvas.drawLine(re.translate(14, -22), re.translate(-10, -30), p);
  }

  void _drawSnout(Canvas canvas) {
    final r = Rect.fromCenter(
      center: const Offset(100, 132),
      width: 48,
      height: 32,
    );
    canvas.drawOval(r.shift(const Offset(0, 3)), Paint()..color = _snoutEdge);
    canvas.drawOval(r, Paint()..color = _snout);
    final n = Paint()..color = _nostril;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(91, 132), width: 7, height: 11),
      n,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(109, 132), width: 7, height: 11),
      n,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(90, 123), width: 10, height: 4),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _drawMouth(Canvas canvas) {
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case MascotMood.happy:
      case MascotMood.waving:
      case MascotMood.excited:
        final big = mood == MascotMood.excited;
        final w = big ? 17.0 : 12.0;
        final d = big ? 22.0 : 15.0;
        final top = 152.0;
        final mouth = Path()
          ..moveTo(100 - w, top)
          ..quadraticBezierTo(100, top - 2, 100 + w, top)
          ..quadraticBezierTo(100 + w * 0.9, top + d, 100, top + d)
          ..quadraticBezierTo(100 - w * 0.9, top + d, 100 - w, top)
          ..close();
        canvas.drawPath(mouth, Paint()..color = _mouth);
        canvas.save();
        canvas.clipPath(mouth);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(100, top + d),
            width: w * 1.5,
            height: d * 0.9,
          ),
          Paint()..color = _tongue,
        );
        canvas.restore();
      case MascotMood.thinking:
        canvas.drawPath(
          Path()
            ..moveTo(86, 157)
            ..quadraticBezierTo(94, 153, 102, 156),
          stroke,
        );
      case MascotMood.sad:
        canvas.drawPath(
          Path()
            ..moveTo(88, 160)
            ..quadraticBezierTo(100, 149, 112, 160),
          stroke,
        );
      case MascotMood.sleeping:
        final o = 1 + 0.25 * math.sin(_t);
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(100, 157),
            width: 9 * o,
            height: 11 * o,
          ),
          Paint()..color = _mouth,
        );
    }
  }

  // ---- extras (not bouncing with the body) -------------------------------------

  void _drawExtras(Canvas canvas) {
    switch (mood) {
      case MascotMood.excited:
        _sparkle(canvas, const Offset(20, 46), 16, 0);
        _sparkle(canvas, const Offset(184, 74), 13, 0.33);
        _sparkle(canvas, const Offset(170, 16), 11, 0.66);
        _sparkle(canvas, const Offset(12, 132), 10, 0.5);
      case MascotMood.thinking:
        final bob = math.sin(_t * 2) * 2;
        final p = Paint()
          ..color = GhinaColors.blue.base.withValues(alpha: 0.85);
        canvas.drawCircle(Offset(160, 44 + bob), 5, p);
        canvas.drawCircle(Offset(172, 28 + bob), 7, p);
        canvas.drawCircle(Offset(188, 10 + bob), 9, p);
      case MascotMood.sleeping:
        for (var i = 0; i < 3; i++) {
          final k = (phase + i / 3) % 1;
          final fade = k < 0.2 ? k / 0.2 : (1 - k);
          _z(
            canvas,
            Offset(166 + k * 20, 70 - k * 58),
            18 + k * 12,
            0.35 + 0.65 * fade,
          );
        }
      default:
        break;
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, double offset) {
    final k = 0.6 + 0.4 * math.sin((phase + offset) * 2 * math.pi * 2);
    final rr = r * k;
    final p = Path()
      ..moveTo(c.dx, c.dy - rr)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + rr, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + rr)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - rr, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - rr)
      ..close();
    canvas.drawPath(p, Paint()..color = GhinaColors.yellow.base);
  }

  void _z(Canvas canvas, Offset at, double size, double opacity) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'z',
        style: GhinaType.nunito(
          size,
          weight: 900,
          color: GhinaColors.blue.base.withValues(
            alpha: opacity.clamp(0.0, 1.0),
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(MascotPainter old) =>
      old.phase != phase ||
      old.mood != mood ||
      old.color != color ||
      old.shadowColor != shadowColor;
}
