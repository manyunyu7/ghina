import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/typography.dart';
import '../tokens/colors.dart';

/// Ghina's moods.
enum MascotMood {
  /// Default friendly smile.
  happy,

  /// Branches up, ^^ eyes, sparkles and coins popping – rewards, streaks,
  /// goals met.
  excited,

  /// Looking up, twig on chin, thought bubbles – tips, loading, quizzes.
  thinking,

  /// Drooping crown, frown, tear, a leaf and a coin falling – over budget,
  /// lost streak, errors.
  sad,

  /// Closed eyes, relaxed crown, Zzz – empty states, nothing today, night.
  sleeping,

  /// Waving branch – greetings, onboarding, login.
  waving,
}

/// Paints "Ghina": an original little money tree – a big round leafy crown
/// (with the face) on a sturdy bark trunk, twig arms, root feet and gold-coin
/// fruits (savings that grow!).
///
/// Drawn in a 200×200 design box, scaled to the canvas. [phase] (0..1,
/// looping) drives the crown sway, blinking, waving, sparkles and Zzz.
/// [color] recolors the crown (defaults to leaf green).
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
  static const _blush = Color(0xFFFF9CC9);
  static const _mouth = Color(0xFF8C2F39);
  static const _tongue = Color(0xFFFF7A8A);
  static const _bark = GhinaColors.bark;
  static const _coin = GhinaColors.yellow;

  /// Where the crown sits on the trunk (sway / droop pivot).
  static const _crownPivot = Offset(100, 132);
  static const _lShoulder = Offset(90, 147);
  static const _rShoulder = Offset(110, 147);

  double get _t => phase * 2 * math.pi;

  /// Lighter leaf tone for tufts and leaf hands.
  Color get _leafHi => color == GhinaColors.green
      ? GhinaColors.lime.base
      : Color.lerp(color.base, Colors.white, 0.3)!;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 200;
    canvas.save();
    canvas.translate((size.width - 200 * s) / 2, (size.height - 200 * s) / 2);
    canvas.scale(s);

    // --- idle motion ---------------------------------------------------------
    // Trees are rooted: the body only squashes a little (and hops when
    // excited); the crown sways on top of the trunk.
    double lift = 0, sx = 1, sy = 1, sway, droop = 1;
    switch (mood) {
      case MascotMood.sleeping:
        final b = math.sin(_t);
        sy = 1 + 0.02 * b;
        sx = 1 - 0.01 * b;
        sway = 0.02 * math.sin(_t);
      case MascotMood.excited:
        final b = math.sin(_t * 4).abs();
        lift = 12 * b;
        sy = 1 + 0.05 * (b - 0.5);
        sx = 1 - 0.04 * (b - 0.5);
        sway = 0.05 * math.sin(_t * 8);
      case MascotMood.sad:
        sway = -0.05 + 0.015 * math.sin(_t);
        droop = 0.93;
      case MascotMood.thinking:
        sway = 0.04 + 0.015 * math.sin(_t * 2);
      case MascotMood.happy:
      case MascotMood.waving:
        final b = math.sin(_t * 2);
        sy = 1 + 0.012 * b;
        sx = 1 - 0.008 * b;
        sway = 0.035 * math.sin(_t * 2);
    }

    // Ground shadow (shrinks while airborne).
    if (shadowColor != null) {
      final k = 1 - lift / 40;
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(100, 193),
          width: 112 * k,
          height: 12 * k,
        ),
        Paint()..color = shadowColor!,
      );
    }
    if (mood == MascotMood.sad) _drawFallenCoin(canvas);

    canvas.save();
    canvas.translate(100, 190 - lift);
    canvas.scale(sx, sy);
    canvas.translate(-100, -190);

    _drawRoots(canvas);
    _drawTrunk(canvas);

    canvas.save();
    canvas.translate(_crownPivot.dx, _crownPivot.dy);
    canvas.rotate(sway);
    canvas.scale(1, droop);
    canvas.translate(-_crownPivot.dx, -_crownPivot.dy);
    _drawCrown(canvas);
    _drawFace(canvas);
    canvas.restore();

    _drawArms(canvas);
    canvas.restore();

    _drawExtras(canvas);
    canvas.restore();
  }

  // ---- tree parts -------------------------------------------------------------

  void _drawRoots(Canvas canvas) {
    final p = Paint()..color = _bark.edge;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(76, 187), width: 36, height: 15),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(124, 187), width: 36, height: 15),
      p,
    );
  }

  static final Path _trunk = Path()
    ..moveTo(82, 188)
    ..quadraticBezierTo(90, 166, 88, 124)
    ..lineTo(112, 124)
    ..quadraticBezierTo(110, 166, 118, 188)
    ..quadraticBezierTo(100, 192, 82, 188)
    ..close();

  void _drawTrunk(Canvas canvas) {
    canvas.drawPath(_trunk, Paint()..color = _bark.base);
    canvas.save();
    canvas.clipPath(_trunk);
    // Right-side shade + a couple of bark lines.
    canvas.drawRect(
      const Rect.fromLTWH(105, 120, 20, 72),
      Paint()..color = _bark.edge.withValues(alpha: 0.55),
    );
    final line = Paint()
      ..color = _bark.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(95, 158)
        ..quadraticBezierTo(93, 166, 95, 174),
      line,
    );
    canvas.restore();
  }

  /// The crown: overlapping leafy blobs with a darker bottom edge.
  static final Path _crown = _union(const [
    (100, 78, 56),
    (58, 98, 33),
    (142, 98, 33),
    (72, 50, 31),
    (128, 50, 31),
    (100, 40, 31),
  ]);

  static Path _union(List<(double, double, double)> circles) {
    Path? p;
    for (final (x, y, r) in circles) {
      final c = Path()
        ..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
      p = p == null ? c : Path.combine(PathOperation.union, p, c);
    }
    return p!;
  }

  void _drawCrown(Canvas canvas) {
    canvas.drawPath(
      _crown.shift(const Offset(0, 9)),
      Paint()..color = color.edge,
    );
    canvas.drawPath(_crown, Paint()..color = color.base);

    // Leaf rustle: highlight tufts shimmer a little.
    final r = mood == MascotMood.sleeping ? 0.0 : math.sin(_t * 4) * 0.6;
    final hi = Paint()..color = _leafHi;
    canvas.drawCircle(Offset(84, 22 + r), 9, hi);
    canvas.drawCircle(Offset(64, 36 - r), 6.5, hi);
    canvas.drawCircle(const Offset(46, 80), 4.5, hi);

    // A few leaf-cluster curls for texture.
    final curl = Paint()
      ..color = color.edge.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    void u(Offset c, double w) => canvas.drawPath(
      Path()
        ..moveTo(c.dx - w, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + w * 0.9, c.dx + w, c.dy),
      curl,
    );
    u(const Offset(132, 30), 7);
    u(const Offset(40, 114), 6);
    u(const Offset(160, 116), 6);

    // Gold-coin fruits (one falls off when sad).
    _drawCoin(canvas, const Offset(46, 62), 11);
    if (mood != MascotMood.sad) _drawCoin(canvas, const Offset(158, 72), 10);
  }

  void _drawCoin(Canvas canvas, Offset c, double r, {double opacity = 1}) {
    Color a(Color x) => x.withValues(alpha: x.a * opacity);
    canvas.drawCircle(
      c.translate(0, r * 0.28),
      r,
      Paint()..color = a(_coin.edge),
    );
    canvas.drawCircle(c, r, Paint()..color = a(_coin.base));
    canvas.drawCircle(
      c,
      r * 0.56,
      Paint()
        ..color = a(_coin.edge)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.18,
    );
    canvas.drawCircle(
      c.translate(-r * 0.38, -r * 0.42),
      r * 0.2,
      Paint()..color = a(Colors.white.withValues(alpha: 0.85)),
    );
  }

  void _drawFallenCoin(Canvas canvas) {
    _drawCoin(canvas, const Offset(160, 184), 9);
  }

  /// A twig arm from [shoulder] at [angle] (0 = straight down), ending in a
  /// round bark "hand" with a tiny leaf.
  void _arm(Canvas canvas, Offset shoulder, double angle, {double len = 30}) {
    canvas.save();
    canvas.translate(shoulder.dx, shoulder.dy);
    canvas.rotate(angle);
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(-6, -4, 12, len + 4),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      rr.shift(const Offset(1.5, 0)),
      Paint()..color = _bark.edge,
    );
    canvas.drawRRect(rr, Paint()..color = _bark.base);
    // Leaf sprouting from the twig, on the upper side of the arm.
    canvas.save();
    canvas.translate(0, len * 0.62);
    // Raised arms flip which side is "up".
    final up = (angle > 0) != (angle.abs() > math.pi / 2);
    canvas.rotate(up ? -1.15 : 1.15);
    final leaf = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(8, -9, 0, -20)
      ..quadraticBezierTo(-8, -9, 0, 0)
      ..close();
    canvas.drawPath(
      leaf.shift(const Offset(0, 2)),
      Paint()..color = color.edge,
    );
    canvas.drawPath(leaf, Paint()..color = _leafHi);
    canvas.restore();
    // Hand knob.
    canvas.drawCircle(Offset(1.5, len + 1.5), 7.5, Paint()..color = _bark.edge);
    canvas.drawCircle(Offset(0, len), 7.5, Paint()..color = _bark.base);
    canvas.restore();
  }

  void _drawArms(Canvas canvas) {
    switch (mood) {
      case MascotMood.excited:
        final w = math.sin(_t * 8) * 0.15;
        _arm(canvas, _lShoulder.translate(-2, -6), 2.25 + w, len: 36);
        _arm(canvas, _rShoulder.translate(2, -6), -2.25 - w, len: 36);
      case MascotMood.waving:
        _arm(canvas, _lShoulder, 1.2);
        _arm(
          canvas,
          _rShoulder.translate(2, -4),
          -2.2 + math.sin(_t * 6) * 0.35,
          len: 36,
        );
      case MascotMood.thinking:
        _arm(canvas, _lShoulder, 1.15);
        _arm(canvas, _rShoulder, -2.72 + math.sin(_t * 2) * 0.05, len: 28);
      case MascotMood.sad:
        _arm(canvas, _lShoulder, 0.55);
        _arm(canvas, _rShoulder, -0.55);
      case MascotMood.sleeping:
        _arm(canvas, _lShoulder, 0.85);
        _arm(canvas, _rShoulder, -0.85);
      case MascotMood.happy:
        final w = math.sin(_t * 2) * 0.06;
        _arm(canvas, _lShoulder, 1.2 + w);
        _arm(canvas, _rShoulder, -1.2 - w);
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

  static const _le = Offset(79, 84), _re = Offset(121, 84);

  void _drawFace(Canvas canvas) {
    // Cheeks
    final cheek = Paint()
      ..color = _blush.withValues(alpha: mood == MascotMood.sad ? 0.75 : 0.95);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(58, 106), width: 22, height: 12),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(142, 106), width: 22, height: 12),
      cheek,
    );

    switch (mood) {
      case MascotMood.excited:
        _arcEye(canvas, _le, up: true);
        _arcEye(canvas, _re, up: true);
      case MascotMood.sleeping:
        _arcEye(canvas, _le.translate(0, 4), up: false);
        _arcEye(canvas, _re.translate(0, 4), up: false);
      case MascotMood.thinking:
        _openEye(canvas, _le, const Offset(5, -8), _blink);
        _openEye(canvas, _re, const Offset(5, -8), _blink);
      case MascotMood.sad:
        _openEye(canvas, _le, const Offset(-2, 7), _blink, lid: true);
        _openEye(canvas, _re, const Offset(2, 7), _blink, lid: true);
        _brows(canvas);
      case MascotMood.happy:
      case MascotMood.waving:
        _openEye(canvas, _le, const Offset(1, 2), _blink);
        _openEye(canvas, _re, const Offset(-1, 2), _blink);
    }

    _drawMouth(canvas);

    if (mood == MascotMood.sad) {
      // Tear
      final y = 100 + (phase * 2 % 1) * 16;
      final tear = Path()
        ..moveTo(64, y - 10)
        ..quadraticBezierTo(57, y, 64, y + 5)
        ..quadraticBezierTo(71, y, 64, y - 10)
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
      eye.shift(const Offset(0, 2.5)),
      Paint()..color = color.edge.withValues(alpha: 0.6),
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
      // Sad lid: droops at the outer corner, lifts toward the nose.
      final outerLeft = c.dx < 100;
      final hi = eye.top + h * 0.12, lo = eye.top + h * 0.42;
      canvas.drawPath(
        Path()
          ..moveTo(eye.left, eye.top)
          ..lineTo(eye.right, eye.top)
          ..lineTo(eye.right, outerLeft ? hi : lo)
          ..lineTo(eye.left, outerLeft ? lo : hi)
          ..close(),
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

  void _brows(Canvas canvas) {
    final p = Paint()
      ..color = color.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(_le.translate(-14, -22), _le.translate(10, -30), p);
    canvas.drawLine(_re.translate(14, -22), _re.translate(-10, -30), p);
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
        final w = big ? 16.0 : 12.0;
        final d = big ? 20.0 : 15.0;
        const top = 106.0;
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
            ..moveTo(88, 112)
            ..quadraticBezierTo(96, 108, 104, 111),
          stroke,
        );
      case MascotMood.sad:
        canvas.drawPath(
          Path()
            ..moveTo(89, 116)
            ..quadraticBezierTo(100, 105, 111, 116),
          stroke,
        );
      case MascotMood.sleeping:
        final o = 1 + 0.25 * math.sin(_t);
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(100, 112),
            width: 9 * o,
            height: 11 * o,
          ),
          Paint()..color = _mouth,
        );
    }
  }

  // ---- extras (not moving with the tree) ---------------------------------------

  void _drawExtras(Canvas canvas) {
    switch (mood) {
      case MascotMood.excited:
        // Coins popping out of the crown.
        for (var i = 0; i < 2; i++) {
          final k = (phase * 2 + i * 0.5) % 1;
          final dir = i == 0 ? -1.0 : 1.0;
          final x = 100 + dir * (26 + 40 * k);
          final y = 30 - 70 * k + 90 * k * k;
          final fade = k < 0.15 ? k / 0.15 : (k > 0.8 ? (1 - k) / 0.2 : 1.0);
          _drawCoin(canvas, Offset(x, y), 8, opacity: fade);
        }
        _sparkle(canvas, const Offset(18, 40), 15, 0);
        _sparkle(canvas, const Offset(186, 60), 13, 0.33);
        _sparkle(canvas, const Offset(176, 10), 10, 0.66);
        _sparkle(canvas, const Offset(14, 140), 10, 0.5);
      case MascotMood.thinking:
        final bob = math.sin(_t * 2) * 2;
        final p = Paint()
          ..color = GhinaColors.blue.base.withValues(alpha: 0.85);
        canvas.drawCircle(Offset(170, 36 + bob), 5, p);
        canvas.drawCircle(Offset(181, 21 + bob), 7, p);
        canvas.drawCircle(Offset(192, 5 + bob), 8, p);
      case MascotMood.sad:
        _fallingLeaf(canvas);
      case MascotMood.sleeping:
        for (var i = 0; i < 3; i++) {
          final k = (phase + i / 3) % 1;
          final fade = k < 0.2 ? k / 0.2 : (1 - k);
          _z(
            canvas,
            Offset(164 + k * 20, 58 - k * 54),
            18 + k * 12,
            0.35 + 0.65 * fade,
          );
        }
      default:
        break;
    }
  }

  void _fallingLeaf(Canvas canvas) {
    final k = phase;
    final x = 34 + 10 * math.sin(k * 2 * math.pi * 2);
    final y = 128 + 56 * k;
    final fade = k > 0.85 ? (1 - k) / 0.15 : 1.0;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(0.6 * math.sin(k * 2 * math.pi * 2) + 0.8);
    final leaf = Path()
      ..moveTo(0, -9)
      ..quadraticBezierTo(8, 0, 0, 9)
      ..quadraticBezierTo(-8, 0, 0, -9)
      ..close();
    canvas.drawPath(
      leaf.shift(const Offset(0, 1.5)),
      Paint()..color = color.edge.withValues(alpha: fade),
    );
    canvas.drawPath(leaf, Paint()..color = _leafHi.withValues(alpha: fade));
    canvas.restore();
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
