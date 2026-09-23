// Visual review of the transactions / wallets / categories screens.
//   GHINA_SHOTS_DIR=/some/dir flutter test test/presentation/features/transactions/feature_shots_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

import '_feature_harness.dart';

Future<Map<String, String>> seedRich(
  WidgetTester tester,
  ProviderContainer c,
) => real(tester, () async {
  final clock = c.read(clockProvider) as FixedClock;
  Future<Wallet> w(WalletInput i) async {
    clock.advance(const Duration(seconds: 1));
    return (await c.read(createWalletProvider)(i)).valueOrThrow;
  }

  final cash = await w(
    const WalletInput(name: 'Tunai', initialBalance: 350000, color: '#22c55e'),
  );
  final bca = await w(
    const WalletInput(
      name: 'BCA',
      type: WalletType.bank,
      color: '#3b82f6',
      initialBalance: 4250000,
    ),
  );
  final gopay = await w(
    const WalletInput(
      name: 'GoPay',
      type: WalletType.ewallet,
      color: '#06b6d4',
      initialBalance: 120000,
    ),
  );
  await w(
    const WalletInput(
      name: 'Tabungan lama',
      type: WalletType.savings,
      color: '#64748b',
      initialBalance: 50000,
      archived: true,
    ),
  );
  await c.read(seedDefaultCategoriesProvider)();
  final cats = await c.read(watchCategoriesUseCaseProvider)().first;
  String cat(String n) => cats.firstWhere((x) => x.name == n).id;
  Future<void> tx(
    TxType t,
    double a,
    String wid,
    String? cid,
    String? note,
    DateTime d, {
    String? to,
  }) => c.read(createTransactionProvider)(
    TransactionInput(
      type: t,
      amount: a,
      walletId: wid,
      categoryId: cid,
      note: note,
      date: d,
      toWalletId: to,
    ),
  );
  await tx(
    TxType.expense,
    25000,
    cash.id,
    cat('Food & Drink'),
    'Nasi padang',
    DateTime(2026, 9, 23, 12, 10),
  );
  await tx(
    TxType.expense,
    18000,
    gopay.id,
    cat('Transport'),
    'Ojol ke kantor',
    DateTime(2026, 9, 23, 8, 5),
  );
  await tx(
    TxType.transfer,
    100000,
    bca.id,
    null,
    null,
    DateTime(2026, 9, 22, 19),
    to: gopay.id,
  );
  await tx(
    TxType.expense,
    187500,
    bca.id,
    cat('Groceries'),
    'Belanja mingguan',
    DateTime(2026, 9, 22, 17, 30),
  );
  await tx(
    TxType.expense,
    450000,
    bca.id,
    cat('Bills & Utilities'),
    'Listrik + internet',
    DateTime(2026, 9, 20, 9),
  );
  await tx(
    TxType.income,
    8500000,
    bca.id,
    cat('Salary'),
    'Gaji September',
    DateTime(2026, 9, 1, 9),
  );
  return {'cash': cash.id, 'bca': bca.id, 'food': cat('Food & Drink')};
});

void main() {
  setUpAll(loadFonts);

  Future<void> shot(
    WidgetTester tester,
    String name,
    String location, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool seed = true,
    Future<void> Function(ProviderContainer c, Map<String, String> ids)? before,
    Future<void> Function()? interact,
  }) async {
    for (final dark in [false, true]) {
      if (textScale != 1 && dark) continue;
      final c = makeContainer();
      final ids = seed ? await seedRich(tester, c) : <String, String>{};
      if (before != null) await before(c, ids);
      const key = ValueKey('shot');
      await pumpApp(
        tester,
        c,
        location,
        dark: dark,
        size: size,
        textScale: textScale,
        boundaryKey: key,
      );
      if (interact != null) await interact();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester, 2);
      expect(tester.takeException(), isNull);
      await saveShot(tester, key, '${name}_${dark ? 'dark' : 'light'}');
      await tearDownApp(tester, c);
    }
  }

  testWidgets(
    'transactions list',
    (t) => shot(t, 'transactions_list', '/transactions'),
  );
  testWidgets(
    'transactions empty',
    (t) => shot(t, 'transactions_empty', '/transactions', seed: false),
  );
  testWidgets(
    'transactions list small + large text',
    (t) => shot(
      t,
      'transactions_list_small',
      '/transactions',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'tx form new',
    (t) => shot(
      t,
      'transactions_form_new',
      '/transactions/new',
      interact: () async {
        for (final k in ['4', '5', '000']) {
          await t.tap(
            find.descendant(
              of: find.byType(AmountKeypad),
              matching: find.text(k),
            ),
          );
          await t.pump();
        }
      },
    ),
  );
  testWidgets(
    'tx form small + large text',
    (t) => shot(
      t,
      'transactions_form_small',
      '/transactions/new',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'tx form transfer',
    (t) => shot(
      t,
      'transactions_form_transfer',
      '/transactions/new',
      interact: () async {
        await t.tap(find.text('Transfer'));
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
  testWidgets('wallets', (t) => shot(t, 'wallets_list', '/wallets'));
  testWidgets(
    'wallets small',
    (t) => shot(
      t,
      'wallets_list_small',
      '/wallets',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'wallet form new',
    (t) => shot(t, 'wallets_form_new', '/wallets/new', seed: false),
  );
  testWidgets('categories', (t) => shot(t, 'categories_list', '/categories'));
  testWidgets(
    'categories small',
    (t) => shot(
      t,
      'categories_list_small',
      '/categories',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'categories empty',
    (t) => shot(t, 'categories_empty', '/categories', seed: false),
  );
  testWidgets(
    'category form new',
    (t) => shot(t, 'categories_form_new', '/categories/new', seed: false),
  );
  testWidgets(
    'tx reward after save',
    (t) => shot(
      t,
      'transactions_reward',
      '/transactions/new',
      interact: () async {
        for (final k in ['1', '5', '000']) {
          await t.tap(
            find.descendant(
              of: find.byType(AmountKeypad),
              matching: find.text(k),
            ),
          );
          await t.pump();
        }
        await t.tap(find.text('SIMPAN'));
        for (var i = 0; i < 8; i++) {
          await settle(t, 2);
        }
        await t.pump(const Duration(milliseconds: 600));
      },
    ),
  );
}
