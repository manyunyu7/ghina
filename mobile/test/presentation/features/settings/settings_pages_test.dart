import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/features/settings/pages/settings_page.dart';
import 'package:ghina/presentation/features/settings/pages/sync_page.dart';
import 'package:ghina/presentation/features/shell/app_shell.dart';
import 'package:ghina/presentation/state/session_controller.dart';

import '../shell/test_utils.dart';

void main() {
  group('SettingsPage', () {
    testWidgets('shows the profile and saves name + currency', (tester) async {
      final session = FakeSession(const SignedIn(testUser));
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: pageOverrides(fakeSession: session),
      );
      expect(find.text('Ghina Putri'), findsWidgets);
      expect(find.text('ghina@contoh.id'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('settings-name')),
        'Ghina P',
      );
      await tester.tap(find.text('USD'));
      await settle(tester, 2);
      await tester.tap(find.text('SIMPAN PROFIL'));
      await settle(tester, 6);
      expect(session.calls, ['updateProfile:Ghina P:USD']);
      await settle(tester, 30);
    });

    testWidgets('offline profile save explains it needs internet', (
      tester,
    ) async {
      final session = FakeSession(const SignedIn(testUser))
        ..nextResult = const Err(NetworkFailure());
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: pageOverrides(fakeSession: session),
      );
      await tester.enterText(find.byKey(const ValueKey('settings-name')), '');
      await tester.enterText(
        find.byKey(const ValueKey('settings-name')),
        'Baru',
      );
      await tester.tap(find.text('SIMPAN PROFIL'));
      await settle(tester, 4);
      expect(find.textContaining('butuh internet'), findsOneWidget);
    });

    testWidgets('empty name is rejected', (tester) async {
      final session = FakeSession(const SignedIn(testUser));
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: pageOverrides(fakeSession: session),
      );
      await tester.enterText(find.byKey(const ValueKey('settings-name')), '  ');
      await tester.pump();
      await tester.tap(find.text('SIMPAN PROFIL'));
      await settle(tester, 4);
      expect(
        find.textContaining('jangan kosong', findRichText: true),
        findsOneWidget,
      );
      expect(session.calls, isEmpty);
    });

    testWidgets('changes the daily goal', (tester) async {
      final store = InMemoryGameStore();
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: pageOverrides(store: store),
      );
      await scrollTo(tester, find.byKey(const ValueKey('goal-intens')));
      await tester.tap(find.byKey(const ValueKey('goal-intens')));
      await settle(tester, 6);
      final saved = GameLocalState.decode(
        store.values[GameLocalState.storageKey],
      );
      expect(saved.currentGoal, DailyGoalLevel.intens);
      await settle(tester, 30);
    });

    testWidgets('sign out asks first and warns about pending changes', (
      tester,
    ) async {
      final session = FakeSession(const SignedIn(testUser));
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: pageOverrides(
          fakeSession: session,
          sync: const SyncStatus(phase: SyncPhase.offline, pendingCount: 4),
        ),
      );
      await scrollTo(tester, find.text('KELUAR'));
      await tester.tap(find.text('KELUAR'));
      await settle(tester, 6);
      expect(find.textContaining('4 perubahan'), findsOneWidget);
      await tester.tap(find.text('BATAL'));
      await settle(tester, 6);
      expect(session.calls, isEmpty);

      await tester.tap(find.text('KELUAR'));
      await settle(tester, 6);
      await tester.tap(find.text('KELUAR').last);
      await settle(tester, 6);
      expect(session.calls, ['signOut']);
    });

    testWidgets('re-download data after confirming', (tester) async {
      final sync = FakeSyncService();
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: pageOverrides(syncService: sync),
      );
      await scrollTo(tester, find.text('Unduh ulang data'));
      await tester.tap(find.text('Unduh ulang data'));
      await settle(tester, 6);
      await tester.tap(find.text('UNDUH ULANG'));
      await settle(tester, 6);
      expect(sync.resetCalls, 1);
      await settle(tester, 30);
    });

    testWidgets('reset game progress warns that onboarding restarts', (
      tester,
    ) async {
      await pumpPage(tester, const SettingsPage(), overrides: pageOverrides());
      await scrollTo(tester, find.text('Reset progres game'));
      await tester.tap(find.text('Reset progres game'));
      await settle(tester, 6);
      expect(find.text('Reset progres game?'), findsOneWidget);
      expect(find.textContaining('onboarding'), findsWidgets);
      await tester.tap(find.text('BATAL'));
      await settle(tester, 6);
    });
  });

  group('SyncPage', () {
    testWidgets('shows status, pending count and last error; syncs on demand', (
      tester,
    ) async {
      final sync = FakeSyncService();
      await pumpPage(
        tester,
        const SyncPage(),
        overrides: pageOverrides(
          syncService: sync,
          sync: SyncStatus(
            phase: SyncPhase.error,
            pendingCount: 3,
            lastSyncAt: testNow.subtract(const Duration(minutes: 5)),
            lastError: 'Kategori tidak ditemukan',
          ),
        ),
      );
      expect(find.text('Sinkron lagi bermasalah'), findsOneWidget);
      expect(find.text('5 menit lalu'), findsOneWidget);
      expect(find.text('3 perubahan'), findsOneWidget);
      expect(find.text('Kategori tidak ditemukan'), findsOneWidget);

      await tester.tap(find.text('SINKRON SEKARANG'));
      await settle(tester, 4);
      expect(sync.syncCalls, 1);
      expect(find.textContaining('sinkron!'), findsOneWidget);
      await settle(tester, 30);
    });

    testWidgets('offline copy is friendly', (tester) async {
      await pumpPage(
        tester,
        const SyncPage(),
        overrides: pageOverrides(
          sync: const SyncStatus(phase: SyncPhase.offline),
        ),
      );
      expect(find.text('Kamu lagi offline'), findsOneWidget);
      expect(find.text('Belum pernah'), findsOneWidget);
    });
  });

  group('OfflineBanner', () {
    testWidgets('appears only while offline and opens /sync', (tester) async {
      await pumpPage(
        tester,
        const Scaffold(body: Column(children: [Spacer(), OfflineBanner()])),
        overrides: pageOverrides(
          sync: const SyncStatus(phase: SyncPhase.offline, pendingCount: 2),
        ),
      );
      expect(find.textContaining('2 perubahan'), findsOneWidget);
      await tester.tap(find.textContaining('Mode offline'));
      await settle(tester, 4);
      expect(find.text('ROUTE:/sync'), findsOneWidget);
    });

    testWidgets('hidden when online', (tester) async {
      await pumpPage(
        tester,
        const Scaffold(body: Column(children: [Spacer(), OfflineBanner()])),
        overrides: pageOverrides(),
      );
      expect(find.textContaining('Mode offline'), findsNothing);
    });
  });
}
