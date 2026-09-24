import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart'
    show ContentStage, weeklyTargetXp;
import 'package:ghina/domain/game/game.dart';

final now = DateTime(2026, 9, 24, 15); // Thursday
final today = GameDate.fromDateTime(now);
DateTime at(int day, [int hour = 10, int minute = 0]) =>
    DateTime(2026, 9, day, hour, minute);

ActivityEvent stage(
  String item,
  ContentStage s, {
  int day = 24,
  int minute = 0,
}) => ActivityEvent.contentStage(
  itemId: item,
  stage: s.wire,
  reachedAt: at(day, 10, minute),
  stageXp: s.xp,
);

ActivityEvent posted(
  String id, {
  int day = 24,
  bool onSchedule = false,
  String account = 'ig',
}) => ActivityEvent.contentPosted(
  postId: id,
  itemId: 'i-$id',
  accountId: account,
  platform: 'instagram',
  postedAt: at(day, 19),
  onSchedule: onSchedule,
);

ActivityEvent weekly(String account, GameDate monday, {DateTime? when}) =>
    ActivityEvent.contentWeeklyTarget(
      accountId: account,
      platform: 'instagram',
      weekStart: monday,
      at: when ?? monday.addDays(4).toLocalDateTime(),
      target: 3,
    );

GameSnapshot snap(
  List<ActivityEvent> events, {
  GameLocalState local = const GameLocalState(lastSeenLevel: 1),
}) => const ComputeGameSnapshot()(
  events: events,
  budgets: const [],
  local: local,
  now: now,
);

