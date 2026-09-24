// Visual review of transaction photos (form chip + strip, attach sheet, list
// badge, viewer).
//   GHINA_SHOTS_DIR=/some/dir flutter test test/presentation/features/transactions/transaction_photos_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/shared/widgets/widgets.dart';

import '_feature_harness.dart';

/// Writes a small fake "receipt" PNG and returns its path.
Future<String> _receipt(String name, Color color) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  const w = 600.0, h = 800.0;
  canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = color);
  final paper = Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(90, 60, 420, 680),
      const Radius.circular(12),
    ),
    paper,
  );
  final ink = Paint()..color = const Color(0xFF9CA3AF);
  for (var i = 0; i < 12; i++) {
    final y = 120.0 + i * 46;
    canvas.drawRect(Rect.fromLTWH(130, y, i.isEven ? 220 : 160, 14), ink);
    canvas.drawRect(Rect.fromLTWH(400, y, 70, 14), ink);
  }
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('${Directory.systemTemp.path}/ghina_photo_shots')
    ..createSync(recursive: true);
  final f = File('${dir.path}/$name.png')
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  return f.path;
}

void main() {
  setUpAll(loadFonts);

  Future<void> run(
    WidgetTester tester,
    String name,
    Future<String> Function(WidgetTester, ProviderContainer) location, {
    Future<void> Function(WidgetTester)? act,
    Size size = const Size(390, 844),
    double textScale = 1,
    List<bool> modes = const [false, true],
  }) async {
    for (final dark in modes) {
      final c = makeContainer();
      final loc = await location(tester, c);
      const key = ValueKey('shot');
      await pumpApp(
        tester,
        c,
        loc,
        dark: dark,
        size: size,
        textScale: textScale,
        boundaryKey: key,
      );
      if (act != null) await act(tester);
      // Let file images load and decode.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      await saveShot(
        tester,
        key,
        'w2/transactions_photos_${name}_${dark ? 'dark' : 'light'}'
        '${textScale != 1 ? '_small' : ''}',
      );
      await tearDownApp(tester, c);
    }
  }

  Future<String> seedEdit(WidgetTester tester, ProviderContainer c) =>
      real(tester, () async {
        final w = (await c.read(createWalletProvider)(
          const WalletInput(name: 'BCA', initialBalance: 4250000),
        )).valueOrThrow;
        final p1 = await _receipt('r1', const Color(0xFFFFC800));
        final p2 = await _receipt('r2', const Color(0xFF1CB0F6));
        final t = (await c.read(createTransactionProvider)(
          TransactionInput(
            type: TxType.expense,
            amount: 327500,
            walletId: w.id,
            note: 'Belanja bulanan Superindo',
            date: DateTime(2026, 9, 23, 10),
            photos: [
              TransactionPhoto.local(p1),
              TransactionPhoto.local(p2),
              const TransactionPhoto.remote('/uploads/missing.jpg'),
            ],
          ),
        )).valueOrThrow;
        await c.read(createTransactionProvider)(
          TransactionInput(
            type: TxType.transfer,
            amount: 500000,
            walletId: w.id,
            toWalletId: (await c.read(createWalletProvider)(
              const WalletInput(name: 'GoPay'),
            )).valueOrThrow.id,
            note: 'Top up',
            date: DateTime(2026, 9, 23, 9),
            photos: [TransactionPhoto.local(p2)],
          ),
        );
        await c.read(createTransactionProvider)(
          TransactionInput(
            type: TxType.expense,
            amount: 25000,
            walletId: w.id,
            note: 'Kopi susu',
            date: DateTime(2026, 9, 23, 8),
          ),
        );
        return '/transactions/${t.id}';
      });

  testWidgets('edit form with photos', (t) => run(t, 'edit', seedEdit));
  testWidgets(
    'edit form small',
    (t) => run(
      t,
      'edit',
      seedEdit,
      size: const Size(360, 640),
      textScale: 1.3,
      modes: const [false],
    ),
  );
  testWidgets(
    'attach sheet',
    (t) => run(
      t,
      'sheet',
      seedEdit,
      act: (tester) async {
        await tester.tap(find.byKey(const ValueKey('tx-photo-chip')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
      },
    ),
  );
  testWidgets(
    'list badge',
    (t) => run(t, 'list', (tester, c) async {
      await seedEdit(tester, c);
      return '/transactions';
    }),
  );
  testWidgets(
    'viewer',
    (t) => run(
      t,
      'viewer',
      seedEdit,
      modes: const [false],
      act: (tester) async {
        await tester.tap(find.byKey(const ValueKey('photo-thumb-0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    ),
  );
  testWidgets(
    'viewer broken',
    (t) => run(
      t,
      'viewer_broken',
      seedEdit,
      modes: const [true],
      act: (tester) async {
        await tester.tap(find.byKey(const ValueKey('photo-thumb-2')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(PhotoViewer), findsOneWidget);
      },
    ),
  );
}
