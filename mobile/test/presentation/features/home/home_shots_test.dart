import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/home/pages/home_page.dart';

import '../../design_system/_helpers.dart';
import '../shell/test_utils.dart';

/// Renders Beranda in light/dark (viewport + full length) and on a small phone with
/// large text. Set GHINA_SHOTS_DIR to write PNGs.
void main() {
  setUpAll(loadGhinaFonts);
  const key = ValueKey('shot');

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('home renders ($mode)', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: pageOverrides(events: streakEvents(6)),
        dark: dark,
        boundaryKey: key,
      );
      await settle(tester, 10);
      final error = tester.takeException();
      await saveShot(tester, key, 'home_$mode');
      expect(error, isNull);
    });

    testWidgets('home full length ($mode)', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: pageOverrides(events: streakEvents(6)),
        dark: dark,
        size: const Size(390, 2150),
        boundaryKey: key,
      );
      await settle(tester, 10);
      final error = tester.takeException();
      await saveShot(tester, key, 'home_full_$mode');
      expect(error, isNull);
    });
  }

  testWidgets('home empty account (light)', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: pageOverrides(
        dashboard: sampleDashboard(empty: true),
        budgets: sampleBudgets(empty: true),
      ),
      size: const Size(390, 1700),
      boundaryKey: key,
    );
    await settle(tester, 10);
    final error = tester.takeException();
    await saveShot(tester, key, 'home_empty_light');
    expect(error, isNull);
  });

  testWidgets('home fits a small phone with large text', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: pageOverrides(events: streakEvents(12)),
      size: const Size(360, 2400),
      textScale: 1.3,
      boundaryKey: key,
    );
    await settle(tester, 10);
    final error = tester.takeException();
    await saveShot(tester, key, 'home_small_text130');
    expect(error, isNull);
  });
}
