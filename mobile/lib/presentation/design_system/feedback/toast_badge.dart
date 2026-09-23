import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';

/// Light reward/info toast that drops from the top, bounces, and leaves.
/// For small wins (+5 XP, achievement unlocked) and quick confirmations.
///
/// ```dart
/// showToastBadge(context, message: '+10 XP', icon: Icons.bolt_rounded, color: GhinaColors.yellow);
/// showToastBadge(context, message: 'Tersimpan offline, nanti disinkron 👍',
///     icon: Icons.cloud_off_rounded, color: GhinaColors.blue);
/// ```
void showToastBadge(
  BuildContext context, {
  required String message,
  IconData icon = Icons.star_rounded,
  ChunkySwatch color = GhinaColors.yellow,
  Duration duration = const Duration(milliseconds: 2200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  HapticFeedback.lightImpact();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastBadge(
      message: message,
      icon: icon,
      color: color,
      duration: duration,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _ToastBadge extends StatefulWidget {
  const _ToastBadge({
    required this.message,
    required this.icon,
    required this.color,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final IconData icon;
  final ChunkySwatch color;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_ToastBadge> createState() => _ToastBadgeState();
}

class _ToastBadgeState extends State<_ToastBadge>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: GhinaMotion.slow);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.animateBack(0, duration: GhinaMotion.fast);
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = Theme.of(context).extension<GhinaTokens>() ?? GhinaTokens.light;
    final curve = CurvedAnimation(
      parent: _c,
      curve: GhinaMotion.pop,
      reverseCurve: Curves.easeIn,
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 24,
      right: 24,
      child: Center(
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -1.6),
            end: Offset.zero,
          ).animate(curve),
          child: GestureDetector(
            onTap: _dismiss,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                decoration: BoxDecoration(
                  color: g.surface,
                  borderRadius: GhinaRadii.rPill,
                  border: Border.all(color: widget.color.base, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.edge,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.color.base,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.color.on,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: GhinaType.body
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
