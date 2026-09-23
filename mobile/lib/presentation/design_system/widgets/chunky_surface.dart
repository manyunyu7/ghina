import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/dimens.dart';

/// The primitive behind every "3D" element: a rounded face sitting on a
/// darker bottom edge. When tapped the face sinks onto the edge.
///
/// You rarely need this directly – use [ChunkyButton], [ChunkyCard],
/// [ChunkyTile] etc. Use it for custom pressables:
///
/// ```dart
/// ChunkySurface(
///   color: GhinaColors.yellow.base,
///   edgeColor: GhinaColors.yellow.edge,
///   onTap: () {},
///   child: const Icon(Icons.star_rounded, color: Colors.white),
/// );
/// ```
class ChunkySurface extends StatefulWidget {
  const ChunkySurface({
    super.key,
    required this.child,
    required this.color,
    required this.edgeColor,
    this.borderColor,
    this.borderWidth = GhinaDepth.border,
    this.borderRadius = GhinaRadii.rLg,
    this.depth = GhinaDepth.md,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.haptics = true,
    this.semanticLabel,
    this.isButton = true,
    this.pressed,
  });

  final Widget child;
  final Color color;
  final Color edgeColor;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;

  /// Height of the bottom edge (the "3D" part).
  final double depth;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final bool haptics;
  final String? semanticLabel;
  final bool isButton;

  /// Force the pressed look (e.g. a selected toggle). Null = interactive.
  final bool? pressed;

  @override
  State<ChunkySurface> createState() => _ChunkySurfaceState();
}

class _ChunkySurfaceState extends State<ChunkySurface> {
  bool _down = false;
  DateTime _downAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Keep the pressed look visible for at least this long, so quick taps
  /// (where down & up arrive together) still show the press.
  static const _minPress = Duration(milliseconds: 90);

  void _release() {
    final left = _minPress - DateTime.now().difference(_downAt);
    if (left <= Duration.zero) {
      _set(false);
    } else {
      _timer?.cancel();
      _timer = Timer(left, () {
        if (mounted) _set(false);
      });
    }
  }

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.pressed ?? (_down && _interactive);
    final d = widget.depth;
    final border = widget.borderColor == null
        ? null
        : Border.all(color: widget.borderColor!, width: widget.borderWidth);

    Widget surface = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          top: d,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.edgeColor,
              borderRadius: widget.borderRadius,
            ),
          ),
        ),
        AnimatedContainer(
          duration: GhinaMotion.press,
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            top: pressed ? d : 0,
            bottom: pressed ? 0 : d,
          ),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: widget.borderRadius,
            border: border,
          ),
          child: widget.child,
        ),
      ],
    );

    if (!_interactive) {
      return Semantics(
        container: true,
        label: widget.semanticLabel,
        button: widget.isButton && widget.onTap != null,
        enabled: widget.enabled,
        child: surface,
      );
    }

    return Semantics(
      button: widget.isButton,
      enabled: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _downAt = DateTime.now();
            _set(true);
            if (widget.haptics) HapticFeedback.lightImpact();
          },
          onTapUp: (_) => _release(),
          onTapCancel: _release,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  _set(false);
                  if (widget.haptics) HapticFeedback.mediumImpact();
                  widget.onLongPress!();
                },
          child: surface,
        ),
      ),
    );
  }
}
