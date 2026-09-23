import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/forecast/forecast_state.dart';

import '../budgets/finance_test_harness.dart';

void main() {
  setUpAll(loadGhinaFonts);

  test('projectBalance applies planned items, bills and history per day', () {
    final f = Forecast(
      month: const YearMonth(2026, 10),
      planned: [
        PlannedTransaction(
          id: 'a',
          type: TxType.income,
          amount: 1000,
          date: DateTime(2026, 10, 1),
          done: false,
          createdAt: t0,
          updatedAt: t0,
        ),
        PlannedTransaction(
          id: 'b',
          type: TxType.expense,
          amount: 300,
          date: DateTime(2026, 10, 10),
          done: false,
          createdAt: t0,
          updatedAt: t0,
        ),
      ],
      subscriptionItems: [
        ForecastSubscriptionItem(
          subscription: subscription('s', DateTime(2026, 10, 5), amount: 100),
          date: DateTime(2026, 10, 5),
        ),
      ],
      averages: [CategoryAverage(category: category('c'), avg: 310)],
      historyMonths: 3,
    );
    final p = projectBalance(f, const ForecastSources(), 500);
    expect(p, hasLength(32));
    expect(p.last.balance, 500 + 1000 - 300 - 100);
    expect(p[5].event, isTrue);
    final withHistory = projectBalance(
      f,
      const ForecastSources(history: true),
      500,
    );
    expect(withHistory.last.balance, closeTo(1100 - 310, 0.001));
    final none = projectBalance(
      f,
      const ForecastSources(manual: false, subscriptions: false),
      500,
    );
    expect(none.last.balance, 500);
  });

  group('ForecastPage', () {
    testWidgets('shows next month projection, planned items and bills', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/forecast', size: const Size(390, 1600));
      expect(find.text('Oktober 2026'), findsOneWidget);
      expect(find.text('Rencana kamu'), findsOneWidget);
      expect(find.text('Pajak motor'), findsOneWidget);
      expect(find.textContaining('SALDO AKHIR OKT'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -1600));
      await settle(tester);
      expect(find.text('Dari langganan'), findsOneWidget);
      expect(
        find.text('Perkiraan dari riwayat'),
        findsNothing,
      ); // history off by default
      expect(tester.takeException(), isNull);
    });

    testWidgets('source toggle hides planned items', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/forecast');
      await tester.tap(find.text('Rencana · 4'));
      await settle(tester);
      expect(find.text('Pajak motor'), findsNothing);
    });

    testWidgets('empty month invites to add a plan', (tester) async {
      final h = FinanceHarness();
      await pumpScreen(tester, h, '/forecast');
      expect(
        find.text('Belum ada perkiraan buat Oktober 2026'),
        findsOneWidget,
      );
    });

    testWidgets('mark done and convert to a real transaction', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/forecast', size: const Size(390, 1600));
      await tester.tap(find.bySemanticsLabel('Tandai selesai').first);
      await settle(tester);
      expect(h.planned.s.items['p-salary']!.done, isTrue);

      await tester.tap(find.text('JADIKAN TRANSAKSI').first);
      await settle(tester);
      await tester.tap(find.text('JADIKAN TRANSAKSI').last);
      await settle(tester, 40);
      expect(
        h.transactions.s.items.values.where((t) => t.note == 'Pajak motor'),
        hasLength(1),
      );
      expect(h.planned.s.items.containsKey('p-tax'), isFalse);
      await settle(tester, 30);
    });

    testWidgets('small phone with large text does not overflow', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(
        tester,
        h,
        '/forecast',
        size: const Size(360, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('PlannedFormPage', () {
    testWidgets('validation and create', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/forecast/new');
      await tester.tap(find.text('SIMPAN'));
      await settle(tester);
      expect(find.text('Tulis dulu ini rencana apa, ya'), findsOneWidget);
      expect(find.text('Isi nominalnya dulu, ya'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Servis motor');
      await tester.enterText(find.byType(TextFormField).at(1), '350000');
      await tester.tap(find.text('SIMPAN'));
      await settle(tester);
      final p = h.planned.s.items.values
          .where((p) => p.note == 'Servis motor')
          .single;
      expect(p.amount, 350000);
      expect(p.type, TxType.expense);
      expect(p.date, DateTime(2026, 10, 1));
    });

    testWidgets('edit and delete', (tester) async {
      final h = FinanceHarness()..seedRich();
      final router = await pumpScreen(tester, h, '/forecast/p-gift');
      expect(find.text('Kado nikahan Rani'), findsOneWidget);
      await tester.tap(find.byTooltip('Hapus'));
      await settle(tester);
      await tester.tap(find.text('HAPUS'));
      await settle(tester);
      expect(h.planned.s.items.containsKey('p-gift'), isFalse);
      expect(router.state.uri.toString(), '/');
    });
  });

  group('screenshots', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('forecast $mode', (tester) async {
        final h = FinanceHarness()..seedRich();
        await pumpScreen(tester, h, '/forecast', dark: dark);
        await shot(tester, 'forecast_$mode');
        await pumpScreen(
          tester,
          h,
          '/forecast',
          dark: dark,
          size: const Size(390, 2400),
        );
        await shot(tester, 'forecast_full_$mode');
        await pumpScreen(tester, h, '/forecast/new', dark: dark);
        await shot(tester, 'forecast_form_$mode');
        await pumpScreen(tester, FinanceHarness(), '/forecast', dark: dark);
        await shot(tester, 'forecast_empty_$mode');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
