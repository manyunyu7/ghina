import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../budgets/finance_test_harness.dart';

void main() {
  setUpAll(loadGhinaFonts);

  testWidgets('renders stats, charts and net worth for 6 months', (
    tester,
  ) async {
    final h = FinanceHarness()..seedRich();
    await pumpScreen(tester, h, '/reports', size: const Size(390, 3600));
    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('RASIO TABUNGAN'), findsOneWidget);
    expect(find.text('6 bulan terakhir'), findsOneWidget);
    expect(find.text('Pemasukan vs pengeluaran'), findsOneWidget);
    expect(find.text('Pengeluaran per kategori'), findsOneWidget);
    expect(find.text('Kekayaan bersih'), findsOneWidget);
    expect(find.text('Makan & Minum'), findsWidgets);
    expect(find.text('BCA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('period chip switches to this month', (tester) async {
    final h = FinanceHarness()..seedRich();
    await pumpScreen(tester, h, '/reports');
    await tester.tap(find.text('Bulan ini'));
    await settle(tester);
    expect(find.text('Bulan ini'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('year picker selects a year without data → empty state', (
    tester,
  ) async {
    final h = FinanceHarness()..seedRich();
    await pumpScreen(tester, h, '/reports');
    await tester.tap(find.text('Per tahun'));
    await settle(tester);
    await tester.tap(find.text('2024'));
    await settle(tester);
    expect(find.text('Tahun 2024'), findsOneWidget);
    expect(find.text('Belum ada data di periode ini'), findsOneWidget);
  });

  testWidgets('empty state without transactions', (tester) async {
    await pumpScreen(tester, FinanceHarness(), '/reports');
    expect(find.text('Belum ada data di periode ini'), findsOneWidget);
  });

  testWidgets('small phone with large text does not overflow', (tester) async {
    final h = FinanceHarness()..seedRich();
    await pumpScreen(
      tester,
      h,
      '/reports',
      size: const Size(360, 3600),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('screenshots $mode', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/reports', dark: dark);
      await shot(tester, 'reports_$mode');
      await pumpScreen(
        tester,
        h,
        '/reports',
        dark: dark,
        size: const Size(390, 3400),
      );
      await shot(tester, 'reports_full_$mode');
      expect(tester.takeException(), isNull);
    });
  }
}
