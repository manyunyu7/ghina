import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../transactions/_feature_harness.dart';

Future<List<Wallet>> allWallets(WidgetTester tester, ProviderContainer c) =>
    real(
      tester,
      () => c.read(watchWalletsUseCaseProvider)(includeArchived: true).first,
    );

Future<Wallet> addWallet(
  WidgetTester tester,
  ProviderContainer c,
  WalletInput input,
) => real(tester, () async {
  (c.read(clockProvider) as FixedClock).advance(const Duration(seconds: 1));
  return (await c.read(createWalletProvider)(input)).valueOrThrow;
});

void main() {
  setUpAll(loadFonts);

  testWidgets('empty state invites to add a wallet', (tester) async {
    final c = makeContainer();
    await pumpApp(tester, c, '/wallets');
    expect(find.text('Belum ada dompet'), findsOneWidget);
    expect(find.text('TAMBAH DOMPET'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('shows total, wallet cards, pending hint and archived section', (
    tester,
  ) async {
    final c = makeContainer();
    final cash = await addWallet(
      tester,
      c,
      const WalletInput(name: 'Tunai', initialBalance: 150000),
    );
    await addWallet(
      tester,
      c,
      const WalletInput(
        name: 'BCA',
        type: WalletType.bank,
        color: '#3b82f6',
        initialBalance: 1000000,
      ),
    );
    await addWallet(
      tester,
      c,
      const WalletInput(name: 'Lama', initialBalance: 999, archived: true),
    );
    // A pending (unsynced) expense changes balance vs syncedBalance.
    await real(
      tester,
      () => c.read(createTransactionProvider)(
        TransactionInput(
          type: TxType.expense,
          amount: 50000,
          walletId: cash.id,
          date: testNow,
        ),
      ),
    );
    await pumpApp(tester, c, '/wallets');
    await tester.pump(const Duration(seconds: 1)); // count-up
    expect(
      find.text('Rp 1.100.000'),
      findsOneWidget,
    ); // total excludes archived
    expect(find.text('Tunai'), findsOneWidget);
    expect(find.text('BCA'), findsOneWidget);
    expect(find.byKey(ValueKey('pending-${cash.id}')), findsOneWidget);
    expect(find.text('Diarsipkan (1)'), findsOneWidget);
    expect(find.text('Lama'), findsNothing);
    await tester.tap(find.text('LIHAT'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Lama'), findsOneWidget);
    expect(find.text('TRANSFER'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('create: validates the name then saves', (tester) async {
    final c = makeContainer();
    await pumpApp(tester, c, '/wallets/new');
    expect(find.text('Dompet baru'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('wallet-save')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kasih nama dulu, ya'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('wallet-name')),
        matching: find.byType(TextField),
      ),
      'GoPay',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('wallet-balance')),
        matching: find.byType(TextField),
      ),
      '250.000',
    );
    await tester.tap(find.text('E-Wallet'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wallet-save')));
    await settle(tester);
    final ws = await allWallets(tester, c);
    expect(ws, hasLength(1));
    expect(ws.single.name, 'GoPay');
    expect(ws.single.type, WalletType.ewallet);
    expect(ws.single.balance, 250000);
    await tearDownApp(tester, c);
  });

  testWidgets('edit: archive toggle and delete with warning', (tester) async {
    final c = makeContainer();
    final w = await addWallet(
      tester,
      c,
      const WalletInput(name: 'Jago', initialBalance: 10000),
    );
    await pumpApp(tester, c, '/wallets/${w.id}');
    expect(find.text('Edit dompet'), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-balance')), findsNothing);
    await scrollTo(tester, find.byKey(const ValueKey('wallet-archive')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wallet-archive')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wallet-save')));
    await settle(tester);
    expect((await allWallets(tester, c)).single.archived, isTrue);

    await pumpApp(tester, c, '/wallets/${w.id}');
    await scrollTo(tester, find.byKey(const ValueKey('wallet-delete')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wallet-delete')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('ikut terhapus permanen'), findsOneWidget);
    await tester.tap(find.text('HAPUS PERMANEN'));
    await settle(tester);
    expect(await allWallets(tester, c), isEmpty);
    await tearDownApp(tester, c);
  });
}
