import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '_feature_harness.dart';

Future<({String cash, String bank, String food})> seed(
  WidgetTester tester,
  ProviderContainer c, {
  bool withTx = true,
}) => real(tester, () async {
  final clock = c.read(clockProvider) as FixedClock;
  final cash = (await c.read(createWalletProvider)(
    const WalletInput(name: 'Tunai', initialBalance: 500000),
  )).valueOrThrow;
  clock.advance(const Duration(seconds: 1));
  final bank = (await c.read(createWalletProvider)(
    const WalletInput(
      name: 'BCA',
      type: WalletType.bank,
      color: '#3b82f6',
      initialBalance: 2000000,
    ),
  )).valueOrThrow;
  final food = (await c.read(createCategoryProvider)(
    const CategoryInput(name: 'Makan', icon: 'utensils', color: '#f97316'),
  )).valueOrThrow;
  if (withTx) {
    await c.read(createTransactionProvider)(
      TransactionInput(
        type: TxType.expense,
        amount: 25000,
        walletId: cash.id,
        categoryId: food.id,
        note: 'Nasi padang',
        date: DateTime(2026, 9, 23, 12),
      ),
    );
    await c.read(createTransactionProvider)(
      TransactionInput(
        type: TxType.income,
        amount: 5000000,
        walletId: bank.id,
        note: 'Gaji',
        date: DateTime(2026, 9, 1, 9),
      ),
    );
  }
  return (cash: cash.id, bank: bank.id, food: food.id);
});

Future<List<Transaction>> allTx(WidgetTester tester, ProviderContainer c) =>
    real(tester, () async {
      final list = await c
          .read(watchTransactionsUseCaseProvider)(TransactionFilter.all)
          .first;
      return [for (final v in list) v.transaction];
    });

Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
  for (final k in keys) {
    await tester.tap(
      find.descendant(of: find.byType(AmountKeypad), matching: find.text(k)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('empty: asks to create a wallet first', (tester) async {
    final c = makeContainer();
    await pumpApp(tester, c, '/transactions');
    expect(find.text('Bikin dompet dulu, yuk!'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('empty month with wallets invites to log one', (tester) async {
    final c = makeContainer();
    await seed(tester, c, withTx: false);
    await pumpApp(tester, c, '/transactions');
    expect(find.text('Belum ada transaksi'), findsOneWidget);
    expect(find.text('CATAT TRANSAKSI'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('lists transactions grouped by day with the month summary', (
    tester,
  ) async {
    final c = makeContainer();
    await seed(tester, c);
    await pumpApp(tester, c, '/transactions');
    expect(find.text('Nasi padang'), findsOneWidget);
    expect(find.text('Gaji'), findsOneWidget);
    expect(find.textContaining('HARI INI'), findsOneWidget);
    expect(find.text('+Rp 5.000.000'), findsWidgets);
    expect(find.text('-Rp 25.000'), findsWidgets);

    // Type filter: only income.
    await tester.ensureVisible(find.text('Pemasukan').last);
    await tester.pump();
    await tester.tap(find.text('Pemasukan').last);
    await settle(tester);
    expect(find.text('Nasi padang'), findsNothing);
    expect(find.text('Gaji'), findsOneWidget);

    // Previous month is empty.
    await tester.tap(find.byKey(const ValueKey('month-prev')));
    await settle(tester);
    expect(find.text('Agustus 2026'), findsOneWidget);
    expect(find.text('Nggak ketemu'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('search filters by note', (tester) async {
    final c = makeContainer();
    await seed(tester, c);
    await pumpApp(tester, c, '/transactions');
    await tester.tap(find.byKey(const ValueKey('tx-search-toggle')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'padang');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Nasi padang'), findsOneWidget);
    expect(find.text('Gaji'), findsNothing);
    await tearDownApp(tester, c);
  });

  testWidgets('quick add: amount + category saves an expense and rewards', (
    tester,
  ) async {
    final c = makeContainer();
    final ids = await seed(tester, c, withTx: false);
    await pumpApp(tester, c, '/transactions/new');
    expect(find.text('Catat transaksi'), findsOneWidget);
    // Defaults to the first wallet.
    expect(find.text('Tunai'), findsOneWidget);

    await tapKeys(tester, ['2', '5', '000']);
    await tester.tap(find.text('Makan'));
    await tester.pump();
    await tester.tap(find.text('SIMPAN'));
    // Let the save + reward polling run.
    for (var i = 0; i < 10; i++) {
      await settle(tester, 2);
    }
    final txs = await allTx(tester, c);
    expect(txs, hasLength(1));
    expect(txs.single.amount, 25000);
    expect(txs.single.type, TxType.expense);
    expect(txs.single.walletId, ids.cash);
    expect(txs.single.categoryId, ids.food);
    // Either a +XP toast or a celebration (first transaction achievement).
    final rewarded =
        find.textContaining('XP').evaluate().isNotEmpty ||
        find.textContaining('encapaian').evaluate().isNotEmpty ||
        find.textContaining('Mantap').evaluate().isNotEmpty;
    expect(rewarded, isTrue);
    await tearDownApp(tester, c);
  });

  testWidgets('transfer without destination shows a friendly error', (
    tester,
  ) async {
    final c = makeContainer();
    await seed(tester, c, withTx: false);
    await pumpApp(tester, c, '/transactions/new');
    await tester.tap(find.text('Transfer'));
    await tester.pump(const Duration(milliseconds: 300));
    await tapKeys(tester, ['5', '000']);
    await tester.tap(find.text('SIMPAN'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pilih dompet tujuan dulu'), findsOneWidget);
    expect(await allTx(tester, c), isEmpty);
    await tearDownApp(tester, c);
  });

  testWidgets('edit mode loads the transaction and can delete it', (
    tester,
  ) async {
    final c = makeContainer();
    await seed(tester, c);
    final tx = (await allTx(tester, c)).firstWhere((t) => t.note == 'Gaji');
    await pumpApp(tester, c, '/transactions/${tx.id}');
    expect(find.text('Edit transaksi'), findsOneWidget);
    expect(find.text('Gaji'), findsOneWidget); // note chip
    expect(find.text('BCA'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tx-delete')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hapus transaksi?'), findsOneWidget);
    await tester.tap(find.text('HAPUS'));
    for (var i = 0; i < 3; i++) {
      await settle(tester, 2);
    }
    final left = await allTx(tester, c);
    expect(left.where((t) => t.id == tx.id), isEmpty);
    await tearDownApp(tester, c);
  });

  testWidgets('edit mode saves a changed amount', (tester) async {
    final c = makeContainer();
    await seed(tester, c);
    final tx = (await allTx(
      tester,
      c,
    )).firstWhere((t) => t.note == 'Nasi padang');
    await pumpApp(tester, c, '/transactions/${tx.id}');
    await tapKeys(tester, ['0']); // 25000 -> 250000
    await tester.tap(find.text('SIMPAN PERUBAHAN'));
    for (var i = 0; i < 3; i++) {
      await settle(tester, 2);
    }
    final updated = (await allTx(tester, c)).firstWhere((t) => t.id == tx.id);
    expect(updated.amount, 250000);
    expect(
      await real(
        tester,
        () async => (await c.read(deleteTransactionProvider)(tx.id)).isOk,
      ),
      isTrue,
    );
    await tearDownApp(tester, c);
  });
}
