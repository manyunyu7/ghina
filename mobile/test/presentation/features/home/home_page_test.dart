import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/home/pages/home_page.dart';

import '../shell/test_utils.dart';

void main() {
  testWidgets(
    'shows game stats, balance, budgets, bills and recent transactions',
    (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: pageOverrides(events: streakEvents(4)),
      );

      expect(find.text('Selamat siang, Ghina!'), findsOneWidget);
      expect(find.byType(StreakFlame), findsOneWidget);
      expect(find.text('TOTAL SALDO'), findsOneWidget);
      expect(find.text('Rp 4.550.000'), findsOneWidget);
      expect(find.text('Tinggal 2 aktivitas lagi'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Netflix'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Lewat!'), findsOneWidget); // food budget is over
      expect(find.text('Tagihan sebentar lagi'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Kopi susu'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Gaji September'), findsOneWidget);
      await tester.ensureVisible(find.text('Kopi susu'));
      await settle(tester, 3);
      await tester.tap(find.text('Kopi susu'));
      await settle(tester);
      expect(find.text('ROUTE:/transactions/t1'), findsOneWidget);
    },
  );

  testWidgets('balance card opens wallets and quick actions navigate', (
    tester,
  ) async {
    await pumpPage(tester, const HomePage(), overrides: pageOverrides());
    await tester.tap(find.text('TOTAL SALDO'));
    await settle(tester);
    expect(find.text('ROUTE:/wallets'), findsOneWidget);
  });

  testWidgets('quick action grid pushes the module route', (tester) async {
    await pumpPage(tester, const HomePage(), overrides: pageOverrides());
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qa-/prayers')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('qa-/prayers')));
    await settle(tester, 3);
    await tester.tap(find.byKey(const ValueKey('qa-/prayers')));
    await settle(tester);
    expect(find.text('ROUTE:/prayers'), findsOneWidget);
  });

  testWidgets('empty account invites the first transaction', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: pageOverrides(
        dashboard: sampleDashboard(empty: true),
        budgets: sampleBudgets(empty: true),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Belum ada transaksi'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('CATAT SEKARANG'));
    await settle(tester, 3);
    await tester.tap(find.text('CATAT SEKARANG'));
    await settle(tester);
    expect(find.text('ROUTE:/transactions/new'), findsOneWidget);
  });

  testWidgets('shows skeletons while loading', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: pageOverrides(
        dashboardStream: const Stream<DashboardSummary>.empty(),
      ),
    );
    expect(find.byType(Skeleton), findsWidgets);
  });

  testWidgets('shows a retry on error', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: pageOverrides(
        dashboardStream: Stream<DashboardSummary>.error(Exception('boom')),
      ),
    );
    expect(find.text('Ups, ada yang salah'), findsOneWidget);
    expect(find.text('COBA LAGI'), findsOneWidget);
  });

  testWidgets('pull to refresh syncs, offline shows a gentle toast', (
    tester,
  ) async {
    final sync = FakeSyncService()..failWith = const NetworkFailure();
    await pumpPage(
      tester,
      const HomePage(),
      overrides: pageOverrides(syncService: sync),
    );
    await tester.fling(find.text('TOTAL SALDO'), const Offset(0, 400), 1000);
    await settle(tester, 20);
    expect(sync.syncCalls, 1);
    expect(find.textContaining('Lagi offline'), findsOneWidget);
    await settle(tester, 30);
  });

  testWidgets('celebrates a met daily goal once and acknowledges it', (
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
      const HomePage(),
      overrides: pageOverrides(events: streakEvents(1, today: 3), store: store),
    );
    await settle(tester, 8);
    expect(find.text('Target harian tercapai!'), findsOneWidget);
    await tester.ensureVisible(find.text('LANJUT'));
    await settle(tester, 3);
    await tester.tap(find.text('LANJUT'));
    await settle(tester, 8);
    expect(find.text('Target harian tercapai!'), findsNothing);
    // First transaction also unlocked badges since the last visit.
    expect(
      find.textContaining(RegExp('lencana baru', caseSensitive: false)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('MANTAP!'));
    await settle(tester, 3);
    await tester.tap(find.text('MANTAP!'));
    await settle(tester, 8);
    final saved = GameLocalState.decode(
      store.values[GameLocalState.storageKey],
    );
    expect(saved.celebrated, contains('goal:2026-09-23'));
    await settle(tester, 8);
    expect(find.byType(CelebrationScreen), findsNothing);
  });
}
