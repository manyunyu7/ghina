import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

import '../transactions/_feature_harness.dart';
import 'wallets_test.dart' show addWallet;

Future<List<TransactionView>> _txs(WidgetTester tester, ProviderContainer c) =>
    real(
      tester,
      () =>
          c.read(watchTransactionsUseCaseProvider)(TransactionFilter.all).first,
    );

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'wallet edit → Sesuaikan saldo: enter real balance, see the difference, save',
    (tester) async {
      final c = makeContainer();
      final w = await addWallet(
        tester,
        c,
        const WalletInput(name: 'BCA', initialBalance: 1000000),
      );
      await pumpApp(tester, c, '/wallets/${w.id}');
      await tester.ensureVisible(find.byKey(const ValueKey('wallet-adjust')));
      await tester.tap(find.byKey(const ValueKey('wallet-adjust')));
      await settle(tester);
      expect(find.text('Saldo di Ghina'), findsOneWidget);
      expect(find.text('+Rp 0'), findsNothing);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('adjust-amount')),
          matching: find.byType(EditableText),
        ),
        '987500',
      );
      await settle(tester);
      expect(find.text('-Rp 12.500'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('adjust-save')));
      await tester.tap(find.byKey(const ValueKey('adjust-save')));
      await settle(tester, 6);

      final list = await _txs(tester, c);
      expect(list.single.type, TxType.adjustment);
      expect(list.single.amount, -12500);
      expect(
        list.single.transaction.note,
        'Penyesuaian saldo: Rp 1.000.000 → Rp 987.500',
      );
      final wallet = await real(
        tester,
        () => c.read(walletRepositoryProvider).getById(w.id),
      );
      expect(wallet!.balance, 987500);
      await tearDownApp(tester, c);
    },
  );

  testWidgets('same balance → nothing to save', (tester) async {
    final c = makeContainer();
    final w = await addWallet(
      tester,
      c,
      const WalletInput(name: 'Tunai', initialBalance: 50000),
    );
    await pumpApp(tester, c, '/wallets/${w.id}');
    await tester.ensureVisible(find.byKey(const ValueKey('wallet-adjust')));
    await tester.tap(find.byKey(const ValueKey('wallet-adjust')));
    await settle(tester);
    expect(
      find.text('Saldonya sudah sama. Nggak ada yang perlu disesuaikan.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('adjust-save')));
    await tester.tap(find.byKey(const ValueKey('adjust-save')));
    await settle(tester);
    expect(await _txs(tester, c), isEmpty);
    await tearDownApp(tester, c);
  });

  testWidgets(
    'Riwayat lists the wallet history incl. adjustments and transfers in',
    (tester) async {
      final c = makeContainer();
      final a = await addWallet(
        tester,
        c,
        const WalletInput(name: 'Tunai', initialBalance: 100000),
      );
      final b = await addWallet(
        tester,
        c,
        const WalletInput(name: 'BCA', initialBalance: 500000),
      );
      await real(tester, () async {
        await c.read(adjustWalletBalanceProvider)(a.id, 90000);
        await c.read(createTransactionProvider)(
          TransactionInput(
            type: TxType.transfer,
            amount: 20000,
            walletId: b.id,
            toWalletId: a.id,
            date: testNow,
          ),
        );
        await c.read(createTransactionProvider)(
          TransactionInput(
            type: TxType.expense,
            amount: 7000,
            walletId: b.id,
            note: 'Parkir',
            date: testNow,
          ),
        );
      });
      final router = await pumpApp(tester, c, '/wallets');
      await settle(tester, 6);
      await tester.ensureVisible(
        find.byKey(ValueKey('wallet-history-${a.id}')),
      );
      await tester.tap(find.byKey(ValueKey('wallet-history-${a.id}')));
      await settle(tester, 6);
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/wallets/${a.id}/history',
      );
      expect(find.text('Riwayat Tunai'), findsOneWidget);
      expect(find.text('Penyesuaian saldo'), findsWidgets);
      expect(find.text('-Rp 10.000'), findsOneWidget);
      expect(find.text('Transfer ke Tunai'), findsOneWidget);
      expect(find.text('Parkir'), findsNothing);
      // Month summary ignores the adjustment (the transfer isn't income either).
      expect(
        tester
            .widget<MoneyText>(find.byKey(const ValueKey('month-net')))
            .amount,
        0,
      );
      await tearDownApp(tester, c);
    },
  );

  testWidgets('transactions tab: adjustment filter chip and edit', (
    tester,
  ) async {
    final c = makeContainer();
    final a = await addWallet(
      tester,
      c,
      const WalletInput(name: 'Tunai', initialBalance: 100000),
    );
    await real(tester, () async {
      await c.read(adjustWalletBalanceProvider)(a.id, 104000);
      await c.read(createTransactionProvider)(
        TransactionInput(
          type: TxType.expense,
          amount: 7000,
          walletId: a.id,
          note: 'Parkir',
          date: testNow,
        ),
      );
    });
    await pumpApp(tester, c, '/transactions');
    expect(find.text('+Rp 4.000'), findsOneWidget);
    expect(find.text('Parkir'), findsOneWidget);
    await tester.ensureVisible(find.text('Penyesuaian saldo').first);
    // The type chip is the last "Penyesuaian saldo" in the chip row.
    final chip = find.ancestor(
      of: find.text('Penyesuaian saldo'),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'ChunkyChip',
      ),
    );
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await settle(tester);
    expect(find.text('Parkir'), findsNothing);
    expect(find.text('+Rp 4.000'), findsOneWidget);

    // Tap → edit form in adjustment mode; flip the sign and save.
    final row = find.text('Rp 100.000 → Rp 104.000 · Tunai · 12.00');
    expect(row, findsOneWidget);
    await tester.tap(row);
    await settle(tester, 6);
    expect(find.text('Penyesuaian saldo'), findsWidgets);
    expect(find.byKey(const ValueKey('adj-info')), findsOneWidget);
    await tester.tap(find.text('Kurangi saldo'));
    await settle(tester);
    await tester.tap(find.text('SIMPAN PERUBAHAN'));
    await settle(tester, 6);
    final list = await _txs(tester, c);
    final adj = list.firstWhere((v) => v.type == TxType.adjustment);
    expect(adj.amount, -4000);
    expect(adj.transaction.categoryId, isNull);
    await tearDownApp(tester, c);
  });
}
