import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/home/pages/home_page.dart';

import '../shell/test_utils.dart';
import '_task_harness.dart';

Finder _check(String id) => find.byKey(ValueKey('home-task-check-$id'));

Future<void> _pump(WidgetTester tester, HomeTaskFixture fx) => pumpPage(
  tester,
  const HomePage(),
  overrides: withTasks(pageOverrides(), fx),
);

void main() {
  group('Tugas FIRE card', () {
    testWidgets('lists up to 5 FIRE tasks of the focus areas', (tester) async {
      final fx = HomeTaskFixture()..life();
      for (var i = 0; i < 7; i++) {
        fx.task('f$i', 'Tugas penting $i', sortOrder: i);
      }
      fx.task('w1', 'Cuma pengen', bucket: TaskBucket.want);
      await _pump(tester, fx);
      await scrollTo(tester, find.text('Tugas FIRE'));
      expect(find.text('Area fokus: Keseharian'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.text('Tugas penting $i'), findsOneWidget);
      }
      expect(find.text('Tugas penting 5'), findsNothing);
      expect(find.text('Cuma pengen'), findsNothing);
      await scrollTo(tester, find.text('+2 tugas FIRE lainnya'));
      await scrollTo(tester, find.text('Tugas FIRE'));
      await tester.tap(find.text('LIHAT SEMUA').first);
      await settle(tester);
      expect(find.text('ROUTE:/tasks'), findsOneWidget);
    });

    testWidgets('empty state: FIRE kosong with the mascot', (tester) async {
      final fx = HomeTaskFixture()..life();
      fx.task('s1', 'Nanti aja', bucket: TaskBucket.should);
      await _pump(tester, fx);
      await scrollTo(tester, find.text('FIRE kosong 🔥 mantap!'));
      expect(find.textContaining('Yang mendesak udah beres'), findsOneWidget);
      await tester.tap(find.text('LIHAT TUGAS'));
      await settle(tester);
      expect(find.text('ROUTE:/tasks'), findsOneWidget);
    });

    testWidgets('empty state without any task invites adding one', (
      tester,
    ) async {
      await _pump(tester, HomeTaskFixture()..life());
      await scrollTo(tester, find.text('FIRE kosong 🔥 mantap!'));
      expect(find.text('TAMBAH TUGAS'), findsOneWidget);
    });

    testWidgets('one tap completes a task without a money link', (
      tester,
    ) async {
      final fx = HomeTaskFixture()..life();
      fx.task('f1', 'Bayar listrik');
      await _pump(tester, fx);
      await scrollTo(tester, _check('f1'));
      await tester.tap(_check('f1'));
      await settle(tester, 25);
      final t = fx.tasks.s.items['f1']!;
      expect(t.done, isTrue);
      expect(t.transactionId, isNull);
      expect(find.textContaining('Beres!'), findsOneWidget);
      expect(find.text('Bayar listrik'), findsNothing);
      expect(find.text('FIRE kosong 🔥 mantap!'), findsOneWidget);
      await settle(tester, 40);
    });

    testWidgets('money link: "Ya, catat" records the expense and completes', (
      tester,
    ) async {
      final fx = HomeTaskFixture()..life();
      fx.wallet('w1', 'Tunai', 500000);
      fx.task('f1', 'Bayar iuran RT', amount: 50000, walletId: 'w1');
      await _pump(tester, fx);
      await scrollTo(tester, _check('f1'));
      await tester.tap(_check('f1'));
      await settle(tester);
      expect(find.text('Catat pengeluaran Rp 50.000?'), findsOneWidget);
      await tester.tap(find.text('YA, CATAT'));
      await settle(tester, 25);
      final t = fx.tasks.s.items['f1']!;
      expect(t.done, isTrue);
      expect(t.transactionId, isNotNull);
      final tx = fx.transactions.s.items[t.transactionId]!;
      expect(tx.amount, 50000);
      expect(tx.type, TxType.expense);
      expect(tx.walletId, 'w1');
      expect(tx.note, 'Bayar iuran RT');
      expect(find.textContaining('Rp 50.000 tercatat'), findsOneWidget);
      await settle(tester, 40);
    });

    testWidgets('money link: "Selesai saja" completes without an expense', (
      tester,
    ) async {
      final fx = HomeTaskFixture()..life();
      fx.wallet('w1', 'Tunai', 500000);
      fx.task('f1', 'Bayar iuran RT', amount: 50000, walletId: 'w1');
      await _pump(tester, fx);
      await scrollTo(tester, _check('f1'));
      await tester.tap(_check('f1'));
      await settle(tester);
      await tester.tap(find.text('SELESAI SAJA'));
      await settle(tester, 25);
      final t = fx.tasks.s.items['f1']!;
      expect(t.done, isTrue);
      expect(t.transactionId, isNull);
      expect(fx.transactions.s.items, isEmpty);
      await settle(tester, 40);
    });

    testWidgets('money link without wallet asks for one; dismiss cancels', (
      tester,
    ) async {
      final fx = HomeTaskFixture()..life();
      fx.wallet('w1', 'Tunai', 500000);
      fx.wallet('w2', 'BCA', 2000000);
      fx.task('f1', 'Servis motor', amount: 150000);
      fx.task('f2', 'Beli token', amount: 100000);
      await _pump(tester, fx);

      // Dismissing the prompt leaves the task open.
      await scrollTo(tester, _check('f2'));
      await tester.tap(_check('f2'));
      await settle(tester);
      expect(find.text('Catat pengeluaran Rp 100.000?'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(fx.tasks.s.items['f2']!.done, isFalse);

      await scrollTo(tester, _check('f1'));
      await tester.tap(_check('f1'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('expense-wallet')));
      await settle(tester);
      expect(find.text('Dibayar pakai'), findsWidgets);
      await tester.tap(find.text('BCA').last);
      await settle(tester);
      await tester.tap(find.text('YA, CATAT'));
      await settle(tester, 25);
      final t = fx.tasks.s.items['f1']!;
      expect(t.done, isTrue);
      expect(fx.transactions.s.items[t.transactionId]!.walletId, 'w2');
      await settle(tester, 40);
    });

    testWidgets('overdue count and a worried mascot when tasks pile up', (
      tester,
    ) async {
      final fx = HomeTaskFixture()..life();
      for (var i = 0; i < 3; i++) {
        fx.task('o$i', 'Telat $i', dueDate: '2026-09-2$i');
      }
      await _pump(tester, fx);
      expect(find.textContaining('terlambat'), findsWidgets);
      expect(
        find.textContaining(RegExp(r'3 tugas (yang )?terlambat|3 udah lewat')),
        findsWidgets,
      );
      await scrollTo(tester, find.text('3 terlambat'));
      expect(find.text('Terlambat'), findsNWidgets(3));
    });
  });

  testWidgets('Sunday morning shows "Sapu bersih SHOULD"', (tester) async {
    final fx = HomeTaskFixture(now: DateTime(2026, 9, 27, 9))..life();
    fx.task('s1', 'Rapikan lemari', bucket: TaskBucket.should);
    fx.task('s2', 'Cuci sepatu', bucket: TaskBucket.should);
    await _pump(tester, fx);
    await scrollTo(tester, find.text('Sapu bersih SHOULD 🧹'));
    expect(find.text('Rapikan lemari'), findsOneWidget);
    await scrollTo(tester, _check('s2'));
    await tester.tap(_check('s2'));
    await settle(tester, 25);
    expect(fx.tasks.s.items['s2']!.done, isTrue);
    await settle(tester, 40);
  });

  testWidgets('no "Sapu bersih" on a weekday', (tester) async {
    final fx = HomeTaskFixture()..life();
    fx.task('s1', 'Rapikan lemari', bucket: TaskBucket.should);
    await _pump(tester, fx);
    await scrollTo(tester, find.text('FIRE kosong 🔥 mantap!'));
    expect(find.text('Sapu bersih SHOULD 🧹'), findsNothing);
  });

  testWidgets('learning stays reachable: Belajar quick action', (tester) async {
    await _pump(tester, HomeTaskFixture()..life());
    await scrollTo(tester, find.byKey(const ValueKey('qa-/learn')));
    await tester.tap(find.byKey(const ValueKey('qa-/learn')));
    await settle(tester);
    expect(find.text('ROUTE:/learn'), findsOneWidget);
  });
}
