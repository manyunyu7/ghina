import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/dimens.dart';

/// Pops its child in (scale overshoot + fade) when first built.
/// Stagger lists with `delay: Duration(milliseconds: 60 * i)`.
///
/// ```dart
/// PopIn(delay: const Duration(milliseconds: 120), child: XpBadge(xp: 15));
/// ```
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = GhinaMotion.slow,
    this.fromScale = 0.5,
    this.slideY = 0,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double fromScale;

  /// Optional vertical slide (fraction of height) combined with the pop.
  final double slideY;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _c, curve: GhinaMotion.pop);
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.4));
    return FadeTransition(
      opacity: fade,
      child: AnimatedBuilder(
        animation: scale,
        builder: (context, child) => FractionalTranslation(
          translation: Offset(0, widget.slideY * (1 - scale.value)),
          child: Transform.scale(
            scale: widget.fromScale + (1 - widget.fromScale) * scale.value,
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Shakes its child horizontally whenever [trigger] changes (e.g. an error
/// counter or the error text). Great for wrong answers and invalid input.
///
/// ```dart
/// Shake(trigger: _errorCount, child: ChunkyTextField(...));
/// ```
class Shake extends StatefulWidget {
  const Shake({
    super.key,
    required this.child,
    this.trigger,
    this.distance = 10,
  });

  final Widget child;
  final Object? trigger;
  final double distance;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && widget.trigger != null) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dx = math.sin(t * math.pi * 6) * widget.distance * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// Gently floats its child up and down forever (idle "alive" motion) –
/// e.g. the current lesson node or a "Mulai" bubble.
class Bounce extends StatefulWidget {
  const Bounce({
    super.key,
    required this.child,
    this.height = 6,
    this.period = const Duration(milliseconds: 1400),
    this.enabled = true,
  });

  final Widget child;
  final double height;
  final Duration period;
  final bool enabled;

  @override
  State<Bounce> createState() => _BounceState();
}

class _BounceState extends State<Bounce> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant Bounce old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_c.isAnimating) _c.repeat();
    if (!widget.enabled && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          -widget.height * (0.5 - 0.5 * math.cos(_c.value * 2 * math.pi)),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Plays a quick "boing" scale pulse whenever [trigger] changes – use on
/// counters (XP, streak, hearts) when their value updates.
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.child,
    this.trigger,
    this.scale = 1.25,
  });

  final Widget child;
  final Object? trigger;
  final double scale;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: GhinaMotion.slow);

  @override
  void didUpdateWidget(covariant Pulse old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final s =
            1 + (widget.scale - 1) * math.sin(t * math.pi) * (1 - t * 0.3);
        return Transform.scale(scale: s, child: child);
      },
      child: widget.child,
    );
  }
}
