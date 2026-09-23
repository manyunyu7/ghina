import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';

void main() {
  late FakeWalletRepository wallets;
  late FakeCategoryRepository categories;
  late FakeTransactionRepository txs;
  late FakeSubscriptionRepository subs;
  late FakePlannedRepository planned;
  late FakeBudgetRepository budgets;
  late FakeUnitOfWork uow;
  final clock = FixedClock(DateTime(2026, 9, 23, 10));

  setUp(() {
    wallets = FakeWalletRepository()
      ..s.put(wallet('w1', createdAt: DateTime(2026, 1, 1)))
      ..s.put(wallet('w2', createdAt: DateTime(2026, 2, 1)));
    categories = FakeCategoryRepository()
      ..s.put(category('food'))
      ..s.put(category('salary', type: CategoryType.income));
    txs = FakeTransactionRepository();
    subs = FakeSubscriptionRepository();
    planned = FakePlannedRepository();
    budgets = FakeBudgetRepository();
    uow = FakeUnitOfWork();
  });

  Failure? failureOf(Result<Object?> r) => r.failureOrNull;

  group('ledger', () {
    test('effects per type', () {
      expect(txn('a', TxType.income, 10, t0).balanceEffects, {'w1': 10});
      expect(txn('a', TxType.expense, 10, t0).balanceEffects, {'w1': -10});
      expect(
        txn('a', TxType.transfer, 10, t0, toWalletId: 'w2').balanceEffects,
        {'w1': -10, 'w2': 10},
      );
      expect(
        effectDelta(
          txn('a', TxType.transfer, 10, t0, toWalletId: 'w2'),
          txn('a', TxType.expense, 4, t0, walletId: 'w2'),
        ),
        {'w1': 10, 'w2': -14},
      );
    });
  });

  group('transactions', () {
    late CreateTransaction create;
    setUp(() => create = CreateTransaction(txs, wallets, categories, clock));

    test('transfer validation', () async {
      final transfer = TransferBetweenWallets(create);
      expect(
        failureOf(
          await transfer(
            fromWalletId: 'w1',
            toWalletId: 'w1',
            amount: 5,
            date: t0,
          ),
        ),
        isA<ValidationFailure>(),
      );
      expect(
        failureOf(
          await transfer(
            fromWalletId: 'w1',
            toWalletId: 'nope',
            amount: 5,
            date: t0,
          ),
        ),
        isA<NotFoundFailure>(),
      );
      expect(
        failureOf(
          await transfer(
            fromWalletId: 'w1',
            toWalletId: 'w2',
            amount: 0,
            date: t0,
          ),
        ),
        isA<ValidationFailure>(),
      );
      final ok = await create(
        TransactionInput(
          type: TxType.transfer,
          amount: 5,
          walletId: 'w1',
          toWalletId: 'w2',
          categoryId: 'food',
          note: '  ',
          date: t0,
        ),
      );
      final t = ok.valueOrThrow;
      expect(t.categoryId, isNull); // transfers carry no category
      expect(t.note, isNull);
    });

    test('non-transfers drop toWalletId and check the category', () async {
      final t = (await create(
        TransactionInput(
          type: TxType.expense,
          amount: 5,
          walletId: 'w1',
          toWalletId: 'w2',
          categoryId: 'food',
          date: t0,
        ),
      )).valueOrThrow;
      expect(t.toWalletId, isNull);
      expect(
        failureOf(
          await create(
            TransactionInput(
              type: TxType.expense,
              amount: 5,
              walletId: 'w1',
              categoryId: 'x',
              date: t0,
            ),
          ),
        ),
        isA<NotFoundFailure>(),
      );
    });

    test('search and group by day', () async {
      txs.s.put(
        txn(
          'a',
          TxType.expense,
          10,
          DateTime(2026, 9, 22, 8),
          categoryId: 'food',
        ),
      );
      txs.s.put(
        txn(
          'b',
          TxType.income,
          50,
          DateTime(2026, 9, 22, 9),
          categoryId: 'salary',
        ),
      );
      txs.s.put(txn('c', TxType.expense, 7, DateTime(2026, 9, 23, 9)));
      final watch = WatchTransactions(txs, wallets, categories);
      final found = await watch(const TransactionFilter(search: 'FOO')).first;
      expect(found.map((v) => v.id), ['a']);
      final days = groupTransactionsByDay(await watch().first);
      expect(days.map((d) => d.day), [
        DateTime(2026, 9, 23),
        DateTime(2026, 9, 22),
      ]);
      expect(days.last.income, 50);
      expect(days.last.expense, 10);
    });
  });

  group('subscriptions', () {
    test(
      'quick pay: expense today + next billing one cycle after the paid occurrence',
      () async {
        subs.s.put(
          subscription(
            'netflix',
            DateTime(2026, 7, 15),
            amount: 54000,
            categoryId: 'food',
          ),
        );
        final pay = PaySubscription(subs, txs, wallets, uow, clock);
        final t = (await pay('netflix')).valueOrThrow;
        expect(t.type, TxType.expense);
        expect(t.amount, 54000);
        expect(t.walletId, 'w1'); // first wallet fallback
        expect(t.categoryId, 'food');
        expect(t.note, 'netflix');
        expect(t.date, clock.now());
        // Paid occurrence = 2026-10-15 (first on/after today) → next = 2026-11-15.
        expect(
          (await subs.getById('netflix'))!.nextBilling,
          DateTime(2026, 11, 15),
        );
        expect(uow.runs, 1);
      },
    );

    test('quick pay without wallets fails', () async {
      wallets = FakeWalletRepository();
      subs.s.put(subscription('x', DateTime(2026, 10, 1)));
      final r = await PaySubscription(subs, txs, wallets, uow, clock)('x');
      expect(r.failureOrNull, isA<ValidationFailure>());
      expect(txs.s.items, isEmpty);
    });

    test('summary totals only active subscriptions', () async {
      subs.s.put(
        subscription(
          'a',
          DateTime(2026, 10, 1),
          amount: 120000,
          cycle: BillingCycle.yearly,
        ),
      );
      subs.s.put(subscription('b', DateTime(2026, 9, 1), amount: 50000));
      subs.s.put(
        subscription('c', DateTime(2026, 9, 1), amount: 99, active: false),
      );
      final s = await WatchSubscriptions(subs, clock)().first;
      expect(s.items.last.id, 'c');
      expect(s.monthlyTotal, 60000);
      expect(s.yearlyTotal, 720000);
    });
  });

  group('planned', () {
    test('convert creates the transaction and removes the plan', () async {
      planned.s.put(
        PlannedTransaction(
          id: 'p',
          type: TxType.income,
          amount: 100,
          walletId: 'w2',
          date: DateTime(2026, 10, 1),
          done: false,
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      final t = (await ConvertPlanned(planned, txs, wallets, uow, clock)(
        'p',
      )).valueOrThrow;
      expect(t.walletId, 'w2');
      expect(t.type, TxType.income);
      expect(t.date, DateTime(2026, 10, 1));
      expect(await planned.getById('p'), isNull);
    });

    test('toggle done', () async {
      planned.s.put(
        PlannedTransaction(
          id: 'p',
          type: TxType.expense,
          amount: 1,
          date: t0,
          done: false,
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      expect(
        (await TogglePlannedDone(planned, clock)('p')).valueOrThrow,
        isTrue,
      );
      expect((await planned.getById('p'))!.done, isTrue);
    });
  });

  group('budgets', () {
    test(
      'set budget upserts on the key and rejects income categories',
      () async {
        final set = SetBudget(budgets, categories, clock);
        final m = const YearMonth(2026, 9);
        final a = (await set(
          categoryId: 'food',
          amount: 100,
          month: m,
        )).valueOrThrow;
        final b = (await set(
          categoryId: 'food',
          amount: 200,
          month: m,
        )).valueOrThrow;
        expect(b.id, a.id);
        expect(budgets.s.items, hasLength(1));
        expect(
          (await set(categoryId: 'salary', amount: 1, month: m)).failureOrNull,
          isA<ValidationFailure>(),
        );
      },
    );

    test('spent / remaining / sorting', () {
      final m = const YearMonth(2026, 9);
      final bs = [
        Budget(
          id: 'b1',
          categoryId: 'food',
          amount: 100,
          month: 9,
          year: 2026,
          createdAt: t0,
          updatedAt: t0,
        ),
        Budget(
          id: 'b2',
          categoryId: 'fun',
          amount: 100,
          month: 9,
          year: 2026,
          createdAt: t0,
          updatedAt: t0,
        ),
      ];
      final ts = [
        txn('a', TxType.expense, 30, DateTime(2026, 9, 2), categoryId: 'food'),
        txn('b', TxType.expense, 150, DateTime(2026, 9, 3), categoryId: 'fun'),
        txn('c', TxType.income, 999, DateTime(2026, 9, 3), categoryId: 'food'),
        txn(
          'd',
          TxType.expense,
          999,
          DateTime(2026, 8, 31),
          categoryId: 'food',
        ),
      ];
      final r = computeBudgetMonth(m, bs, ts, [
        category('food'),
        category('fun'),
        category('new'),
      ]);
      expect(r.items.map((i) => i.budget.id), ['b2', 'b1']);
      expect(r.items.first.over, isTrue);
      expect(r.items.last.spent, 30);
      expect(r.items.last.remaining, 70);
      expect(r.totalSpent, 180);
      expect(r.unbudgetedCategories.map((c) => c.id), ['new']);
    });
  });

  group('reports & dashboard', () {
    final now = DateTime(2026, 9, 23, 10);
    final ts = [
      txn('a', TxType.income, 1000, DateTime(2026, 9, 1), categoryId: 'salary'),
      txn(
        'b',
        TxType.expense,
        250,
        DateTime(2026, 9, 23, 8),
        categoryId: 'food',
      ),
      txn('c', TxType.expense, 50, DateTime(2026, 8, 5)),
      txn('d', TxType.transfer, 999, DateTime(2026, 9, 5), toWalletId: 'w2'),
      txn('e', TxType.expense, 70, DateTime(2026, 3, 5), categoryId: 'food'),
    ];

    test('resolvePeriod', () {
      final six = resolvePeriod(ReportPeriod.last6Months, now);
      expect(six.months.first, const YearMonth(2026, 4));
      expect(six.months.last, const YearMonth(2026, 9));
      final year = resolvePeriod(const ReportPeriod.year(2026), now);
      expect(year.months, hasLength(9));
      expect(
        resolvePeriod(const ReportPeriod.year(2025), now).months,
        hasLength(12),
      );
    });

    test('report aggregates', () {
      final r = buildReport(
        period: ReportPeriod.last6Months,
        now: now,
        transactions: ts,
        categories: [
          category('food'),
          category('salary', type: CategoryType.income),
        ],
        wallets: [
          wallet('w1', balance: 700),
          wallet('w2', balance: 300),
          wallet('old', balance: 5, archived: true),
        ],
      );
      expect(r.totalIncome, 1000);
      expect(r.totalExpense, 300); // March excluded, transfer excluded
      expect(r.savingsRate, 70);
      expect(r.months.last.net, 750);
      expect(r.spending.map((c) => c.name), ['food', 'Tanpa kategori']);
      expect(r.spending.first.pct, closeTo(250 / 300 * 100, 1e-9));
      expect(r.netWorth, 1000);
      expect(r.wallets.map((w) => w.id), ['w1', 'w2']);
    });

    test('dashboard', () {
      final d = buildDashboard(
        now: now,
        wallets: [wallet('w1', balance: 700), wallet('w2', balance: 300)],
        categories: [category('food')],
        transactions: ts,
        monthBudgets: [
          Budget(
            id: 'b',
            categoryId: 'food',
            amount: 400,
            month: 9,
            year: 2026,
            createdAt: t0,
            updatedAt: t0,
          ),
        ],
        recent: const [],
      );
      expect(d.totalBalance, 1000);
      expect(d.monthIncome, 1000);
      expect(d.monthExpense, 250);
      expect(d.todayExpense, 250);
      expect(d.monthBudgeted, 400);
      expect(d.trend, hasLength(6));
      expect(d.trend[4].expense, 50);
    });
  });

  group('validation', () {
    test('health rules', () {
      expect(
        () => validateHealth(HealthInput(date: t0)),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => validateHealth(HealthInput(date: t0, systolic: 120)),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => validateHealth(HealthInput(date: t0, weight: 600)),
        throwsA(isA<ValidationFailure>()),
      );
      validateHealth(HealthInput(date: t0, systolic: 120, diastolic: 80));
      expect(classifyBp(135, 70)!.level, BpLevel.stage1);
    });

    test('default categories seeding is idempotent', () async {
      final seed = SeedDefaultCategories(categories, uow, clock);
      categories.s.put(
        TxCategory(
          id: 'x',
          name: 'groceries',
          type: CategoryType.expense,
          color: '#000000',
          icon: 'circle',
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      expect(
        (await seed()).valueOrThrow,
        defaultCategories.length - 2,
      ); // groceries + salary exist
      expect((await seed()).valueOrThrow, 0);
    });
  });
}
