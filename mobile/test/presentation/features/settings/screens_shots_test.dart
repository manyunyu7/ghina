import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/auth/pages/login_page.dart';
import 'package:ghina/presentation/features/auth/pages/onboarding_page.dart';
import 'package:ghina/presentation/features/auth/pages/register_page.dart';
import 'package:ghina/presentation/features/settings/pages/settings_page.dart';
import 'package:ghina/presentation/features/settings/pages/sync_page.dart';
import 'package:ghina/presentation/state/session_controller.dart';

import '../../../domain/fakes.dart'
    show FakeWalletRepository, FakeCategoryRepository, FakeUnitOfWork;
import '../../design_system/_helpers.dart';
import '../shell/test_utils.dart';

/// Visual review of auth, onboarding, settings and sync pages (light/dark, and a
/// small phone at 1.3× text). Set GHINA_SHOTS_DIR to write PNGs.
void main() {
  setUpAll(loadGhinaFonts);
  const key = ValueKey('shot');

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 10);
    final error = tester.takeException();
    await saveShot(tester, key, name);
    expect(error, isNull);
  }

  List<Override> onboardingRepos() => [
    walletRepositoryProvider.overrideWithValue(FakeWalletRepository()),
    categoryRepositoryProvider.overrideWithValue(FakeCategoryRepository()),
    unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
  ];

  final variants = <(String, bool, Size, double)>[
    ('light', false, const Size(390, 844), 1),
    ('dark', true, const Size(390, 844), 1),
    ('small_text130', false, const Size(360, 640), 1.3),
  ];

  for (final (name, dark, size, scale) in variants) {
    testWidgets('login ($name)', (tester) async {
      await pumpPage(
        tester,
        const LoginPage(),
        overrides: pageOverrides(
          fakeSession: FakeSession(const SignedOut(expired: true)),
        ),
        dark: dark,
        size: size,
        textScale: scale,
        boundaryKey: key,
      );
      await shot(tester, 'auth_login_$name');
    });

    testWidgets('register ($name)', (tester) async {
      await pumpPage(
        tester,
        const RegisterPage(),
        overrides: pageOverrides(fakeSession: FakeSession(const SignedOut())),
        dark: dark,
        size: size,
        textScale: scale,
        boundaryKey: key,
      );
      await shot(tester, 'auth_register_$name');
    });

    testWidgets('onboarding steps ($name)', (tester) async {
      await pumpPage(
        tester,
        const OnboardingPage(),
        overrides: pageOverrides(extra: onboardingRepos()),
        dark: dark,
        size: size,
        textScale: scale,
        boundaryKey: key,
      );
      await shot(tester, 'auth_onboarding1_$name');
      await tester.tap(find.text('MULAI'));
      await shot(tester, 'auth_onboarding2_$name');
      await tester.tap(find.text('LANJUT'));
      await shot(tester, 'auth_onboarding3_$name');
      await tester.tap(find.text('BUAT DOMPET'));
      await settle(tester, 10);
      await tester.tap(find.text('LANJUT'));
      await shot(tester, 'auth_onboarding4_$name');
      await settle(tester, 30);
    });

    testWidgets('settings ($name)', (tester) async {
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: pageOverrides(
          sync: SyncStatus(phase: SyncPhase.idle, lastSyncAt: testNow),
        ),
        dark: dark,
        size: Size(size.width, size.height * 2.3),
        textScale: scale,
        boundaryKey: key,
      );
      await shot(tester, 'settings_$name');
    });

    testWidgets('sync ($name)', (tester) async {
      await pumpPage(
        tester,
        const SyncPage(),
        overrides: pageOverrides(
          sync: SyncStatus(
            phase: SyncPhase.offline,
            pendingCount: 3,
            lastSyncAt: testNow.subtract(const Duration(hours: 2)),
            lastError: 'Tidak ada koneksi internet',
          ),
        ),
        dark: dark,
        size: Size(size.width, size.height * 1.6),
        textScale: scale,
        boundaryKey: key,
      );
      await shot(tester, 'settings_sync_$name');
    });
  }
}
