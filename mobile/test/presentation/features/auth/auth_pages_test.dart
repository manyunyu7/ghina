import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/usecases/usecases.dart' show defaultCategories;
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/features/auth/pages/login_page.dart';
import 'package:ghina/presentation/features/auth/pages/onboarding_page.dart';
import 'package:ghina/presentation/features/auth/pages/register_page.dart';
import 'package:ghina/presentation/state/session_controller.dart';

import '../../../domain/fakes.dart'
    show FakeWalletRepository, FakeCategoryRepository, FakeUnitOfWork;
import '../shell/test_utils.dart';

void main() {
  group('LoginPage', () {
    testWidgets('validates the fields before signing in', (tester) async {
      final session = FakeSession(const SignedOut());
      await pumpPage(
        tester,
        const LoginPage(),
        overrides: pageOverrides(fakeSession: session),
      );
      await tester.tap(find.text('MASUK'));
      await settle(tester, 4);
      expect(find.text('Email-nya diisi dulu, ya'), findsOneWidget);
      expect(find.text('Kata sandinya diisi dulu, ya'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'bukan-email',
      );
      await tester.tap(find.text('MASUK'));
      await settle(tester, 4);
      expect(find.text('Format email-nya kurang pas'), findsOneWidget);
      expect(session.calls, isEmpty);
    });

    testWidgets('signs in and shows server errors', (tester) async {
      final session = FakeSession(const SignedOut())
        ..nextResult = const Err(
          UnauthorizedFailure('Email atau kata sandi salah'),
        );
      await pumpPage(
        tester,
        const LoginPage(),
        overrides: pageOverrides(fakeSession: session),
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'ghina@contoh.id',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'rahasia',
      );
      await tester.tap(find.text('MASUK'));
      await settle(tester, 4);
      expect(session.calls, ['signIn:ghina@contoh.id']);
      expect(find.text('Email atau kata sandi salah'), findsOneWidget);
    });

    testWidgets('explains an expired session', (tester) async {
      await pumpPage(
        tester,
        const LoginPage(),
        overrides: pageOverrides(
          fakeSession: FakeSession(const SignedOut(expired: true)),
        ),
      );
      expect(find.text('Sesi kamu berakhir'), findsOneWidget);
      expect(find.textContaining('perlu masuk lagi'), findsOneWidget);
    });

    testWidgets('links to register', (tester) async {
      await pumpPage(
        tester,
        const LoginPage(),
        overrides: pageOverrides(fakeSession: FakeSession(const SignedOut())),
      );
      await tester.ensureVisible(find.text('Daftar'));
      await tester.tap(find.text('Daftar'));
      await settle(tester, 4);
      expect(find.text('ROUTE:/register'), findsOneWidget);
    });
  });

  group('RegisterPage', () {
    testWidgets('requires a name and a 6+ char password, then registers', (
      tester,
    ) async {
      final session = FakeSession(const SignedOut());
      await pumpPage(
        tester,
        const RegisterPage(),
        overrides: pageOverrides(fakeSession: session),
      );
      await tester.enterText(
        find.byKey(const ValueKey('register-email')),
        'baru@contoh.id',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register-password')),
        '123',
      );
      await tester.ensureVisible(find.text('DAFTAR'));
      await tester.tap(find.text('DAFTAR'));
      await settle(tester, 4);
      expect(find.text('Namanya siapa, nih?'), findsOneWidget);
      expect(find.text('Minimal 6 karakter biar aman'), findsOneWidget);
      expect(session.calls, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('register-name')),
        'Budi',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register-password')),
        'rahasia123',
      );
      await tester.ensureVisible(find.text('DAFTAR'));
      await tester.tap(find.text('DAFTAR'));
      await settle(tester, 4);
      expect(session.calls, ['register:Budi:baru@contoh.id']);
    });
  });

  group('OnboardingPage', () {
    testWidgets('goal → seeds categories → first wallet → completes onboarding', (
      tester,
    ) async {
      final wallets = FakeWalletRepository();
      final categories = FakeCategoryRepository();
      final store = InMemoryGameStore();
      final sync = FakeSyncService();
      await pumpPage(
        tester,
        const OnboardingPage(),
        overrides: pageOverrides(
          store: store,
          syncService: sync,
          extra: [
            walletRepositoryProvider.overrideWithValue(wallets),
            categoryRepositoryProvider.overrideWithValue(categories),
            unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
          ],
        ),
      );

      expect(find.textContaining('aku Ghina'), findsOneWidget);
      await tester.tap(find.text('MULAI'));
      await settle(tester, 6);

      await tester.tap(find.byKey(const ValueKey('goal-serius')));
      await settle(tester, 2);
      await tester.tap(find.text('LANJUT'));
      await settle(tester, 10);

      // Setup: synced first, then seeded the default categories (none existed).
      expect(sync.syncCalls, 1);
      expect(categories.s.items, hasLength(defaultCategories.length));
      expect(find.text('BUAT DOMPET'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('wallet-balance')),
        '150.000',
      );
      await tester.tap(find.text('BUAT DOMPET'));
      await settle(tester, 10);
      expect(wallets.s.items.values.single.balance, 150000);
      expect(wallets.s.items.values.single.name, 'Dompet Tunai');

      await tester.tap(find.text('LANJUT'));
      await settle(tester, 6);
      expect(find.text('Target harian: Serius'), findsOneWidget);
      await tester.tap(find.text('AYO MULAI!'));
      await settle(tester, 6);

      final saved = GameLocalState.decode(
        store.values[GameLocalState.storageKey],
      );
      expect(saved.onboardingDone, isTrue);
      expect(saved.currentGoal, DailyGoalLevel.serius);
    });

    testWidgets('skips the wallet form when a wallet already exists', (
      tester,
    ) async {
      final wallets = FakeWalletRepository();
      final categories = FakeCategoryRepository();
      await wallets.save(wallet('w1', 'BCA', 10));
      await categories.save(food);
      await pumpPage(
        tester,
        const OnboardingPage(),
        overrides: pageOverrides(
          extra: [
            walletRepositoryProvider.overrideWithValue(wallets),
            categoryRepositoryProvider.overrideWithValue(categories),
            unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
          ],
        ),
      );
      await tester.tap(find.text('MULAI'));
      await settle(tester, 6);
      await tester.tap(find.text('LANJUT'));
      await settle(tester, 10);
      expect(find.text('BUAT DOMPET'), findsNothing);
      expect(find.text('BCA'), findsOneWidget);
      expect(categories.s.items, hasLength(1));
    });
  });
}
