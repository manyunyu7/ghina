import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';

BudgetStatus b(String id, double budget, double spent, {int month = 9}) =>
    BudgetStatus(
      categoryId: id,
      year: 2026,
      month: month,
      budget: budget,
      spent: spent,
    );

MascotContext ctx({
  int hour = 10,
  int streak = 5,
  bool logged = false,
  bool goalMet = false,
  int remaining = 2,
  int hearts = 5,
  int longest = 5,
  String? name,
}) => MascotContext(
  now: DateTime(2026, 9, 10, hour),
  streak: streak,
  loggedToday: logged,
  goalMet: goalMet,
  goalRemaining: remaining,
  hearts: hearts,
  maxHearts: 5,
  longestStreak: longest,
  name: name,
);

void main() {
  const month = GameMonth(2026, 9);

  group('Hearts', () {
    test('full hearts without overspending', () {
      final h = HeartsCalculator.compute([b('a', 100, 50)], month);
      expect(h.current, 5);
      expect(h.isFull, isTrue);
      expect(h.budgetCount, 1);
    });

    test('one heart lost per over-budget category, other months ignored', () {
      final h = HeartsCalculator.compute([
        b('a', 100, 150),
        b('b', 100, 101),
        b('c', 100, 95),
        b('d', 100, 500, month: 8),
      ], month);
      expect(h.current, 3);
      expect(h.overBudget.map((e) => e.categoryId), ['a', 'b']);
      expect(h.nearLimit.map((e) => e.categoryId), ['c']);
      expect(h.lost, 2);
    });

    test('exactly at budget is not over', () {
      expect(HeartsCalculator.compute([b('a', 100, 100)], month).current, 5);
    });

    test('never below zero', () {
      final h = HeartsCalculator.compute([
        for (var i = 0; i < 8; i++) b('c$i', 10, 20),
      ], month);
      expect(h.current, 0);
      expect(h.isEmpty, isTrue);
    });
  });

  group('Mascot mood', () {
    test('celebrates when the goal is met', () {
      expect(
        Mascot.moodFor(ctx(logged: true, goalMet: true, remaining: 0)),
        MascotMood.celebrating,
      );
    });

    test('worried when the streak is at risk in the evening', () {
      expect(Mascot.moodFor(ctx(hour: 20)), MascotMood.worried);
      expect(Mascot.moodFor(ctx(hour: 23)), MascotMood.worried);
    });

    test('encouraging in the morning when not logged yet', () {
      expect(Mascot.moodFor(ctx(hour: 9)), MascotMood.encouraging);
    });

    test('sleeping at night when nothing is at risk', () {
      expect(Mascot.moodFor(ctx(hour: 23, logged: true)), MascotMood.sleeping);
      expect(
        Mascot.moodFor(ctx(hour: 2, logged: true, goalMet: true)),
        MascotMood.sleeping,
      );
    });

    test('worried when hearts are low, sad when empty', () {
      expect(Mascot.moodFor(ctx(logged: true, hearts: 1)), MascotMood.worried);
      expect(Mascot.moodFor(ctx(logged: true, hearts: 0)), MascotMood.sad);
    });

    test('sad after losing a streak', () {
      expect(Mascot.moodFor(ctx(streak: 0, longest: 12)), MascotMood.sad);
    });

    test('happy when logged and fine', () {
      expect(Mascot.moodFor(ctx(logged: true)), MascotMood.happy);
    });
  });

  group('Mascot messages', () {
    test('every mood has several variants', () {
      for (final mood in MascotMood.values) {
        expect(
          Mascot.messages[mood]!.length,
          greaterThanOrEqualTo(4),
          reason: '$mood',
        );
      }
    });

    test('placeholders are always filled and deterministic per seed', () {
      for (final mood in MascotMood.values) {
        for (var seed = 0; seed < 12; seed++) {
          for (final c in [
            ctx(),
            ctx(streak: 0, remaining: 0, hearts: 0, longest: 0),
            ctx(name: 'Ghina'),
          ]) {
            final m = Mascot.messageFor(mood, c, seed: seed);
            expect(m, isNot(contains('{')), reason: m);
            expect(m, Mascot.messageFor(mood, c, seed: seed));
          }
        }
      }
    });

    test('messages reflect the numbers', () {
      final lines = {
        for (var s = 0; s < 20; s++)
          Mascot.messageFor(MascotMood.worried, ctx(hour: 21), seed: s),
      };
      expect(lines.any((l) => l.contains('5 hari')), isTrue);
      expect(lines.any((l) => l.contains('Hati tinggal')), isFalse);
      final heartLines = {
        for (var s = 0; s < 20; s++)
          Mascot.messageFor(
            MascotMood.worried,
            ctx(logged: true, hearts: 1),
            seed: s,
          ),
      };
      expect(heartLines.every((l) => l.contains('Hati tinggal 1')), isTrue);
    });

    test('variety across seeds', () {
      final lines = {
        for (var s = 0; s < 30; s++)
          Mascot.messageFor(MascotMood.encouraging, ctx(), seed: s),
      };
      expect(lines.length, greaterThan(3));
    });
  });
}
