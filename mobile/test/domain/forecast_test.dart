import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';

/// Parity with `src/app/(dashboard)/forecast/logic.ts` + `subscriptions/presets.ts`
/// (date-fns addWeeks/addMonths/addYears semantics).
void main() {
  group('occurrencesInRange (occurrencesInMonth)', () {
    final sep = const YearMonth(2026, 9);

    test('monthly anchor in the past rolls forward to the one occurrence', () {
      final r = occurrencesInRange(
        DateTime(2026, 3, 15, 9),
        BillingCycle.monthly,
        sep.start,
        sep.end,
      );
      expect(r, [DateTime(2026, 9, 15, 9)]);
    });

    test('weekly lands several times in a month', () {
      final r = occurrencesInRange(
        DateTime(2026, 8, 30),
        BillingCycle.weekly,
        sep.start,
        sep.end,
      );
      expect(r, [
        DateTime(2026, 9, 6),
        DateTime(2026, 9, 13),
        DateTime(2026, 9, 20),
        DateTime(2026, 9, 27),
      ]);
    });

    test('anchor on the 31st drifts after February (date-fns clamping)', () {
      final r = occurrencesInRange(
        DateTime(2026, 1, 31),
        BillingCycle.monthly,
        const YearMonth(2026, 4).start,
        const YearMonth(2026, 4).end,
      );
      expect(r, [DateTime(2026, 4, 28)]);
      expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
    });

    test('yearly only in its month; leap day clamps to Feb 28', () {
      expect(
        occurrencesInRange(
          DateTime(2025, 9, 2),
          BillingCycle.yearly,
          sep.start,
          sep.end,
        ),
        [DateTime(2026, 9, 2)],
      );
      expect(
        occurrencesInRange(
          DateTime(2025, 10, 2),
          BillingCycle.yearly,
          sep.start,
          sep.end,
        ),
        isEmpty,
      );
      expect(addYears(DateTime(2024, 2, 29), 1), DateTime(2025, 2, 28));
    });

    test(
      'anchor after the range → nothing; anchor on the boundaries → included',
      () {
        expect(
          occurrencesInRange(
            DateTime(2026, 10, 1),
            BillingCycle.monthly,
            sep.start,
            sep.end,
          ),
          isEmpty,
        );
        expect(
          occurrencesInRange(
            DateTime(2026, 9, 1),
            BillingCycle.monthly,
            sep.start,
            sep.end,
          ),
          [DateTime(2026, 9, 1)],
        );
        expect(
          occurrencesInRange(
            DateTime(2026, 9, 30, 23, 59, 59, 999),
            BillingCycle.monthly,
            sep.start,
            sep.end,
          ),
          hasLength(1),
        );
      },
    );
  });

  group('presets helpers', () {
    test('nextOccurrence rolls to today or later (day granularity)', () {
      final now = DateTime(2026, 9, 23, 15);
      expect(
        nextBillingOccurrence(
          DateTime(2026, 7, 23, 8),
          BillingCycle.monthly,
          now,
        ),
        DateTime(2026, 9, 23, 8),
      ); // today counts even if the time has passed
      expect(
        nextBillingOccurrence(DateTime(2026, 7, 22), BillingCycle.monthly, now),
        DateTime(2026, 10, 22),
      );
      expect(
        nextBillingOccurrence(DateTime(2026, 12, 1), BillingCycle.weekly, now),
        DateTime(2026, 12, 1),
      );
    });

    test('monthly / yearly normalisation', () {
      expect(BillingCycle.weekly.monthlyAmount(12000), 52000);
      expect(BillingCycle.yearly.monthlyAmount(120000), 10000);
      expect(BillingCycle.monthly.yearlyAmount(50000), 600000);
      expect(BillingCycle.weekly.yearlyAmount(1000), 52000);
    });
  });

  group('categoryMonthlyAverages', () {
    test('averages the last 3 complete months, expense categories only', () {
      final now = DateTime(2026, 9, 23);
      final food = category('food');
      final salary = category('salary', type: CategoryType.income);
      final txs = [
        txn('a', TxType.expense, 300, DateTime(2026, 6, 1), categoryId: 'food'),
        txn(
          'b',
          TxType.expense,
          600,
          DateTime(2026, 8, 31, 23),
          categoryId: 'food',
        ),
        txn(
          'c',
          TxType.expense,
          999,
          DateTime(2026, 9, 1),
          categoryId: 'food',
        ), // current month
        txn(
          'd',
          TxType.expense,
          999,
          DateTime(2026, 5, 31),
          categoryId: 'food',
        ), // too old
        txn(
          'e',
          TxType.income,
          900,
          DateTime(2026, 7, 1),
          categoryId: 'salary',
        ),
        txn('f', TxType.expense, 90, DateTime(2026, 7, 1)), // uncategorised
      ];
      final r = categoryMonthlyAverages(txs, [food, salary], now);
      expect(r, hasLength(1));
      expect(r.single.category.id, 'food');
      expect(r.single.avg, 300);
    });
  });

  group('buildForecast / WatchForecast', () {
    test(
      'tiers and totals match the web view (history off by default)',
      () async {
        final month = const YearMonth(2026, 10);
        final planned = [
          PlannedTransaction(
            id: 'p1',
            type: TxType.income,
            amount: 5000000,
            date: DateTime(2026, 10, 25),
            done: false,
            createdAt: t0,
            updatedAt: t0,
          ),
          PlannedTransaction(
            id: 'p2',
            type: TxType.expense,
            amount: 200000,
            date: DateTime(2026, 10, 3),
            done: true,
            createdAt: t0,
            updatedAt: t0,
          ),
          PlannedTransaction(
            id: 'p3',
            type: TxType.expense,
            amount: 100000,
            date: DateTime(2026, 10, 10),
            done: false,
            createdAt: t0,
            updatedAt: t0,
          ),
          PlannedTransaction(
            id: 'out',
            type: TxType.expense,
            amount: 1,
            date: DateTime(2026, 11, 1),
            done: false,
            createdAt: t0,
            updatedAt: t0,
          ),
        ];
        final subs = [
          subscription('netflix', DateTime(2026, 1, 4), amount: 54000),
          subscription(
            'gym',
            DateTime(2026, 9, 28),
            cycle: BillingCycle.weekly,
            amount: 25000,
          ),
          subscription('paused', DateTime(2026, 1, 1), active: false),
        ];
        final f = buildForecast(
          month: month,
          planned: planned,
          subscriptions: subs,
          averages: [CategoryAverage(category: category('food'), avg: 1000)],
        );
        expect(f.planned.map((p) => p.id), [
          'p3',
          'p1',
          'p2',
        ]); // not-done first, by date
        expect(f.subscriptionItems.map((s) => s.subscription.id), [
          'netflix',
          'gym',
          'gym',
          'gym',
          'gym',
        ]);
        expect(f.subscriptionsExpense, 54000 + 4 * 25000);
        final t = f.totals();
        expect(t.projectedExpense, 300000 + 154000);
        expect(t.projectedIncome, 5000000);
        expect(t.net, 5000000 - 454000);
        expect(
          f.totals(const ForecastSources(history: true)).projectedExpense,
          455000,
        );
        expect(
          f.totals(const ForecastSources(manual: false)).projectedIncome,
          0,
        );
      },
    );

    test('WatchForecast defaults to next month', () async {
      final planned = FakePlannedRepository();
      final subs = FakeSubscriptionRepository();
      final tx = FakeTransactionRepository();
      final cats = FakeCategoryRepository();
      final watch = WatchForecast(
        planned,
        subs,
        tx,
        cats,
        FixedClock(DateTime(2026, 9, 23)),
      );
      final stream = watch();
      final first = await stream.first;
      expect(first.month, const YearMonth(2026, 10));
      expect(first.isEmpty, isTrue);
      expect(
        defaultForecastMonth(DateTime(2026, 12, 5)),
        const YearMonth(2027, 1),
      );
    });
  });
}
