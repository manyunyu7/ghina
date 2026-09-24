/// Balance adjustment screens: the "Sesuaikan saldo" sheet, the wallet history
/// and the transactions list with adjustment rows, at 390×844 light + dark and
/// 360×640 at 1.3× text. Asserts no layout exceptions; set GHINA_SHOTS_DIR to
/// also write PNGs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../transactions/_feature_harness.dart';
import 'wallets_test.dart' show addWallet;

Future<Wallet> _seed(WidgetTester tester, ProviderContainer c) async {
  final bca = await addWallet(
    tester,
    c,
    const WalletInput(
      name: 'BCA',
      type: WalletType.bank,
      color: '#3b82f6',
      initialBalance: 2450000,
    ),
  );
  final cash = await addWallet(
    tester,
    c,
    const WalletInput(name: 'Tunai', initialBalance: 150000),
  );
  await real(tester, () async {
    await c.read(createTransactionProvider)(
      TransactionInput(
        type: TxType.expense,
        amount: 35000,
        walletId: bca.id,
        note: 'Kopi & roti',
        date: DateTime(2026, 9, 23, 8),
      ),
    );
    await c.read(adjustWalletBalanceProvider)(
      bca.id,
      2400000,
      note: 'biaya admin',
    );
    await c.read(createTransactionProvider)(
      TransactionInput(
        type: TxType.transfer,
        amount: 50000,
        walletId: bca.id,
        toWalletId: cash.id,
        date: DateTime(2026, 9, 22, 18),
      ),
    );
    await c.read(adjustWalletBalanceProvider)(cash.id, 212500);
  });
  return bca;
}

void main() {
  setUpAll(loadFonts);
  const key = ValueKey('shot');

  final variants = <(String, bool, Size, double)>[
    ('light', false, const Size(390, 844), 1),
    ('dark', true, const Size(390, 844), 1),
    ('small', false, const Size(360, 640), 1.3),
  ];

  for (final (name, dark, size, scale) in variants) {
    testWidgets('adjust sheet ($name)', (tester) async {
      final c = makeContainer();
      final bca = await _seed(tester, c);
      await pumpApp(
        tester,
        c,
        '/wallets/${bca.id}',
        dark: dark,
        size: size,
        textScale: scale,
        boundaryKey: key,
      );
      await scrollTo(tester, find.byKey(const ValueKey('wallet-adjust')));
      await tester.ensureVisible(find.byKey(const ValueKey('wallet-adjust')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('wallet-adjust')));
      await settle(tester, 6);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('adjust-amount')),
          matching: find.byType(EditableText),
        ),
        '2387000',
      );
      await settle(tester, 6);
      expect(tester.takeException(), isNull);
      await saveShot(tester, key, 'adjust_sheet_$name');
      await tearDownApp(tester, c);
    });

    testWidgets('wallet edit card ($name)', (tester) async {
      final c = makeContainer();
      final bca = await _seed(tester, c);
      await pumpApp(
        tester,
        c,
        '/wallets/${bca.id}',
        dark: dark,
        size: size,
        textScale: scale,
        boundaryKey: key,
      );
      await scrollTo(tester, find.byKey(const ValueKey('wallet-balance-card')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('wallet-balance-card')),
      );
      await settle(tester, 6);
      expect(tester.takeException(), isNull);
      await saveShot(tester, key, 'adjust_wallet_form_$name');
      await tearDownApp(tester, c);
    });

    testWidgets('wallets + history ($name)', (tester) async {
      final c = makeContainer();
      final bca = await _seed(tester, c);
      await pumpApp(
        tester,
        c,
        '/wallets',
        dark: dark,
        size: size,
        textScale: scale,
        boundaryKey: key,
      );
      await tester.pump(const Duration(seconds: 1));
      await settle(tester, 6);
      expect(tester.takeException(), isNull);
      await saveShot(tester, key, 'adjust_wallets_$name');
      await tester.ensureVisible(
        find.byKey(ValueKey('wallet-history-${bca.id}')),
      );
      await tester.tap(find.byKey(ValueKey('wallet-history-${bca.id}')));
      await settle(tester, 8);
      expect(tester.takeException(), isNull);
      await saveShot(tester, key, 'adjust_history_$name');
      await tearDownApp(tester, c);
    });
  }
}
