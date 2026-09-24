import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game/game.dart' hide MascotMood;
import '../../design_system/design_system.dart';
import '../../state/game/game_providers.dart';
import 'celebrations.dart';

/// The reward moment after the user logs something (transaction, prayer,
/// health entry, food, lesson, quick pay…):
///
/// 1. [start] snapshots the game state *before* the write,
/// 2. [finish] waits (briefly) until the summary reflects the write,
/// 3. toasts the XP gained (or a plain "saved" toast),
/// 4. presents pending celebrations in order and acknowledges them
///    (via [presentPendingCelebrations], so nothing shows twice).
///
/// ```dart
/// final rewards = RewardTracker.start(ref);
/// final r = await ref.read(createFoodLogProvider)(input);
/// if (r.isOk && context.mounted) {
///   await rewards.finish(context, xpToast: (xp) => 'Nyam! +$xp XP');
/// }
/// ```
class RewardTracker {
  RewardTracker._(this._before, [this._keepAlive]);

  final GameSummary? _before;

  /// Set by [startLoaded]: keeps the summary listened until [finish]/[cancel].
  final ProviderSubscription<Object?>? _keepAlive;

  /// Releases what [startLoaded] holds when [finish] won't be called.
  void cancel() => _keepAlive?.close();

  /// Remembers the current game summary (if it's loaded).
  static RewardTracker start(WidgetRef ref) {
    GameSummary? s;
    try {
      s = ref.read(gameSummaryProvider).value;
    } catch (_) {
      s = null;
    }
    return RewardTracker._(s);
  }

  /// Like [start], but when the summary isn't loaded yet (nothing on screen
  /// watches it — e.g. a cold start straight into the Tugas tab), loads it
  /// first so the XP diff can be computed. Gives up after [timeout].
  static Future<RewardTracker> startLoaded(
    WidgetRef ref, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final now = start(ref);
    if (now._before != null) return now;
    // Listen (a bare read would leave the unlistened provider paused).
    final done = Completer<GameSummary?>();
    ProviderSubscription<AsyncValue<GameSummary>>? sub;
    try {
      sub = ref.listenManual<AsyncValue<GameSummary>>(gameSummaryProvider, (
        _,
        next,
      ) {
        if (done.isCompleted) return;
        if (next.hasError && !next.isLoading) done.complete(null);
        final v = next.value;
        if (v != null && !next.isLoading) done.complete(v);
      }, fireImmediately: true);
    } catch (_) {
      return now;
    }
    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete(null);
    });
    final s = await done.future;
    timer.cancel();
    // Stays open (the provider keeps updating) until finish/cancel.
    return RewardTracker._(s, sub);
  }

  /// Runs steps 2–4. [xpToast] builds the toast shown when XP was gained;
  /// [doneToast] is shown otherwise (none when null). With [goalHint] the
  /// toast also shows daily goal progress while the goal isn't met yet.
  /// Returns the XP gained (0 when none or unknown).
  Future<int> finish(
    BuildContext context, {
    String Function(int xp)? xpToast,
    String? doneToast,
    bool goalHint = false,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final s = await _awaitFresh(container, timeout);
    cancel();
    if (!context.mounted) return 0;
    final before = _before;
    final diff = (s == null || before == null) ? 0 : s.totalXp - before.totalXp;
    final gained = diff > 0 ? diff : 0;

    final goal = s?.goal;
    final hint = goalHint && goal != null && !goal.isMet
        ? ' · Target ${goal.done}/${goal.target}'
        : '';
    var toasted = false;
    if (gained > 0 && xpToast != null) {
      showToastBadge(
        context,
        message: '${xpToast(gained)}$hint',
        icon: Icons.bolt_rounded,
        color: GhinaColors.xp,
      );
      toasted = true;
    } else if (doneToast != null) {
      showToastBadge(
        context,
        message: '$doneToast$hint',
        icon: Icons.check_circle_rounded,
        color: GhinaColors.green,
      );
      toasted = true;
    }

    if (s != null && s.celebrations.isNotEmpty) {
      // Let the toast register before the confetti covers the screen.
      if (toasted) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      if (context.mounted) {
        await presentPendingCelebrations(context, summary: s);
      }
    }
    return gained;
  }

  /// Latest summary once it differs from the snapshot (more XP, or a new
  /// transaction counted today even when XP is capped), or whatever is there
  /// after [timeout]. Null when the game state can't be read.
  Future<GameSummary?> _awaitFresh(
    ProviderContainer container,
    Duration timeout,
  ) async {
    final before = _before;
    bool fresh(GameSummary s) =>
        before == null ||
        s.totalXp != before.totalXp ||
        _txToday(s) != _txToday(before) ||
        s.xp.activitiesToday != before.xp.activitiesToday;

    final done = Completer<GameSummary?>();
    ProviderSubscription<AsyncValue<GameSummary>>? sub;
    try {
      sub = container.listen<AsyncValue<GameSummary>>(gameSummaryProvider, (
        _,
        next,
      ) {
        final v = next.value;
        if (v != null && !next.isLoading && fresh(v) && !done.isCompleted) {
          done.complete(v);
        }
      }, fireImmediately: true);
    } catch (_) {
      return null;
    }
    final timer = Timer(timeout, () {
      if (done.isCompleted) return;
      try {
        done.complete(container.read(gameSummaryProvider).value);
      } catch (_) {
        done.complete(null);
      }
    });
    final r = await done.future;
    timer.cancel();
    sub.close();
    return r;
  }

  static int _txToday(GameSummary s) =>
      s.xp.dayOf(s.today)?.transactionsTotal ?? 0;
}
