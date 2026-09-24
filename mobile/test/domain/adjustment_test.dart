// Balance adjustments (docs/balance-adjustment.md): ledger effect, the
// "Sesuaikan saldo" use case, and every place they must NOT count.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/di/game_overrides.dart' show activityEventsFrom;
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 9, 24, 10);
  final clock = FixedClock(now);
  late FakeWalletRepository wallets;
  late FakeCategoryRepository categories;
  late FakeTransactionRepository txs;

  setUp(() {
    wallets = FakeWalletRepository()..s.put(wallet('w1', balance: 100000));
    categories = FakeCategoryRepository()
      ..s.put(category('food'))
      ..s.put(category('salary', type: CategoryType.income));
    txs = FakeTransactionRepository();
  });

  group('ledger', () {
    test('adjustment adds its signed amount to the wallet', () {
      expect(txn('a', TxType.adjustment, 500, t0).balanceEffects, {'w1': 500});
      expect(txn('a', TxType.adjustment, -250, t0).balanceEffects, {
        'w1': -250,
      });
    });

    test('edit reverses old + applies new; delete restores', () {
      expect(
        effectDelta(
          txn('a', TxType.adjustment, 500, t0),
          txn('a', TxType.adjustment, -100, t0),
        ),
        {'w1': -600},
      );
      expect(effectDelta(txn('a', TxType.adjustment, -250, t0), null), {
        'w1': 250,
      });
    });

    test(
      'unknown wire types parse to null (skipped), known ones round-trip',
      () {
        expect(TxType.tryFromWire('gift'), isNull);
        expect(TxType.tryFromWire(null), isNull);
        for (final t in TxType.values) {
          expect(TxType.tryFromWire(t.wire), t);
        }
        expect(TxType.loggable, isNot(contains(TxType.adjustment)));
      },
    );
  });

  group('AdjustWalletBalance', () {
    test(
      'records the signed difference against the displayed balance',
      () async {
        // Displayed balance includes pending local changes.
        wallets.s.put(
          Wallet(
            id: 'w1',
            name: 'BCA',
            type: WalletType.bank,
            balance: 120000,
            syncedBalance: 100000,
            currency: 'IDR',
            color: '#6366f1',
            icon: 'bank',
            archived: false,
            createdAt: t0,
            updatedAt: t0,
          ),
        );
        final r = await AdjustWalletBalance(wallets, txs, clock)('w1', 95500);
        final t = r.valueOrNull!;
        expect(t.type, TxType.adjustment);
        expect(t.amount, -24500);
        expect(t.walletId, 'w1');
        expect(t.categoryId, isNull);
        expect(t.toWalletId, isNull);
        expect(t.date, now);
        expect(t.note, 'Penyesuaian saldo: Rp 120.000 → Rp 95.500');
        expect(txs.s.items, hasLength(1));
      },
    );

    test('user note is appended; wallet currency formats the note', () async {
      wallets.s.put(
        Wallet(
          id: 'usd',
          name: 'Wise',
          type: WalletType.bank,
          balance: 10.5,
          syncedBalance: 10.5,
          currency: 'USD',
          color: '#6366f1',
          icon: 'bank',
          archived: false,
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      final r = await AdjustWalletBalance(wallets, txs, clock)(
        'usd',
        12,
        note: ' biaya admin ',
        date: DateTime(2026, 9, 20),
      );
      final t = r.valueOrNull!;
      expect(t.amount, 1.5);
      expect(t.note, r'Penyesuaian saldo: $10.50 → $12.00 — biaya admin');
      expect(t.date, DateTime(2026, 9, 20));
    });

    test(
      'no difference (after 2-decimal rounding) → nothing recorded',
      () async {
        wallets.s.put(wallet('w1', balance: 0.1 + 0.2));
        final r = await AdjustWalletBalance(wallets, txs, clock)('w1', 0.3);
        expect(r.failureOrNull, isA<ValidationFailure>());
        expect(txs.s.items, isEmpty);
        expect(adjustmentDelta(0.1 + 0.2, 0.3), 0);
        expect(adjustmentDelta(10, 12.345), 2.35);
      },
    );

    test('unknown wallet / non-finite target', () async {
      final adjust = AdjustWalletBalance(wallets, txs, clock);
      expect((await adjust('nope', 5)).failureOrNull, isA<NotFoundFailure>());
      expect(
        (await adjust('w1', double.nan)).failureOrNull,
        isA<ValidationFailure>(),
      );
    });

    test('negative balances are fine (credit cards)', () async {
      final r = await AdjustWalletBalance(wallets, txs, clock)('w1', -50000);
      expect(r.valueOrNull!.amount, -150000);
    });
  });

  group('editing an adjustment like any transaction', () {
    test('signed non-zero amount, category/toWallet dropped', () async {
      final create = CreateTransaction(txs, wallets, categories, clock);
      final r = await create(
        TransactionInput(
          type: TxType.adjustment,
          amount: -1500,
          walletId: 'w1',
          toWalletId: 'w1',
          categoryId: 'food',
          date: now,
        ),
      );
      final t = r.valueOrNull!;
      expect(t.amount, -1500);
      expect(t.categoryId, isNull);
      expect(t.toWalletId, isNull);

      final update = UpdateTransaction(txs, wallets, categories, clock);
      final u = await update(
        t.id,
        TransactionInput(
          type: TxType.adjustment,
          amount: 2500,
          walletId: 'w1',
          date: now,
        ),
      );
      expect(u.valueOrNull!.amount, 2500);
      expect(
        (await update(
          t.id,
          TransactionInput(
            type: TxType.adjustment,
            amount: 0,
            walletId: 'w1',
            date: now,
          ),
        )).failureOrNull,
        isA<ValidationFailure>(),
      );
      // Other types still need a positive amount.
      expect(
        (await create(
          TransactionInput(
            type: TxType.expense,
            amount: -5,
            walletId: 'w1',
            date: now,
          ),
        )).failureOrNull,
        isA<ValidationFailure>(),
      );
    });

    test('view title/label', () {
      final v = TransactionView(
        transaction: txn(
          'a',
          TxType.adjustment,
          -5000,
          now,
        ).copyNote('Penyesuaian saldo: Rp 10.000 → Rp 5.000'),
      );
      expect(v.title, 'Penyesuaian saldo');
    });
  });

  group('excluded from income/expense aggregates', () {
    final month = YearMonth(2026, 9);
    final list = [
      txn('e', TxType.expense, 30000, now, categoryId: 'food'),
      txn('i', TxType.income, 100000, now, categoryId: 'salary'),
      txn('a1', TxType.adjustment, 50000, now),
      txn('a2', TxType.adjustment, -20000, now),
    ];

    test('month totals, day groups, category totals', () {
      final totals = monthlyTotals(list, [month]).single;
      expect(totals.income, 100000);
      expect(totals.expense, 30000);
      final groups = groupTransactionsByDay([
        for (final t in list) TransactionView(transaction: t),
      ]);
      expect(groups.single.income, 100000);
      expect(groups.single.expense, 30000);
      expect(groups.single.items, hasLength(4), reason: 'still listed');
      final cats = [
        category('food'),
        category('salary', type: CategoryType.income),
      ];
      expect(categoryTotals(list, cats, TxType.expense).map((c) => c.total), [
        30000,
      ]);
    });

    test('dashboard month stats and today', () {
      final d = buildDashboard(
        now: now,
        wallets: [wallet('w1', balance: 130000)],
        categories: [category('food')],
        transactions: list,
        monthBudgets: const [],
        recent: const [],
      );
      expect(d.monthIncome, 100000);
      expect(d.monthExpense, 30000);
      expect(d.todayIncome, 100000);
      expect(d.todayExpense, 30000);
      expect(d.totalBalance, 130000, reason: 'balances include adjustments');
    });

    test('reports (income vs expense, savings rate, by category)', () {
      final r = buildReport(
        period: ReportPeriod.thisMonth,
        now: now,
        transactions: list,
        categories: [
          category('food'),
          category('salary', type: CategoryType.income),
        ],
        wallets: [wallet('w1', balance: 130000)],
      );
      expect(r.totalIncome, 100000);
      expect(r.totalExpense, 30000);
      expect(r.savingsRate, 70);
      expect(r.netWorth, 130000);
    });

    test('budgets spent', () {
      final b = Budget(
        id: 'b',
        categoryId: 'food',
        amount: 50000,
        month: 9,
        year: 2026,
        createdAt: t0,
        updatedAt: t0,
      );
      final bm = computeBudgetMonth(month, [b], list, [category('food')]);
      expect(bm.items.single.spent, 30000);
      expect(
        computeBudgetUsage([b], list, [category('food')]).single.spent,
        30000,
      );
    });

    test('forecast history averages', () {
      final hist = [
        txn(
          'e',
          TxType.expense,
          30000,
          DateTime(2026, 8, 5),
          categoryId: 'food',
        ),
        txn('a', TxType.adjustment, -90000, DateTime(2026, 8, 6)),
      ];
      final avg = categoryMonthlyAverages(hist, [category('food')], now);
      expect(avg.single.avg, 10000);
    });

    test('gamification: adjustments are not activity events', () {
      final events = activityEventsFrom(list, const [], const [], const []);
      expect(events, hasLength(2));
      expect(events.map((e) => e.id), ['e', 'i']);
    });
  });
}

extension on Transaction {
  Transaction copyNote(String note) => Transaction(
    id: id,
    walletId: walletId,
    toWalletId: toWalletId,
    categoryId: categoryId,
    type: type,
    amount: amount,
    note: note,
    date: date,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
