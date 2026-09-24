import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/shared/widgets/widgets.dart';

import '_feature_harness.dart';

/// Returns the next queued result per call; records the requested limits.
class FakePhotoPicker implements PhotoPicker {
  final queue = <Object>[];
  final calls = <(PhotoSource, int)>[];
  var _n = 0;

  /// Queues [count] fresh paths.
  void willReturn(int count) =>
      queue.add([for (var i = 0; i < count; i++) '/tmp/pick_${_n++}.jpg']);

  void willThrow(PhotoPickerException e) => queue.add(e);

  @override
  Future<List<String>> pick(PhotoSource source, {required int limit}) async {
    calls.add((source, limit));
    final next = queue.isEmpty ? const <String>[] : queue.removeAt(0);
    if (next is PhotoPickerException) throw next;
    return next as List<String>;
  }
}

Future<({String cash})> seedWallet(WidgetTester tester, ProviderContainer c) =>
    real(tester, () async {
      final cash = (await c.read(createWalletProvider)(
        const WalletInput(name: 'Tunai', initialBalance: 500000),
      )).valueOrThrow;
      return (cash: cash.id);
    });

Future<Transaction> seedTx(
  WidgetTester tester,
  ProviderContainer c,
  String walletId, {
  List<TransactionPhoto> photos = const [],
  String note = 'Belanja bulanan',
}) => real(
  tester,
  () async => (await c.read(createTransactionProvider)(
    TransactionInput(
      type: TxType.expense,
      amount: 150000,
      walletId: walletId,
      note: note,
      date: DateTime(2026, 9, 23, 10),
      photos: photos,
    ),
  )).valueOrThrow,
);

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

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tx-photo-chip')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> closeSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('photo-done')));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> pickFrom(WidgetTester tester, PhotoSource s) async {
  await tester.tap(find.byKey(ValueKey('photo-source-${s.name}')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> saveAndWait(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  for (var i = 0; i < 8; i++) {
    await settle(tester, 2);
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('quick add: attach from gallery + camera, remove, save', (
    tester,
  ) async {
    final picker = FakePhotoPicker()
      ..willReturn(2)
      ..willReturn(1);
    final c = makeContainer(
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    await seedWallet(tester, c);
    await pumpApp(tester, c, '/transactions/new');
    expect(find.text('Foto'), findsOneWidget);
    expect(find.byKey(const ValueKey('tx-photo-strip')), findsNothing);

    await openSheet(tester);
    expect(find.text('0/5'), findsOneWidget);
    await pickFrom(tester, PhotoSource.gallery);
    expect(picker.calls.last, (PhotoSource.gallery, 5));
    expect(find.text('2/5'), findsOneWidget);
    await pickFrom(tester, PhotoSource.camera);
    expect(picker.calls.last, (PhotoSource.camera, 3));
    expect(find.text('3/5'), findsOneWidget);
    // Remove the first one from the sheet.
    await tester.tap(
      find
          .descendant(
            of: find.byType(PhotoAttachSheet),
            matching: find.bySemanticsLabel('Hapus foto'),
          )
          .first,
    );
    await tester.pump();
    expect(find.text('2/5'), findsOneWidget);
    await closeSheet(tester);

    expect(find.text('Foto · 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('tx-photo-strip')), findsOneWidget);
    // Pending photos show the cloud-upload badge.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tx-photo-strip')),
        matching: find.byKey(const ValueKey('photo-pending')),
      ),
      findsNWidgets(2),
    );

    await tapKeys(tester, ['5', '000']);
    await saveAndWait(tester, 'SIMPAN');
    final tx = (await allTx(tester, c)).single;
    expect(tx.photos, const [
      TransactionPhoto.local('/tmp/pick_1.jpg'),
      TransactionPhoto.local('/tmp/pick_2.jpg'),
    ]);
    await tearDownApp(tester, c);
  });

  testWidgets('max 5: picker limited to what is left, then a friendly note', (
    tester,
  ) async {
    final picker = FakePhotoPicker()
      ..willReturn(4)
      ..willReturn(3); // more than asked: trimmed
    final c = makeContainer(
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    await seedWallet(tester, c);
    await pumpApp(tester, c, '/transactions/new');
    await openSheet(tester);
    await pickFrom(tester, PhotoSource.gallery);
    await pickFrom(tester, PhotoSource.gallery);
    expect(picker.calls.last.$2, 1);
    expect(find.text('5/5'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-full')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-source-camera')), findsNothing);
    expect(find.textContaining('Cuma 1 foto yang masuk'), findsOneWidget);
    await closeSheet(tester);
    expect(find.text('Foto · 5'), findsOneWidget);
    // Strip is full: no "+" tile.
    expect(find.byKey(const ValueKey('photo-add')), findsNothing);
    await tearDownApp(tester, c);
  });

  testWidgets('denied permission shows how to enable it', (tester) async {
    final picker = FakePhotoPicker()
      ..willThrow(const PhotoPickerException(PhotoSource.camera, denied: true));
    final c = makeContainer(
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    await seedWallet(tester, c);
    await pumpApp(tester, c, '/transactions/new');
    await openSheet(tester);
    await pickFrom(tester, PhotoSource.camera);
    expect(find.textContaining('Izin kamera ditolak'), findsOneWidget);
    expect(find.text('0/5'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('adjustments can carry photos too (edit applies on save)', (
    tester,
  ) async {
    final picker = FakePhotoPicker()..willReturn(1);
    final c = makeContainer(
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    final w = await seedWallet(tester, c);
    final adj = await real(
      tester,
      () async => (await c.read(adjustWalletBalanceProvider)(
        w.cash,
        450000,
      )).valueOrThrow,
    );
    await pumpApp(tester, c, '/transactions/${adj.id}');
    expect(find.text('Penyesuaian saldo'), findsOneWidget);
    expect(find.byKey(const ValueKey('tx-photo-chip')), findsOneWidget);
    await openSheet(tester);
    await pickFrom(tester, PhotoSource.gallery);
    await closeSheet(tester);
    await saveAndWait(tester, 'SIMPAN PERUBAHAN');
    final saved = (await allTx(tester, c)).firstWhere((t) => t.id == adj.id);
    expect(saved.photos, hasLength(1));
    await tearDownApp(tester, c);
  });

  testWidgets('transfer: photo chip is there and photos are saved', (
    tester,
  ) async {
    final picker = FakePhotoPicker()..willReturn(1);
    final c = makeContainer(
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    final w = await seedWallet(tester, c);
    final bank = await real(
      tester,
      () async => (await c.read(createWalletProvider)(
        const WalletInput(name: 'BCA', type: WalletType.bank),
      )).valueOrThrow,
    );
    await pumpApp(tester, c, '/transactions/new');
    await tester.tap(find.text('Transfer'));
    await tester.pump(const Duration(milliseconds: 300));
    await openSheet(tester);
    await pickFrom(tester, PhotoSource.gallery);
    await closeSheet(tester);
    await tester.tap(find.byKey(const ValueKey('tx-to-wallet')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byKey(ValueKey('wallet-option-${w.cash}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tapKeys(tester, ['5', '000']);
    await saveAndWait(tester, 'SIMPAN');
    final tx = (await allTx(tester, c)).single;
    expect(tx.type, TxType.transfer);
    expect(tx.toWalletId, w.cash);
    expect(tx.walletId, bank.id);
    expect(tx.photos, const [TransactionPhoto.local('/tmp/pick_0.jpg')]);
    await tearDownApp(tester, c);
  });

  testWidgets('edit keeps uploaded photos and removes one', (tester) async {
    final c = makeContainer(
      overrides: [photoPickerProvider.overrideWithValue(FakePhotoPicker())],
    );
    final w = await seedWallet(tester, c);
    final tx = await seedTx(
      tester,
      c,
      w.cash,
      photos: const [
        TransactionPhoto.remote('/uploads/a.jpg'),
        TransactionPhoto.remote('/uploads/b.jpg'),
        TransactionPhoto.local('/tmp/c.jpg'),
      ],
    );
    await pumpApp(tester, c, '/transactions/${tx.id}');
    expect(find.text('Foto · 3'), findsOneWidget);
    final strip = find.byKey(const ValueKey('tx-photo-strip'));
    expect(
      find.descendant(of: strip, matching: find.byType(PhotoThumb)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: strip,
        matching: find.byKey(const ValueKey('photo-pending')),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find
          .descendant(of: strip, matching: find.bySemanticsLabel('Hapus foto'))
          .at(1),
    );
    await tester.pump();
    expect(find.text('Foto · 2'), findsOneWidget);
    await saveAndWait(tester, 'SIMPAN PERUBAHAN');
    final saved = (await allTx(tester, c)).single;
    expect(saved.photos, const [
      TransactionPhoto.remote('/uploads/a.jpg'),
      TransactionPhoto.local('/tmp/c.jpg'),
    ]);
    await tearDownApp(tester, c);
  });

  testWidgets('list row shows a photo badge that opens the viewer', (
    tester,
  ) async {
    final c = makeContainer();
    final w = await seedWallet(tester, c);
    final tx = await seedTx(
      tester,
      c,
      w.cash,
      photos: const [
        TransactionPhoto.remote('/uploads/a.jpg'),
        TransactionPhoto.remote('/uploads/b.jpg'),
      ],
    );
    await seedTx(tester, c, w.cash, note: 'Tanpa foto');
    await pumpApp(tester, c, '/transactions');
    final badge = find.byKey(ValueKey('tx-photos-${tx.id}'));
    expect(badge, findsOneWidget);
    expect(find.byType(PhotoCountBadge), findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('2')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1)); // row pop-in
    await tester.tap(badge);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo-viewer-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhotoViewer), findsNothing);
    // Still on the list.
    expect(find.text('Belanja bulanan'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('adjust-balance sheet attaches proof photos', (tester) async {
    final picker = FakePhotoPicker()..willReturn(2);
    final c = makeContainer(
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    final w = await seedWallet(tester, c);
    await pumpApp(tester, c, '/wallets/${w.cash}');
    await tester.ensureVisible(find.byKey(const ValueKey('wallet-adjust')));
    await tester.tap(find.byKey(const ValueKey('wallet-adjust')));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('adjust-amount')),
        matching: find.byType(EditableText),
      ),
      '480000',
    );
    await settle(tester);
    final add = find.descendant(
      of: find.byKey(const ValueKey('adjust-photos')),
      matching: find.byKey(const ValueKey('photo-add')),
    );
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await pickFrom(tester, PhotoSource.gallery);
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adjust-photos')),
        matching: find.byType(PhotoThumb),
      ),
      findsNWidgets(2),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('adjust-save')));
    await tester.tap(find.byKey(const ValueKey('adjust-save')));
    await settle(tester, 6);
    final tx = (await allTx(tester, c)).single;
    expect(tx.type, TxType.adjustment);
    expect(tx.photos, const [
      TransactionPhoto.local('/tmp/pick_0.jpg'),
      TransactionPhoto.local('/tmp/pick_1.jpg'),
    ]);
    await tearDownApp(tester, c);
  });
}