void main() {
  group('Content XP', () {
    test('stage XP mirrors the shared stage table', () {
      for (final s in ContentStage.values) {
        expect(XpRules.contentStage(s.wire), s.xp, reason: s.wire);
      }
      expect(XpRules.contentWeeklyTarget, weeklyTargetXp);
    });

    test('each stage reached earns its XP and counts toward the goal', () {
      final s = snap([
        stage('a', ContentStage.naskah),
        stage('a', ContentStage.produksi),
        stage('a', ContentStage.siap),
        stage('a', ContentStage.terjadwal),
        stage('a', ContentStage.tayang),
      ]).summary;
      final day = s.xp.dayOf(today)!;
      expect(day.breakdown[XpSource.contentStage], 3 + 4 + 5 + 6 + 10);
      expect(day.contentCounted, 5);
      expect(s.goal.done, 5);
    });

    test('the same stage event twice is deduped by id', () {
      final day = snap([
        stage('a', ContentStage.naskah),
        stage('a', ContentStage.naskah),
      ]).summary.xp.dayOf(today)!;
      expect(day.breakdown[XpSource.contentStage], 3);
    });

    test('falls back to the rules table when the event has no XP', () {
      final day = snap([
        ActivityEvent.contentStage(
          itemId: 'x',
          stage: 'tayang',
          reachedAt: at(24),
        ),
      ]).summary.xp.dayOf(today)!;
      expect(day.breakdown[XpSource.contentStage], 10);
    });

    test('posting on schedule earns a bonus; late posts only count', () {
      final day = snap([
        posted('p1', onSchedule: true),
        posted('p2'),
      ]).summary.xp.dayOf(today)!;
      expect(
        day.breakdown[XpSource.contentOnSchedule],
        XpRules.contentOnSchedule,
      );
      expect(day.contentCounted, 2);
      expect(day.activities, 2);
    });

    test('weekly target met +20 and sponsor paid are bonuses', () {
      final day = snap([
        weekly('ig', GameDate(2026, 9, 21), when: at(24, 20)),
        ActivityEvent.contentSponsorPaid(itemId: 'i1', at: at(24), amount: 1),
      ]).summary.xp.dayOf(today)!;
      expect(day.breakdown[XpSource.contentWeeklyTarget], 20);
      expect(
        day.breakdown[XpSource.contentSponsor],
        XpRules.contentSponsorPaid,
      );
      expect(day.activities, 0);
    });

    test('at most ${XpRules.contentBonusDailyCap} bonuses a day earn XP', () {
      final day = snap([
        for (var i = 0; i < 4; i++)
          weekly('acc$i', GameDate(2026, 9, 21), when: at(24, 8, i)),
        for (var i = 0; i < 4; i++)
          ActivityEvent.contentSponsorPaid(itemId: 's$i', at: at(24, 9, i)),
      ]).summary.xp.dayOf(today)!;
      expect(day.contentBonuses, XpRules.contentBonusDailyCap);
      expect(
        day.breakdown[XpSource.contentWeeklyTarget],
        XpRules.contentBonusDailyCap * XpRules.contentWeeklyTarget,
      );
      expect(day.breakdown[XpSource.contentSponsor], isNull);
    });

    test('at most ${XpRules.contentDailyCap} milestones a day earn XP', () {
      final events = [
        for (var i = 0; i < 25; i++)
          stage('i$i', ContentStage.naskah, minute: i),
      ];
      final day = snap(events).summary.xp.dayOf(today)!;
      expect(day.contentTotal, 25);
      expect(day.contentCounted, XpRules.contentDailyCap);
      expect(day.breakdown[XpSource.contentStage], XpRules.contentDailyCap * 3);
    });

    test('content never touches the transaction streak', () {
      final s = snap([posted('p1'), stage('a', ContentStage.naskah)]).summary;
      expect(s.streak.current, 0);
    });
  });

  group('Content achievements', () {
    AchievementsState ach(List<ActivityEvent> events) =>
        snap(events).achievements;

    test('first post and 50 posts', () {
      expect(ach([]).byId('first_content_post')!.unlocked, isFalse);
      expect(ach([posted('p1')]).byId('first_content_post')!.unlocked, isTrue);
      final many = [
        for (var i = 0; i < 50; i++) posted('p$i', day: 1 + i % 24),
      ];
      final a = ach(many);
      expect(a.byId('content_posts_50')!.unlocked, isTrue);
      expect(ach(many.sublist(1)).byId('content_posts_50')!.current, 49);
    });

    test('4-week consistency needs consecutive weeks of one account', () {
      final m = GameDate(2026, 8, 31);
      final three = [
        for (var i = 0; i < 3; i++) weekly('ig', m.addDays(7 * i)),
      ];
      expect(ach(three).byId('content_consistency_4')!.current, 3);
      // A gap breaks the run; another account doesn't bridge it.
      final gap = [
        ...three,
        weekly('tt', m.addDays(21)),
        weekly('ig', m.addDays(28)),
      ];
      expect(ach(gap).byId('content_consistency_4')!.unlocked, isFalse);
      final four = [...three, weekly('ig', m.addDays(21))];
      expect(ach(four).byId('content_consistency_4')!.unlocked, isTrue);
    });

    test('first sponsor', () {
      final a = ach([
        ActivityEvent.contentSponsorPaid(itemId: 'i1', at: at(20)),
      ]);
      expect(a.byId('first_sponsor')!.unlocked, isTrue);
    });

    test('Indonesian copy', () {
      for (final id in [
        'first_content_post',
        'content_consistency_4',
        'content_posts_50',
        'first_sponsor',
      ]) {
        final d = achievementDefs.firstWhere((d) => d.id == id);
        expect(d.title, isNotEmpty);
        expect(d.description, isNot(contains('Anda')));
      }
    });

    test('bestWeeklyRun', () {
      final m = GameDate(2026, 1, 5);
      expect(AchievementStats.bestWeeklyRun([]), 0);
      expect(
        AchievementStats.bestWeeklyRun([
          m,
          m.addDays(7),
          m.addDays(21),
          m.addDays(28),
          m.addDays(35),
        ]),
        3,
      );
    });
  });
}
