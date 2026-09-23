import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';

import 'finance_test_harness.dart';

void main() {
  setUpAll(loadGhinaFonts);

  group('BudgetsPage', () {
    testWidgets('lists budgets with totals, hearts and variance', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/budgets');

      expect(find.text('Anggaran'), findsOneWidget);
      expect(find.text('TOTAL BUDGET'), findsOneWidget);
      expect(find.text('Makan & Minum'), findsWidgets);
      expect(find.text('Target'), findsWidgets);
      // Shopping (1.500.000 of 1.500.000 → 900k+700k? odd month 9 → 1.6jt) is over budget.
      expect(find.text('JEBOL'), findsWidgets);
      expect(find.textContaining('hati hilang'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty month invites to set a budget', (tester) async {
      final h = FinanceHarness()..cat('food', 'Makan', '#f97316', 'utensils');
      await pumpScreen(tester, h, '/budgets');
      expect(find.text('Belum ada budget buat September 2026'), findsOneWidget);
      expect(find.text('PASANG BUDGET'), findsWidgets);
    });

    testWidgets('without expense categories asks to create one', (
      tester,
    ) async {
      final h = FinanceHarness();
      await pumpScreen(tester, h, '/budgets');
      expect(find.text('Belum ada kategori pengeluaran'), findsOneWidget);
    });

    testWidgets('month switcher moves to the previous month', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/budgets');
      await tester.tap(find.byTooltip('Bulan sebelumnya'));
      await settle(tester);
      expect(find.text('Agustus 2026'), findsOneWidget);
      expect(find.text('Belum ada budget buat Agustus 2026'), findsOneWidget);
    });

    testWidgets('pull to refresh syncs', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/budgets');
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 400),
        1000,
      );
      await settle(tester);
      expect(h.sync.syncs, 1);
    });

    testWidgets('small phone with large text does not overflow', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(
        tester,
        h,
        '/budgets',
        size: const Size(360, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('BudgetFormPage', () {
    testWidgets('shows friendly validation errors', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/budgets/new');
      await tester.tap(find.text('SIMPAN'));
      await settle(tester);
      expect(find.text('Pilih kategori dulu, ya'), findsOneWidget);
      expect(find.text('Isi nominal budget-nya dulu, ya'), findsOneWidget);
    });

    testWidgets('creates a budget for the picked category', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/budgets/new');
      await tester.tap(find.text('Pilih kategori pengeluaran'));
      await settle(tester);
      await tester.tap(find.text('Hiburan'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField), '400000');
      await settle(tester, 3);
      expect(find.text('400.000'), findsOneWidget);
      await tester.tap(find.text('SIMPAN'));
      await settle(tester);
      final fun = h.budgets.s.items.values.where((b) => b.categoryId == 'fun');
      expect(fun.single.amount, 400000);
      expect(fun.single.month, 9);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('picking an already budgeted category updates it', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/budgets/new');
      await tester.tap(find.text('Pilih kategori pengeluaran'));
      await settle(tester);
      await tester.tap(find.text('Transportasi'));
      await settle(tester);
      expect(find.textContaining('sudah punya budget'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '900000');
      await tester.tap(find.text('PERBARUI'));
      await settle(tester);
      final t = h.budgets.s.items.values
          .where((b) => b.categoryId == 'transport')
          .toList();
      expect(t, hasLength(1));
      expect(t.single.id, 'b-transport');
      expect(t.single.amount, 900000);
    });

    testWidgets('edit loads the budget, saves and deletes', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/budgets/b-food');
      expect(find.text('Makan & Minum'), findsOneWidget);
      expect(find.text('2.500.000'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '3000000');
      await tester.tap(find.text('PERBARUI'));
      await settle(tester);
      expect(h.budgets.s.items['b-food']!.amount, 3000000);

      final router = await pumpScreen(tester, h, '/budgets/b-food');
      await tester.tap(find.byTooltip('Hapus'));
      await settle(tester);
      await tester.tap(find.text('HAPUS'));
      await settle(tester);
      expect(h.budgets.s.items.containsKey('b-food'), isFalse);
      expect(router.state.uri.toString(), '/');
    });
  });

  group('screenshots', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('budgets $mode', (tester) async {
        final h = FinanceHarness()..seedRich();
        await pumpScreen(tester, h, '/budgets', dark: dark);
        await shot(tester, 'budgets_list_$mode');
        await pumpScreen(
          tester,
          h,
          '/budgets',
          dark: dark,
          size: const Size(390, 2400),
        );
        await shot(tester, 'budgets_list_full_$mode');
        await pumpScreen(tester, h, '/budgets/new', dark: dark);
        await shot(tester, 'budgets_form_$mode');
        await pumpScreen(tester, h, '/budgets/b-shop', dark: dark);
        await shot(tester, 'budgets_edit_$mode');
        final empty = FinanceHarness()
          ..cat('food', 'Makan', '#f97316', 'utensils');
        await pumpScreen(tester, empty, '/budgets', dark: dark);
        await shot(tester, 'budgets_empty_$mode');
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('seed sanity', () {
    final h = FinanceHarness()..seedRich();
    expect(
      h.categories.s.items.values.where((c) => c.type == CategoryType.expense),
      hasLength(6),
    );
  });
}
