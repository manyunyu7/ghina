import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game/game.dart' hide MascotMood;
import '../../design_system/design_system.dart';
import '../../state/game/game_providers.dart';
import '../game_visuals.dart';

/// Makes sure a reward moment is shown at most once per app session, and only
/// one presentation runs at a time. Scoped to the [ProviderContainer] (one per
/// app / per test).
final celebrationGateProvider = Provider<CelebrationGate>(
  (ref) => CelebrationGate(),
);

class CelebrationGate {
  Future<void>? _running;
  final Set<String> _claimed = {};

  /// True while a presentation is on screen.
  bool get isBusy => _running != null;

  /// Waits until no presentation runs (or [context] goes away). Returns
  /// whether it had to wait.
  Future<bool> _idle(BuildContext context) async {
    var waited = false;
    for (var r = _running; r != null && context.mounted; r = _running) {
      waited = true;
      await r;
    }
    return waited;
  }

  static List<String> _keys(GameCelebrations c, GameDate today) => [
    if (c.dailyGoalMet) GameCelebrations.goalKey(today),
    if (c.streakMilestone case final m?) GameCelebrations.streakKey(m),
    if (c.levelUp case final l?) 'level:${l.level}',
    for (final a in c.newAchievements) 'badge:${a.id}',
  ];

  /// The part of [c] nobody has claimed yet.
  GameCelebrations _unclaimed(GameCelebrations c, GameDate today) {
    bool free(String key) => !_claimed.contains(key);
    final m = c.streakMilestone;
    final l = c.levelUp;
    return GameCelebrations(
      dailyGoalMet: c.dailyGoalMet && free(GameCelebrations.goalKey(today)),
      streakMilestone: m != null && free(GameCelebrations.streakKey(m))
          ? m
          : null,
      levelUp: l != null && free('level:${l.level}') ? l : null,
      newAchievements: [
        for (final a in c.newAchievements)
          if (free('badge:${a.id}')) a,
      ],
    );
  }
}

/// Shows the pending reward moments of the current [GameSummary] one after
/// another — daily goal, streak milestone, level up, then new badges — and
/// acknowledges exactly the ones that were shown.
///
/// Safe to call from anywhere, any number of times: moments already shown (or
/// being shown) are skipped, and a call made while another presentation runs
/// waits for it first. Pass [summary] when you already have a fresh one.
Future<void> presentPendingCelebrations(
  BuildContext context, {
  GameSummary? summary,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final gate = container.read(celebrationGateProvider);
  final waited = await gate._idle(context);
  if (!context.mounted) return;
  GameSummary? s = waited ? null : summary;
  try {
    s ??= container.read(gameSummaryProvider).value;
  } catch (_) {
    s = null;
  }
  if (s == null || !context.mounted) return;
  await _present(context, container, gate, s.celebrations, s);
}

/// Celebrates [items] (e.g. badges found unseen on the achievements page)
/// through the same once-only path as [presentPendingCelebrations].
Future<void> presentNewAchievements(
  BuildContext context,
  List<AchievementProgress> items,
) async {
  if (items.isEmpty) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final gate = container.read(celebrationGateProvider);
  await gate._idle(context);
  if (!context.mounted) return;
  await _present(
    context,
    container,
    gate,
    GameCelebrations(newAchievements: items),
    null,
  );
}

Future<void> _present(
  BuildContext context,
  ProviderContainer container,
  CelebrationGate gate,
  GameCelebrations all,
  GameSummary? s,
) async {
  final today =
      s?.today ??
      GameDate.fromDateTime(container.read(gameClockProvider).now());
  final c = gate._unclaimed(all, today);
  if (c.isEmpty) return;
  final keys = CelebrationGate._keys(c, today);
  gate._claimed.addAll(keys);
  final done = Completer<void>();
  gate._running = done.future;

  var goalShown = false;
  StreakMilestoneHit? streakShown;
  LevelInfo? levelShown;
  var badgesShown = false;
  try {
    if (c.dailyGoalMet && s != null && context.mounted) {
      await showCelebration(
        context,
        title: 'Target harian tercapai!',
        subtitle: '${s.goal.done} aktivitas hari ini. Kamu keren banget!',
        xp: XpRules.dailyGoalMet,
        streak: s.streak.current > 0 ? s.streak.current : null,
      );
      goalShown = true;
    }
    final m = c.streakMilestone;
    if (m != null && context.mounted) {
      await showCelebration(
        context,
        title: 'Streak ${m.length} hari! 🔥',
        subtitle: m.length % XpRules.freezeEveryDays == 0
            ? 'Bonus: kamu dapat 1 streak freeze buat jaga-jaga 🧊'
            : 'Api semangatmu makin besar. Pertahankan!',
        xp: XpRules.streakMilestones[m.length],
        streak: m.length,
      );
      streakShown = m;
    }
    final l = c.levelUp;
    if (l != null && context.mounted) {
      await showCelebration(
        context,
        title: 'Naik ke level ${l.level}!',
        subtitle: l.nextTitle == null
            ? 'Gelar kamu sekarang: ${l.title}.'
            : 'Gelar kamu sekarang: ${l.title}. Berikutnya: ${l.nextTitle}.',
        stats: [
          CelebrationStat(
            label: 'Level',
            value: '${l.level}',
            icon: Icons.military_tech_rounded,
            color: GhinaColors.level,
          ),
        ],
      );
      levelShown = l;
    }
    if (c.newAchievements.isNotEmpty && context.mounted) {
      await showAchievementsUnlocked(context, c.newAchievements);
      badgesShown = true;
    }
  } finally {
    final shown = GameCelebrations(
      dailyGoalMet: goalShown,
      streakMilestone: streakShown,
      levelUp: levelShown,
      newAchievements: badgesShown ? c.newAchievements : const [],
    );
    // Whatever couldn't be shown (screen went away) stays pending for later.
    gate._claimed.removeAll(
      keys.toSet().difference(CelebrationGate._keys(shown, today).toSet()),
    );
    try {
      if (shown.isNotEmpty) {
        await container
            .read(gameActionsProvider)
            .acknowledgeCelebrations(shown);
      }
    } catch (_) {
      // Container gone (app closing): nothing left to persist.
    } finally {
      gate._running = null;
      done.complete();
    }
  }
}

/// Bottom sheet presenting newly unlocked badges in their tier colours.
/// Prefer [presentNewAchievements]; this only draws the sheet.
Future<void> showAchievementsUnlocked(
  BuildContext context,
  List<AchievementProgress> items,
) {
  HapticFeedback.mediumImpact();
  return showChunkyBottomSheet<void>(
    context,
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          items.length == 1
              ? 'Lencana baru! 🎉'
              : '${items.length} lencana baru! 🎉',
          style: GhinaType.h1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < items.length; i++)
          PopIn(
            delay: Duration(milliseconds: 120 * i),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ChunkyCard(
                tinted: tierSwatch(items[i].def.tier),
                child: Row(
                  children: [
                    AchievementBadge(
                      def: items[i].def,
                      unlocked: true,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].def.title, style: GhinaType.h3),
                          const SizedBox(height: 2),
                          Text(
                            items[i].def.description,
                            style: GhinaType.bodyS.copyWith(
                              color: c.ghina.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ChunkyPill(
                            label: tierLabel(items[i].def.tier),
                            color: tierSwatch(items[i].def.tier),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        ChunkyButton(
          label: 'Mantap!',
          size: ChunkyButtonSize.large,
          onPressed: () => Navigator.of(c).pop(),
        ),
      ],
    ),
  );
}
