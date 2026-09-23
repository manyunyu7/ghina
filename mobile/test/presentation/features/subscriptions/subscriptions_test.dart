import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';

import '../budgets/finance_test_harness.dart';

void main() {
  setUpAll(loadGhinaFonts);

  group('SubscriptionsPage', () {
    testWidgets('shows monthly total, due chips and paused section', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/subscriptions');
      expect(find.text('LANGGANAN PER BULAN'), findsOneWidget);
      expect(find.text('Tagihan berikutnya'), findsOneWidget);
      expect(find.text('Hari ini'), findsOneWidget); // iCloud due today
      expect(find.text('2 hari lagi'), findsOneWidget); // Netflix on the 25th
      await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
      await settle(tester);
      expect(find.text('Dijeda'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state', (tester) async {
      final h = FinanceHarness();
      await pumpScreen(tester, h, '/subscriptions');
      expect(find.text('Belum ada langganan'), findsOneWidget);
    });

    testWidgets('quick pay creates an expense and advances next billing', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/subscriptions');
      await tester.tap(find.text('BAYAR').first); // iCloud (first due)
      await settle(tester);
      expect(find.text('Bayar Apple iCloud?'), findsOneWidget);
      await tester.tap(find.text('BAYAR').last);
      await settle(tester, 30);
      final paid = h.transactions.s.items.values.where(
        (t) => t.note == 'Apple iCloud',
      );
      expect(paid.single.amount, 15000);
      expect(paid.single.walletId, 'gopay');
      expect(
        h.subscriptions.s.items['icloud']!.nextBilling,
        DateTime(2026, 10, 23),
      );
      await settle(tester, 30);
    });

    testWidgets('small phone with large text does not overflow', (
      tester,
    ) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(
        tester,
        h,
        '/subscriptions',
        size: const Size(360, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SubscriptionFormPage', () {
    testWidgets('validation errors', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/subscriptions/new');
      await tester.tap(find.text('SIMPAN'));
      await settle(tester);
      expect(find.text('Kasih nama langganannya dulu, ya'), findsOneWidget);
      expect(find.text('Isi nominal tagihannya dulu, ya'), findsOneWidget);
    });

    testWidgets('preset + amount creates a subscription', (tester) async {
      final h = FinanceHarness()..seedRich();
      await pumpScreen(tester, h, '/subscriptions/new');
      await tester.tap(find.text('Spotify'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).at(1), '54990');
      await tester.tap(find.text('SIMPAN'));
      await settle(tester);
      final created = h.subscriptions.s.items.values.where(
        (s) => s.name == 'Spotify' && s.id != 'spotify',
      );
      expect(created.single.amount, 54990);
      expect(created.single.icon, 'music');
      expect(created.single.cycle, BillingCycle.monthly);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('edit loads values and deletes', (tester) async {
      final h = FinanceHarness()..seedRich();
      final router = await pumpScreen(tester, h, '/subscriptions/netflix');
      expect(find.text('Ubah langganan'), findsOneWidget);
      expect(find.text('186.000'), findsOneWidget);
      await tester.tap(find.byTooltip('Hapus'));
      await settle(tester);
      await tester.tap(find.text('HAPUS'));
      await settle(tester);
      expect(h.subscriptions.s.items.containsKey('netflix'), isFalse);
      expect(router.state.uri.toString(), '/');
    });
  });

  group('screenshots', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('subscriptions $mode', (tester) async {
        final h = FinanceHarness()..seedRich();
        await pumpScreen(tester, h, '/subscriptions', dark: dark);
        await shot(tester, 'subscriptions_list_$mode');
        await pumpScreen(
          tester,
          h,
          '/subscriptions',
          dark: dark,
          size: const Size(390, 1900),
        );
        await shot(tester, 'subscriptions_list_full_$mode');
        await pumpScreen(
          tester,
          h,
          '/subscriptions/new',
          dark: dark,
          size: const Size(390, 2000),
        );
        await shot(tester, 'subscriptions_form_$mode');
        await pumpScreen(
          tester,
          FinanceHarness(),
          '/subscriptions',
          dark: dark,
        );
        await shot(tester, 'subscriptions_empty_$mode');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
