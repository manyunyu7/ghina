import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/features/profile/pages/achievements_page.dart';
import 'package:ghina/presentation/features/profile/pages/profile_page.dart';
import 'package:go_router/go_router.dart';

import '_harness.dart';

final _routes = [
  GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
  GoRoute(path: '/achievements', builder: (_, _) => const AchievementsPage()),
];

void main() {
  testWidgets('profile shows who you are, level, streak and stats', (
    tester,
  ) async {
    final h = Harness()..seedStreak(5);
    await pumpScreen(tester, h, location: '/profile', routes: _routes);
    expect(find.text('Ghina Putri'), findsOneWidget);
    expect(find.text('ghina@contoh.id'), findsOneWidget);
    expect(find.text('LEVEL 1'), findsOneWidget);
    expect(find.text('Receh Pemula'), findsOneWidget);
    expect(find.text('Total XP'), findsOneWidget);
    expect(find.text('Rekor streak'), findsOneWidget);
    await scrollTo(tester, find.text('5 hari streak'));
    expect(find.text('5 hari streak'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('menu links to the other features', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/profile', routes: _routes);
    await scrollTo(tester, find.text('Salat'));
    await tester.tap(find.text('Salat'));
    await settle(tester, 5);
    expect(find.text('route:/prayers'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('menu links to Konten', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/profile', routes: _routes);
    await scrollTo(tester, find.text('Konten'));
    await tester.tap(find.text('Konten'));
    await settle(tester, 5);
    expect(find.text('route:/content'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('daily goal can be changed', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/profile', routes: _routes);
    await scrollTo(tester, find.text('Target harian'));
    expect(find.text('Reguler · 3 aktivitas sehari'), findsOneWidget);
    await tester.tap(find.text('Target harian'));
    await settle(tester, 6);
    await tester.tap(find.text('Serius · 5 aktivitas'));
    await settle(tester, 10);
    expect(find.text('Serius · 5 aktivitas sehari'), findsOneWidget);
    final saved = GameLocalState.decode(
      h.gameStore.values[GameLocalState.storageKey],
    );
    expect(saved.currentGoal, DailyGoalLevel.serius);
    await drain(tester);
  });

  testWidgets('achievements preview opens the full list', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/profile', routes: _routes);
    await scrollTo(tester, find.text('LIHAT SEMUA'));
    await tester.tap(find.text('LIHAT SEMUA'));
    await settle(tester, 8);
    expect(find.text('Pencapaian'), findsWidgets);
    expect(
      find.textContaining('dari ${achievementDefs.length} lencana'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('newly unlocked badges are celebrated then marked seen', (
    tester,
  ) async {
    final h = Harness()..seedStreak(1);
    // Not the first run, so the unlocked badge counts as new.
    h.seedGame(const GameLocalState(lastSeenLevel: 1, onboardingDone: true));
    await pumpScreen(tester, h, location: '/achievements', routes: _routes);
    expect(find.text('Lencana baru! 🎉'), findsOneWidget);
    expect(find.text('Langkah Pertama'), findsWidgets);
    await tester.tap(find.text('MANTAP!'));
    await settle(tester, 8);
    final saved = GameLocalState.decode(
      h.gameStore.values[GameLocalState.storageKey],
    );
    expect(saved.seenAchievements, contains('first_transaction'));
    await drain(tester);
  });

  testWidgets('tapping a locked badge shows its progress', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/achievements', routes: _routes);
    await tester.tap(find.text('Langkah Pertama'));
    await settle(tester, 6);
    expect(find.text('Catat transaksi pertamamu.'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);
    await drain(tester);
  });
}
