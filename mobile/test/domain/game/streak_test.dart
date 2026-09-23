import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';

GameDate d(int day, [int month = 9]) => GameDate(2026, month, day);

StreakResult run(
  List<GameDate> logged,
  GameDate today, {
  Set<GameDate> recorded = const {},
  List<GameDate> grants = const [],
}) => StreakCalculator.compute(
  loggedDays: logged,
  today: today,
  recordedFrozenDays: recorded,
  grantedFreezes: grants,
);

List<GameDate> range(GameDate from, GameDate to) => [
  for (var x = from; !x.isAfter(to); x = x.addDays(1)) x,
];

void main() {
  group('GameDate', () {
    test('local days split at midnight', () {
      expect(GameDate.fromDateTime(DateTime(2026, 9, 1, 23, 59, 59)), d(1));
      expect(GameDate.fromDateTime(DateTime(2026, 9, 2, 0, 0, 1)), d(2));
    });

    test('UTC instants are converted to the local day', () {
      final utc = DateTime.utc(2026, 9, 1, 23, 30);
      expect(GameDate.fromDateTime(utc), GameDate.fromDateTime(utc.toLocal()));
    });

    test('arithmetic across month/year and DST boundaries', () {
      expect(GameDate(2026, 12, 31).addDays(1), GameDate(2027, 1, 1));
      expect(GameDate(2024, 3, 1).addDays(-1), GameDate(2024, 2, 29));
      expect(GameDate(2026, 3, 30).difference(GameDate(2026, 3, 28)), 2);
      expect(GameDate(2026, 11, 2).difference(GameDate(2026, 10, 31)), 2);
    });

    test('parse / key round-trip and invalid dates', () {
      expect(GameDate.tryParse('2026-09-05'), d(5));
      expect(d(5).toKey(), '2026-09-05');
      expect(GameDate.tryParse('2026-02-31'), isNull);
      expect(GameDate.tryParse('nope'), isNull);
    });

    test('GameMonth bounds', () {
      expect(const GameMonth(2024, 2).dayCount, 29);
      expect(const GameMonth(2026, 12).next, const GameMonth(2027, 1));
      expect(const GameMonth(2026, 1).previous, const GameMonth(2025, 12));
    });
  });

  group('StreakCalculator', () {
    test('no data = no streak', () {
      final r = run([], d(10));
      expect(r.current, 0);
      expect(r.longest, 0);
      expect(r.atRisk, isFalse);
      expect(r.statusOn(d(10)), StreakDayStatus.none);
    });

    test('consecutive days including today', () {
      final r = run([d(8), d(9), d(10)], d(10));
      expect(r.current, 3);
      expect(r.loggedToday, isTrue);
      expect(r.atRisk, isFalse);
      expect(r.currentStart, d(8));
    });

    test('today not logged yet: streak alive but at risk', () {
      final r = run([d(8), d(9)], d(10));
      expect(r.current, 2);
      expect(r.atRisk, isTrue);
      expect(r.statusOn(d(10)), StreakDayStatus.pending);
    });

    test('missing yesterday breaks the streak (no freezes)', () {
      final r = run([d(7), d(8)], d(10));
      expect(r.current, 0);
      expect(r.longest, 2);
      expect(r.statusOn(d(9)), StreakDayStatus.missed);
      expect(r.atRisk, isFalse);
    });

    test('gap then restart', () {
      final r = run([d(1), d(2), d(3), d(6), d(7)], d(7));
      expect(r.current, 2);
      expect(r.longest, 3);
      expect(r.statusOn(d(4)), StreakDayStatus.missed);
      expect(r.statusOn(d(5)), StreakDayStatus.missed);
    });

    test('multiple events on the same day count once', () {
      final r = run([d(9), d(9), d(10), d(10)], d(10));
      expect(r.current, 2);
    });

    test('future-dated entries are ignored', () {
      final r = run([d(10), d(11), d(12)], d(10));
      expect(r.current, 1);
    });

    test('7-day streak earns a freeze that covers a missed day', () {
      final logged = [...range(d(1), d(7)), d(9)];
      final r = run(logged, d(9));
      expect(r.freezesEarned, [d(7)]);
      expect(r.statusOn(d(8)), StreakDayStatus.frozen);
      expect(r.newlyFrozenDays, {d(8)});
      expect(r.current, 8); // frozen day doesn't add
      expect(r.freezesHeld, 0);
    });

    test('freeze covers yesterday while today is still pending', () {
      final r = run(range(d(1), d(7)), d(9));
      expect(r.statusOn(d(8)), StreakDayStatus.frozen);
      expect(r.current, 7);
      expect(r.atRisk, isTrue);
    });

    test('no freeze before 7 days', () {
      final r = run([...range(d(1), d(6)), d(8)], d(8));
      expect(r.statusOn(d(7)), StreakDayStatus.missed);
      expect(r.current, 1);
    });

    test('freezes are capped at the max held', () {
      final r = run(range(d(1), d(28)), d(28));
      expect(r.freezesEarned.length, 4);
      expect(r.freezesHeld, XpRules.maxFreezesHeld);
    });

    test('two freezes cover two consecutive days, the third day breaks', () {
      final r1 = run([...range(d(1), d(14)), d(17)], d(17));
      expect(r1.statusOn(d(15)), StreakDayStatus.frozen);
      expect(r1.statusOn(d(16)), StreakDayStatus.frozen);
      expect(r1.current, 15);

      final r2 = run([...range(d(1), d(14)), d(18)], d(18));
      expect(r2.statusOn(d(17)), StreakDayStatus.missed);
      expect(r2.current, 1);
      expect(r2.longest, 14);
    });

    test(
      'recorded frozen days stay frozen even if the earning day disappears',
      () {
        // Originally 1..7 + 9 with 8 frozen; later day 3 got deleted.
        final r = run(
          [d(1), d(2), d(4), d(5), d(6), d(7), d(9)],
          d(9),
          recorded: {d(3), d(8)},
        );
        expect(r.statusOn(d(3)), StreakDayStatus.frozen);
        expect(r.statusOn(d(8)), StreakDayStatus.frozen);
        expect(r.current, 7);
        expect(r.newlyFrozenDays, isEmpty);
      },
    );

    test('recorded frozen days are stable across recomputation', () {
      final logged = [...range(d(1), d(7)), d(9), d(10)];
      final first = run(logged, d(10));
      final second = run(logged, d(10), recorded: first.newlyFrozenDays);
      expect(second.current, first.current);
      expect(second.newlyFrozenDays, isEmpty);
      expect(second.frozenDays, first.frozenDays);
    });

    test('granted freezes can save a streak', () {
      final r = run([d(1), d(2), d(4)], d(4), grants: [d(1)]);
      expect(r.statusOn(d(3)), StreakDayStatus.frozen);
      expect(r.current, 3);
    });

    test('milestones are recorded (and again after a reset)', () {
      final r = run([...range(d(1), d(3)), ...range(d(10), d(12))], d(12));
      expect(r.milestones, [
        StreakMilestoneHit(d(3), 3),
        StreakMilestoneHit(d(12), 3),
      ]);
      expect(r.milestoneToday, StreakMilestoneHit(d(12), 3));
      expect(r.nextMilestone, 7);
    });

    test('long streak across months and years', () {
      final start = GameDate(2025, 12, 1);
      final today = GameDate(2026, 3, 10);
      final r = run(range(start, today), today);
      expect(r.current, today.difference(start) + 1);
      expect(r.milestones.map((m) => m.length), [3, 7, 14, 30, 50, 100]);
    });

    test('month calendar data', () {
      final r = run([...range(d(1), d(7)), d(9)], d(10));
      final cal = r.month(2026, 9);
      expect(cal.length, 30);
      expect(cal[0].status, StreakDayStatus.logged);
      expect(cal[7].status, StreakDayStatus.frozen);
      expect(cal[9].status, StreakDayStatus.pending);
      expect(cal[10].status, StreakDayStatus.none);
      expect(
        r.month(2026, 8).every((c) => c.status == StreakDayStatus.none),
        isTrue,
      );
    });
  });
}
