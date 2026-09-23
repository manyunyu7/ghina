import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mascot/mascot_view.dart';
import '../motion/motion.dart';
import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import '../widgets/chunky_button.dart';
import '../widgets/game_badges.dart';

/// One stat box on the celebration screen ("TOTAL XP  +15").
class CelebrationStat {
  const CelebrationStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final ChunkySwatch color;
}

/// Full-screen "lesson complete" celebration: confetti, excited mascot,
/// big title, stat boxes and a continue button. Resolves when dismissed.
///
/// ```dart
/// await showCelebration(
///   context,
///   title: 'Mantap!',
///   subtitle: 'Transaksi pertamamu hari ini tercatat.',
///   xp: 15,
///   streak: 6,
/// );
/// // or fully custom stats:
/// await showCelebration(context, title: 'Budget aman!', stats: [
///   CelebrationStat(label: 'Hemat', value: 'Rp 120rb', icon: Icons.savings_rounded, color: GhinaColors.green),
/// ]);
/// ```
Future<void> showCelebration(
  BuildContext context, {
  String title = 'Mantap!',
  String? subtitle,
  int? xp,
  int? streak,
  List<CelebrationStat>? stats,
  MascotMood mood = MascotMood.excited,
  String buttonLabel = 'Lanjut',
  bool confetti = true,
}) {
  HapticFeedback.mediumImpact();
  final allStats = <CelebrationStat>[
    if (xp != null)
      CelebrationStat(
        label: 'Total XP',
        value: '+$xp',
        icon: Icons.bolt_rounded,
        color: GhinaColors.yellow,
      ),
    if (streak != null)
      CelebrationStat(
        label: 'Streak',
        value: '$streak hari',
        icon: Icons.local_fire_department_rounded,
        color: GhinaColors.orange,
      ),
    ...?stats,
  ];
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: GhinaMotion.medium,
      reverseTransitionDuration: GhinaMotion.fast,
      pageBuilder: (_, _, _) => CelebrationScreen(
        title: title,
        subtitle: subtitle,
        stats: allStats,
        mood: mood,
        buttonLabel: buttonLabel,
        confetti: confetti,
        streak: streak,
      ),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

/// The screen used by [showCelebration]. Usable directly (e.g. as a route).
class CelebrationScreen extends StatefulWidget {
  const CelebrationScreen({
    super.key,
    this.title = 'Mantap!',
    this.subtitle,
    this.stats = const [],
    this.mood = MascotMood.excited,
    this.buttonLabel = 'Lanjut',
    this.confetti = true,
    this.streak,
    this.onContinue,
  });

  final String title;
  final String? subtitle;
  final List<CelebrationStat> stats;
  final MascotMood mood;
  final String buttonLabel;
  final bool confetti;
  final int? streak;

  /// Defaults to popping the route.
  final VoidCallback? onContinue;

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen> {
  late final _confetti = ConfettiController(
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.confetti) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _confetti.play();
      });
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Scaffold(
      backgroundColor: g.background,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  PopIn(child: MascotView(mood: widget.mood, size: 180)),
                  const SizedBox(height: 20),
                  PopIn(
                    delay: const Duration(milliseconds: 150),
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: GhinaType.display.copyWith(
                        color: GhinaColors.yellow.base,
                        fontSize: 38,
                      ),
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 8),
                    PopIn(
                      delay: const Duration(milliseconds: 250),
                      child: Text(
                        widget.subtitle!,
                        textAlign: TextAlign.center,
                        style: GhinaType.bodyL
                            .w(700)
                            .copyWith(color: g.textSecondary),
                      ),
                    ),
                  ],
                  if (widget.streak != null) ...[
                    const SizedBox(height: 16),
                    PopIn(
                      delay: const Duration(milliseconds: 320),
                      child: StreakFlame(count: widget.streak!, size: 34),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (widget.stats.isNotEmpty)
                    Row(
                      children: [
                        for (var i = 0; i < widget.stats.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(
                            child: PopIn(
                              delay: Duration(milliseconds: 420 + 120 * i),
                              child: _StatBox(stat: widget.stats[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  const Spacer(flex: 3),
                  PopIn(
                    delay: const Duration(milliseconds: 600),
                    fromScale: 0.9,
                    child: ChunkyButton(
                      label: widget.buttonLabel,
                      onPressed:
                          widget.onContinue ??
                          () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              blastDirection: math.pi / 2,
              emissionFrequency: 0.06,
              numberOfParticles: 18,
              maxBlastForce: 28,
              minBlastForce: 10,
              gravity: 0.25,
              colors: GhinaColors.confetti,
              minimumSize: const Size(10, 6),
              maximumSize: const Size(18, 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.stat});

  final CelebrationStat stat;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      decoration: BoxDecoration(
        color: stat.color.base,
        borderRadius: GhinaRadii.rLg,
        border: Border.all(color: stat.color.base, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              stat.label.toUpperCase(),
              style: GhinaType.overline.copyWith(
                color: stat.color.on,
                fontSize: 12,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: g.surface,
              borderRadius: BorderRadius.circular(GhinaRadii.lg - 3),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(stat.icon, color: stat.color.base, size: 26),
                  const SizedBox(width: 4),
                  Text(
                    stat.value,
                    style: GhinaType.h2.w(900).copyWith(color: stat.color.base),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
