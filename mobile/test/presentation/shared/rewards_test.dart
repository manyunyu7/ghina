import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/shared/rewards/rewards.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';

import '../features/shell/test_utils.dart';

/// Fires [presentPendingCelebrations] twice at once.
class _Trigger extends ConsumerWidget {
  const _Trigger();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(gameSummaryProvider);
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () {
            for (var i = 0; i < 2; i++) {
              unawaited(presentPendingCelebrations(context));
            }
          },
          child: const Text('go'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('concurrent presentations show each moment once, ack once', (
    tester,
  ) async {
    final store = InMemoryGameStore({
      GameLocalState.storageKey: const GameLocalState(
        lastSeenLevel: 1,
        onboardingDone: true,
      ).encode(),
    });
    await pumpPage(
      tester,
      const _Trigger(),
      overrides: pageOverrides(events: streakEvents(1, today: 3), store: store),
    );
    await settle(tester, 6);

    await tester.tap(find.text('go'));
    await settle(tester, 8);
    expect(find.text('Target harian tercapai!'), findsOneWidget);
    await tester.ensureVisible(find.text('LANJUT'));
    await tester.tap(find.text('LANJUT'));
    await settle(tester, 8);
    expect(find.textContaining('encana baru'), findsOneWidget);
    await tester.ensureVisible(find.text('MANTAP!'));
    await tester.tap(find.text('MANTAP!'));
    await settle(tester, 12);

    // The second (concurrent) call found nothing left to show.
    expect(find.byType(CelebrationScreen), findsNothing);
    expect(find.textContaining('encana baru'), findsNothing);
    final saved = GameLocalState.decode(
      store.values[GameLocalState.storageKey],
    );
    expect(saved.celebrated, contains('goal:2026-09-23'));
    expect(saved.seenAchievements, isNotEmpty);

    // Calling again later (even with a possibly stale summary) is a no-op.
    await tester.tap(find.text('go'));
    await settle(tester, 8);
    expect(find.byType(CelebrationScreen), findsNothing);
    await settle(tester, 30);
  });
}
