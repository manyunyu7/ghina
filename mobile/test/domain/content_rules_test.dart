// Parity with the server's content module (`src/lib/content.ts`), mirroring the
// cases of `scripts/test-content.mjs` (docs/content.md). The server works in
// Asia/Jakarta; the device uses its local time, so the WIB instants of the
// server cases are written here as local times.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';

final _t0 = DateTime(2026, 8, 1);

SocialAccount acc(
  String id, {
  SocialPlatform platform = SocialPlatform.instagram,
  int? target,
  bool archived = false,
  int sortOrder = 0,
  String? platformName,
}) => SocialAccount(
  id: id,
  platform: platform,
  platformName: platformName,
  handle: id,
  color: platform.color,
  targetPerWeek: target,
  archived: archived,
  sortOrder: sortOrder,
  createdAt: _t0,
  updatedAt: _t0,
);

ContentPost post(
  String id, {
  String contentId = 'c',
  String accountId = 'ig',
  PostStatus status = PostStatus.draft,
  DateTime? scheduledAt,
  DateTime? postedAt,
  PostMetrics metrics = PostMetrics.empty,
  DateTime? metricsAt,
}) => ContentPost(
  id: id,
  contentId: contentId,
  accountId: accountId,
  status: status,
  scheduledAt: scheduledAt,
  postedAt: postedAt,
  metrics: metrics,
  metricsAt: metricsAt,
  createdAt: _t0,
  updatedAt: _t0,
);

ContentItem item(
  String id, {
  String title = 'x',
  String? pillar,
  ContentFormat? format,
  Sponsor? sponsor,
  ContentStage stage = ContentStage.ide,
}) => ContentItem(
  id: id,
  title: title,
  pillar: pillar,
  format: format,
  sponsor: sponsor,
  stage: stage,
  createdAt: _t0,
  updatedAt: _t0,
);

List<ContentPost> statuses(List<PostStatus> s) => [
  for (final (i, x) in s.indexed)
    post(
      'p$i',
      status: x,
      scheduledAt: DateTime(2026, 9, 1),
      postedAt: DateTime(2026, 9, 1),
    ),
];

void main() {
  final clock = FixedClock(DateTime(2026, 9, 24, 10));

  group('platform registry', () {
    test('8 platforms in order, each with label/code/color/icon', () {
      expect(SocialPlatform.values.map((p) => p.wire), [
        'instagram',
        'tiktok',
        'youtube',
        'x',
        'threads',
        'linkedin',
        'facebook',
        'other',
      ]);
      expect(SocialPlatform.values.map((p) => p.code), [
        'IG',
        'TT',
        'YT',
        'X',
        'TH',
        'IN',
        'FB',
        'LAIN',
      ]);
      for (final p in SocialPlatform.values) {
        expect(
          RegExp(r'^#[0-9A-F]{6}$', caseSensitive: false).hasMatch(p.color),
          isTrue,
        );
        expect(p.icon, isNotEmpty);
      }
    });
    test('profile URL: @ stripped + encoded', () {
      expect(
        platformUrl(SocialPlatform.instagram.profileUrl, '@ghina.id'),
        'https://www.instagram.com/ghina.id/',
      );
      expect(
        platformUrl(SocialPlatform.tiktok.profileUrl, 'a b'),
        'https://www.tiktok.com/@a%20b',
      );
      expect(
        acc('@ghina.id').profileUrl,
        'https://www.instagram.com/ghina.id/',
      );
      expect(acc('ghina').appUrl, 'instagram://user?username=ghina');
    });
    test('other has no URL; unknown platform → other', () {
      expect(platformUrl(SocialPlatform.other.profileUrl, 'x'), isNull);
      expect(SocialPlatform.fromWire('myspace'), SocialPlatform.other);
    });
    test('label / code for other', () {
      final p = acc(
        'a',
        platform: SocialPlatform.other,
        platformName: 'Pinterest',
      );
      expect(p.platformLabel, 'Pinterest');
      expect(p.code, 'PINT');
      expect(otherPlatformCode('!!'), 'LAIN');
      expect(otherPlatformCode('Café'), 'CAFE');
    });
    test('notification title [IG-TAYANG]', () {
      expect(
        postNotificationTitle(acc('ig'), 'Tips hemat'),
        '[IG-TAYANG] Tips hemat',
      );
    });
  });

  group('stages', () {
    test('order and XP', () {
      expect(ContentStage.values.map((s) => s.wire), [
        'ide',
        'naskah',
        'produksi',
        'siap',
        'terjadwal',
        'tayang',
      ]);
      expect(stageXp(ContentStage.ide, ContentStage.naskah), 3);
      expect(stageXp(ContentStage.terjadwal, ContentStage.tayang), 10);
      expect(stageXp(ContentStage.ide, ContentStage.tayang), 28);
      expect(stageXp(ContentStage.tayang, ContentStage.ide), 0);
    });
    test('autoStage', () {
      const d = PostStatus.draft,
          s = PostStatus.scheduled,
          p = PostStatus.posted,
          k = PostStatus.skipped;
      expect(autoStage(ContentStage.naskah, const []), ContentStage.naskah);
      expect(
        autoStage(ContentStage.produksi, statuses([d, s])),
        ContentStage.terjadwal,
      );
      expect(
        autoStage(ContentStage.tayang, statuses([s])),
        ContentStage.tayang,
      );
      expect(
        autoStage(ContentStage.terjadwal, statuses([p, k, p])),
        ContentStage.tayang,
      );
      expect(autoStage(ContentStage.siap, statuses([p, d])), ContentStage.siap);
      expect(
        autoStage(ContentStage.siap, statuses([p, s])),
        ContentStage.terjadwal,
      );
      expect(autoStage(ContentStage.siap, statuses([k, k])), ContentStage.siap);
      expect(
        autoStage(ContentStage.tayang, statuses([d])),
        ContentStage.tayang,
      );
      expect(ContentStage.fromWire('weird'), ContentStage.ide);
    });
    test('recordStage fills skipped stages once', () {
      final a = DateTime(2026, 9, 1), b = DateTime(2026, 9, 2);
      var log = recordStage(const {}, ContentStage.produksi, a);
      expect(log.keys, [
        ContentStage.ide,
        ContentStage.naskah,
        ContentStage.produksi,
      ]);
      log = recordStage(log, ContentStage.siap, b);
      expect(log[ContentStage.naskah], a);
      expect(log[ContentStage.siap], b);
    });
  });

  group('account input (server socialAccountSchema)', () {
    late CreateSocialAccount create;
    setUp(
      () => create = CreateSocialAccount(FakeSocialAccountRepository(), clock),
    );

    test(
      'defaults: platform color, platformName null for built-ins, 0 → no target',
      () async {
        final a = (await create(
          const SocialAccountInput(
            platform: SocialPlatform.instagram,
            handle: ' @ghina ',
            platformName: 'ignored',
            targetPerWeek: 3,
          ),
        )).valueOrThrow;
        expect(
          [a.color, a.platformName, a.handle, a.targetPerWeek, a.archived],
          ['#E1306C', null, '@ghina', 3, false],
        );
        final b = (await create(
          const SocialAccountInput(
            platform: SocialPlatform.x,
            handle: 'a',
            targetPerWeek: 0,
          ),
        )).valueOrThrow;
        expect(b.targetPerWeek, isNull);
        expect(b.sortOrder, 1);
      },
    );
    test('other needs platformName; limits', () async {
      final r = await create(
        const SocialAccountInput(platform: SocialPlatform.other, handle: 'a'),
      );
      expect(r.failureOrNull!.message, contains('nama platform'));
      final ok = (await create(
        const SocialAccountInput(
          platform: SocialPlatform.other,
          platformName: 'Pinterest',
          handle: 'a',
        ),
      )).valueOrThrow;
      expect(ok.platformName, 'Pinterest');
      expect(
        (await create(
          SocialAccountInput(platform: SocialPlatform.x, handle: 'a' * 61),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          const SocialAccountInput(
            platform: SocialPlatform.x,
            handle: 'a',
            targetPerWeek: 51,
          ),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          const SocialAccountInput(
            platform: SocialPlatform.x,
            handle: 'a',
            color: '#123456',
          ),
        )).valueOrThrow.color,
        '#123456',
      );
    });
  });

  group('item input (server contentItemSchema)', () {
    late CreateContentItem create;
    setUp(() => create = CreateContentItem(FakeContentItemRepository(), clock));

    test('defaults and normalization', () async {
      final it = (await create(
        const ContentItemInput(title: '  Review\nHP  '),
      )).valueOrThrow;
      expect(
        [
          it.title,
          it.stage,
          it.format,
          it.pillar,
          it.idea,
          it.noteId,
          it.sponsor,
        ],
        ['Review HP', ContentStage.ide, null, null, '', null, null],
      );
      final full = (await create(
        ContentItemInput(
          title: 'Endorse kopi',
          stage: ContentStage.produksi,
          format: ContentFormat.reel,
          pillar: ' Promo ',
          idea: '# Hook\r\nCoba kopi',
          checklist: const [ChecklistItem(id: 'c1', text: 'Rekam')],
          photos: const [TransactionPhoto.remote('/uploads/t.jpg')],
          assetLinks: const [
            AssetLink(url: 'https://drive.google.com/x', label: ' Draft '),
            AssetLink(url: 'https://canva.com/y'),
          ],
          sponsor: SponsorInput(
            brand: ' Kopi Kita ',
            amount: 1500000,
            currency: 'idr',
            due: DateTime(2026, 10, 1),
          ),
        ),
      )).valueOrThrow;
      expect(full.pillar, 'Promo');
      expect(full.idea, '# Hook\nCoba kopi');
      expect(full.assetLinks, const [
        AssetLink(url: 'https://drive.google.com/x', label: 'Draft'),
        AssetLink(url: 'https://canva.com/y'),
      ]);
      expect(
        full.sponsor,
        const Sponsor(brand: 'Kopi Kita', amount: 1500000, due: '2026-10-01'),
      );
    });
    test('errors', () async {
      expect(
        (await create(
          const ContentItemInput(title: '  '),
        )).failureOrNull!.message,
        'Judul wajib diisi',
      );
      expect(
        (await create(
          const ContentItemInput(
            title: 'a',
            sponsor: SponsorInput(brand: 'b', amount: -1),
          ),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          const ContentItemInput(
            title: 'a',
            sponsor: SponsorInput(brand: 'b', amount: 1, currency: 'RUPIAH'),
          ),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          const ContentItemInput(
            title: 'a',
            sponsor: SponsorInput(brand: 'b', amount: 0),
          ),
        )).isOk,
        isTrue,
      );
      expect(
        (await create(
          const ContentItemInput(
            title: 'a',
            assetLinks: [AssetLink(url: 'javascript:1')],
          ),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          ContentItemInput(
            title: 'a',
            assetLinks: [
              for (var i = 0; i < 21; i++) AssetLink(url: 'https://x.id/$i'),
            ],
          ),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          ContentItemInput(
            title: 'a',
            photos: [
              for (var i = 0; i < 11; i++)
                TransactionPhoto.remote('/uploads/p$i.png'),
            ],
          ),
        )).isOk,
        isFalse,
      );
    });
  });

  group('post input (server contentPostSchema)', () {
    late FakeContentPostRepository posts;
    late FakeContentItemRepository items;
    late FakeSocialAccountRepository accounts;
    late CreateContentPost create;
    setUp(() async {
      posts = FakeContentPostRepository();
      items = FakeContentItemRepository();
      accounts = FakeSocialAccountRepository();
      await items.save(item('c'));
      await accounts.save(acc('a'));
      await accounts.save(acc('b'));
      create = CreateContentPost(
        posts,
        items,
        accounts,
        FakeUnitOfWork(),
        clock,
      );
    });

    test('defaults; scheduledAt → scheduled; one post per account', () async {
      final p = (await create(
        'c',
        const ContentPostInput(accountId: 'a'),
      )).valueOrThrow;
      expect(
        [
          p.status,
          p.caption,
          p.hashtags,
          p.scheduledAt,
          p.postedAt,
          p.url,
          p.metrics,
          p.metricsAt,
        ],
        [PostStatus.draft, '', '', null, null, null, PostMetrics.empty, null],
      );
      expect(
        (await create('c', const ContentPostInput(accountId: 'a'))).isOk,
        isFalse,
      );
      final s = (await create(
        'c',
        ContentPostInput(
          accountId: 'b',
          scheduledAt: DateTime(2026, 9, 25, 12),
        ),
      )).valueOrThrow;
      expect(s.status, PostStatus.scheduled);
      // Auto-advance: a scheduled post moves the item to terjadwal.
      expect((await items.getById('c'))!.stage, ContentStage.terjadwal);
    });
    test('url must be http(s); caption/hashtags/remindBefore limits', () async {
      expect(
        (await create(
          'c',
          const ContentPostInput(accountId: 'a', url: 'javascript:alert(1)'),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          'c',
          const ContentPostInput(
            accountId: 'a',
            url: ' https://instagram.com/p/x ',
          ),
        )).valueOrThrow.url,
        'https://instagram.com/p/x',
      );
      expect(
        (await create(
          'c',
          ContentPostInput(accountId: 'b', caption: 'x' * 5001),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          'c',
          ContentPostInput(accountId: 'b', hashtags: '#' * 1001),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          'c',
          const ContentPostInput(accountId: 'b', remindBefore: 10081),
        )).isOk,
        isFalse,
      );
      expect(
        (await create(
          'c',
          const ContentPostInput(accountId: 'b', remindBefore: 0),
        )).isOk,
        isTrue,
      );
    });
    test('metrics parsing: unknown keys dropped, negative dropped', () {
      expect(
        PostMetrics.parse({'views': 100, 'likes': null, 'foo': 3}),
        const PostMetrics(views: 100),
      );
      expect(PostMetrics.parse('oops'), PostMetrics.empty);
    });
  });

  group('pillars', () {
    test('default pillars (deterministic ids, order)', () {
      final d = defaultPillars('u1', DateTime(2026));
      expect(
        [for (final p in d) (p.id, p.name, p.sortOrder)],
        [
          ('pillar-edukasi-u1', 'Edukasi', 0),
          ('pillar-hiburan-u1', 'Hiburan', 1),
          ('pillar-promo-u1', 'Promo', 2),
          ('pillar-bts-u1', 'Behind the scene', 3),
          ('pillar-personal-u1', 'Personal', 4),
        ],
      );
      expect(pillarNameTaken(d, 'edukasi'), isTrue);
      expect(
        pillarNameTaken(d, 'EDUKASI', exceptId: 'pillar-edukasi-u1'),
        isFalse,
      );
      expect(pillarNameTaken(d, 'Tutorial'), isFalse);
    });
    test('pillar name 1–30', () async {
      final c = CreateContentPillar(FakeContentPillarRepository(), clock);
      expect((await c(const ContentPillarInput(name: ''))).isOk, isFalse);
      expect((await c(ContentPillarInput(name: 'x' * 31))).isOk, isFalse);
      expect(
        (await c(const ContentPillarInput(name: ' Tips '))).valueOrThrow.name,
        'Tips',
      );
    });
  });

  group('weeks / slots / consistency', () {
    test('weekStart Monday; weeks in range; full weeks', () {
      expect(weekStartOf(DateTime(2026, 9, 24)), DateTime(2026, 9, 21));
      expect(weekStartOf(DateTime(2026, 9, 21)), DateTime(2026, 9, 21));
      expect(weekStartOf(DateTime(2026, 9, 27, 23)), DateTime(2026, 9, 21));
      expect(
        weeksIn(DateTime(2026, 9, 24), DateTime(2026, 10, 5)).map(dateKey),
        ['2026-09-21', '2026-09-28', '2026-10-05'],
      );
      expect(
        fullWeeksIn(DateTime(2026, 9, 1), DateTime(2026, 9, 21)).map(dateKey),
        ['2026-09-07', '2026-09-14'],
      );
      expect(daysIn(DateTime(2026, 8, 31), DateTime(2026, 9, 13)), 14);
    });
    test(
      'week slots (IG planned 2/3, posted 1, empty 1; archived skipped)',
      () {
        final accounts = [
          acc('ig', target: 3),
          acc('tt', target: null, sortOrder: 1),
          acc('old', target: 1, archived: true),
        ];
        final posts = [
          post(
            '1',
            status: PostStatus.posted,
            scheduledAt: DateTime(2026, 9, 20, 10),
            postedAt: DateTime(2026, 9, 21, 10),
          ),
          post(
            '2',
            status: PostStatus.scheduled,
            scheduledAt: DateTime(2026, 9, 26, 12),
          ),
          post(
            '3',
            status: PostStatus.skipped,
            scheduledAt: DateTime(2026, 9, 23, 12),
          ),
          post(
            '4',
            status: PostStatus.scheduled,
            scheduledAt: DateTime(2026, 9, 28, 1),
          ),
          post('5', accountId: 'tt', scheduledAt: DateTime(2026, 9, 22, 12)),
        ];
        final cal = buildContentCalendar(
          DateTime(2026, 9, 21),
          DateTime(2026, 9, 27),
          posts,
          const [],
          accounts,
        );
        final slots = cal.weeks.single.accounts;
        expect(slots, hasLength(2));
        final ig = slots[0];
        expect(
          [ig.count, ig.posted, ig.target, ig.emptySlots, ig.met, ig.label],
          [2, 1, 3, 1, false, 'IG: 2/3'],
        );
        final tt = slots[1];
        expect(
          [tt.count, tt.posted, tt.target, tt.emptySlots, tt.met],
          [1, 0, null, 0, false],
        );
        expect(posts[0].calendarAt, DateTime(2026, 9, 21, 10));
        expect(posts[1].calendarAt, DateTime(2026, 9, 26, 12));
        // Days: skipped excluded, next-week post outside the range.
        expect(cal.days.keys.toSet(), {
          '2026-09-21',
          '2026-09-22',
          '2026-09-26',
        });
      },
    );
    test('consistency', () {
      final weeks = [
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 21),
      ];
      final counts = {weeks[0]: 3, weeks[1]: 1, weeks[2]: 3};
      final c = consistency(counts, 3, weeks, currentWeek: weeks[3]);
      expect(
        [c.weeksMet, c.weeks, c.longestStreak, c.currentStreak],
        [2, 4, 1, 1],
      );
      expect(consistency(counts, 3, weeks).currentStreak, 0);
      final all = {for (final w in weeks) w: 2};
      final d = consistency(all, 2, weeks, currentWeek: weeks[3]);
      expect(
        [d.weeksMet, d.weeks, d.longestStreak, d.currentStreak],
        [4, 4, 4, 4],
      );
      expect(consistency(all, null, weeks).weeksMet, 0);
    });
    test('postedPerWeek by local postedAt', () {
      final m = postedPerWeek([
        post(
          '1',
          accountId: 'a',
          status: PostStatus.posted,
          postedAt: DateTime(2026, 9, 21, 1),
        ),
        post(
          '2',
          accountId: 'a',
          status: PostStatus.posted,
          postedAt: DateTime(2026, 9, 20, 23),
        ),
        post(
          '3',
          accountId: 'a',
          status: PostStatus.scheduled,
          scheduledAt: DateTime(2026, 9, 22),
        ),
      ], 'a');
      expect(m, {DateTime(2026, 9, 21): 1, DateTime(2026, 9, 14): 1});
    });
    test('weekly targets met: week + the post that reached it', () {
      final a = acc('ig', target: 2);
      final met = weeklyTargetsMet(a, [
        post(
          '1',
          status: PostStatus.posted,
          postedAt: DateTime(2026, 9, 22, 9),
        ),
        post(
          '2',
          status: PostStatus.posted,
          postedAt: DateTime(2026, 9, 21, 9),
        ),
        post(
          '3',
          status: PostStatus.posted,
          postedAt: DateTime(2026, 9, 24, 9),
        ),
        post(
          '4',
          status: PostStatus.posted,
          postedAt: DateTime(2026, 9, 29, 9),
        ),
      ]);
      expect(met, [
        (weekStart: DateTime(2026, 9, 21), at: DateTime(2026, 9, 22, 9)),
      ]);
    });
  });

  group('metrics', () {
    test('engagement / rate', () {
      expect(
        const PostMetrics(
          likes: 10,
          comments: 2,
          shares: 3,
          saves: 5,
          views: 100,
        ).engagement,
        20,
      );
      expect(engagementRate(const PostMetrics(likes: 10, views: 100)), 0.1);
      expect(engagementRate(const PostMetrics(likes: 1)), isNull);
    });
    test('metrics prompt after 3 days without metrics', () {
      final now = DateTime.utc(2026, 9, 23);
      expect(
        needsMetricsPrompt(
          post(
            'a',
            status: PostStatus.posted,
            postedAt: DateTime.utc(2026, 9, 20),
          ),
          now,
        ),
        isTrue,
      );
      expect(
        needsMetricsPrompt(
          post(
            'a',
            status: PostStatus.posted,
            postedAt: DateTime.utc(2026, 9, 21),
          ),
          now,
        ),
        isFalse,
      );
      expect(
        needsMetricsPrompt(
          post(
            'a',
            status: PostStatus.posted,
            postedAt: DateTime.utc(2026, 9, 1),
            metricsAt: DateTime.utc(2026, 9, 5),
          ),
          now,
        ),
        isFalse,
      );
      expect(
        needsMetricsPrompt(post('a', status: PostStatus.scheduled), now),
        isFalse,
      );
    });
    test('captionWithHashtags', () {
      expect(
        ContentPost(
          id: 'x',
          contentId: 'c',
          accountId: 'a',
          caption: 'Halo\n',
          hashtags: ' #a #b ',
          createdAt: _t0,
          updatedAt: _t0,
        ).copyText,
        'Halo\n\n#a #b',
      );
      expect(
        ContentPost(
          id: 'x',
          contentId: 'c',
          accountId: 'a',
          hashtags: '#a',
          createdAt: _t0,
          updatedAt: _t0,
        ).copyText,
        '#a',
      );
    });
  });

  group('report', () {
    final accounts = [
      acc('ig', target: 2),
      acc('tt', platform: SocialPlatform.tiktok, sortOrder: 1),
    ];
    final items = [
      item(
        'i1',
        title: 'Tips A',
        pillar: 'Edukasi',
        format: ContentFormat.reel,
      ),
      item('i2', title: 'Promo B', pillar: 'Promo', format: ContentFormat.post),
      item('i3', title: 'Vlog C', format: ContentFormat.video),
    ];
    final posts = [
      post(
        'p1',
        contentId: 'i1',
        status: PostStatus.posted,
        postedAt: DateTime(2026, 9, 1, 19),
        metrics: const PostMetrics(views: 1000, likes: 100, comments: 10),
      ),
      post(
        'p2',
        contentId: 'i2',
        status: PostStatus.posted,
        postedAt: DateTime(2026, 9, 3, 19),
        metrics: const PostMetrics(views: 500, likes: 5),
      ),
      post(
        'p3',
        contentId: 'i1',
        accountId: 'tt',
        status: PostStatus.posted,
        postedAt: DateTime(2026, 9, 8, 9),
        metrics: const PostMetrics(views: 5000, likes: 50, shares: 30),
      ),
      post(
        'p4',
        contentId: 'i3',
        status: PostStatus.posted,
        postedAt: DateTime(2026, 9, 9, 19),
      ),
      post(
        'p5',
        contentId: 'i3',
        accountId: 'tt',
        status: PostStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 10, 19),
      ),
      post(
        'p6',
        contentId: 'i2',
        status: PostStatus.posted,
        postedAt: DateTime(2026, 8, 20, 19),
        metrics: const PostMetrics(views: 99999),
      ),
    ];
    final r = buildContentReport(
      from: DateTime(2026, 8, 31),
      to: DateTime(2026, 9, 13),
      now: DateTime(2026, 9, 13, 12),
      items: items,
      posts: posts,
      accounts: accounts,
    );

    test('full weeks, days, totals', () {
      expect(r.weeks, [DateTime(2026, 8, 31), DateTime(2026, 9, 7)]);
      expect(r.days, 14);
      expect(
        r.totals,
        const ContentTotals(
          posted: 4,
          scheduled: 1,
          skipped: 0,
          views: 6500,
          engagement: 195,
        ),
      );
    });
    test('IG: 3 posted of 4 expected, 1 week met, current streak 1', () {
      final ig = r.accounts.firstWhere((a) => a.account.id == 'ig');
      expect(
        [
          ig.posted,
          ig.expected,
          ig.ratio,
          ig.weeksMet,
          ig.longestStreak,
          ig.currentStreak,
        ],
        [3, 4, 0.75, 1, 1, 1],
      );
      expect(
        r.accounts.firstWhere((a) => a.account.id == 'tt').expected,
        isNull,
      );
    });
    test('best posts', () {
      expect(r.bestByViews.map((b) => b.id), ['p3', 'p1', 'p2']);
      expect(r.bestByViews.first.title, 'Tips A');
      expect(
        [for (final b in r.bestByEngagement) (b.id, b.post.metrics.engagement)],
        [('p1', 110), ('p3', 80), ('p2', 5)],
      );
    });
    test('groups', () {
      final edu = r.byPillar.firstWhere((g) => g.key == 'Edukasi');
      expect([edu.posts, edu.avgViews, edu.avgEngagement], [2, 3000, 95]);
      final none = r.byPillar.firstWhere((g) => g.key == '');
      expect(
        [none.posts, none.withMetrics, none.avgViews, none.label],
        [1, 0, null, 'Tanpa pilar'],
      );
      expect(r.byFormat.map((g) => g.key).toList()..sort(), [
        'post',
        'reel',
        'video',
      ]);
      expect(
        [for (final g in r.byWeekday) (g.key, g.posts)],
        [('2', 2), ('3', 1), ('4', 1)],
      );
      expect(r.byWeekday.first.label, 'Selasa');
      expect(
        [for (final g in r.byHour) (g.key, g.posts)],
        [('9', 1), ('19', 3)],
      );
      expect(
        r.byPillar.fold<double>(0, (s, g) => s + g.share),
        closeTo(1, 1e-9),
      );
      expect(r.byPillar.firstWhere((g) => g.key == 'Edukasi').share, 0.5);
    });
  });

  group('sponsorship', () {
    test('summary', () {
      Sponsor sp(
        String brand,
        double amount,
        String? due,
        bool paid, [
        String? tx,
      ]) => Sponsor(
        brand: brand,
        amount: amount,
        due: due,
        paid: paid,
        transactionId: tx,
      );
      final s = sponsorSummary(
        items: [
          item(
            'i1',
            title: 'Kopi',
            sponsor: sp('Kopi Kita', 1000000, '2026-09-10', true, 't1'),
          ),
          item(
            'i2',
            title: 'Sepatu',
            sponsor: sp('Lari', 500000, '2026-10-05', true),
          ),
          item(
            'i3',
            title: 'Skincare',
            sponsor: sp('Glow', 750000, '2026-09-01', false),
          ),
          item('i4', title: 'Tas', sponsor: sp('Bag', 200000, null, false)),
          item('i5', title: 'Tanpa sponsor'),
        ],
        posts: [
          post('a', contentId: 'i1', accountId: 'ig'),
          post('b', contentId: 'i1', accountId: 'tt'),
          post('c', contentId: 'i2', accountId: 'ig'),
        ],
        txDates: {'t1': DateTime(2026, 9, 1, 3)},
        now: DateTime(2026, 9, 24),
      );
      expect(s.byMonth, const [
        SponsorMonth(month: '2026-09', amount: 1000000, count: 1),
        SponsorMonth(month: '2026-10', amount: 500000, count: 1),
      ]);
      expect(s.byAccount, const [
        SponsorAccountIncome(accountId: 'ig', amount: 1000000),
        SponsorAccountIncome(accountId: 'tt', amount: 500000),
      ]);
      expect(
        [for (final u in s.unpaid) (u.item.id, u.overdue)],
        [('i3', true), ('i4', false)],
      );
      expect(sponsorTransactionNote('Kopi Kita'), 'Endorse Kopi Kita');
    });
    test('stored sponsor parsing is lenient', () {
      expect(Sponsor.tryParse('{bad'), isNull);
      expect(Sponsor.tryParse(null), isNull);
      expect(Sponsor.tryParse({'brand': 'x'}), isNull);
      expect(
        Sponsor.tryParse({
          'brand': 'B',
          'amount': 5,
          'currency': 'IDR',
          'due': null,
          'paid': true,
          'transactionId': 't',
        })!.transactionId,
        't',
      );
      expect(
        AssetLink.tryParse({'url': 'https://a.id'}),
        const AssetLink(url: 'https://a.id'),
      );
    });
  });

  group('reminders', () {
    test(
      'scheduled posts with a reminder → [IG-TAYANG], soonest first, capped',
      () {
        final now = DateTime(2026, 9, 24, 10);
        final accounts = [
          acc('ig'),
          acc('tt', platform: SocialPlatform.tiktok),
        ];
        final items = [item('c', title: 'Tips hemat')];
        final r = computeContentReminders(
          [
            ContentPost(
              id: 'a',
              contentId: 'c',
              accountId: 'tt',
              status: PostStatus.scheduled,
              scheduledAt: DateTime(2026, 9, 24, 19),
              remindBefore: 30,
              createdAt: _t0,
              updatedAt: _t0,
            ),
            ContentPost(
              id: 'b',
              contentId: 'c',
              accountId: 'ig',
              status: PostStatus.scheduled,
              scheduledAt: DateTime(2026, 9, 24, 12),
              remindBefore: 0,
              createdAt: _t0,
              updatedAt: _t0,
            ),
            // No reminder / draft / past / posted: nothing.
            ContentPost(
              id: 'c',
              contentId: 'c',
              accountId: 'ig',
              status: PostStatus.scheduled,
              scheduledAt: DateTime(2026, 9, 25),
              createdAt: _t0,
              updatedAt: _t0,
            ),
            ContentPost(
              id: 'd',
              contentId: 'c',
              accountId: 'ig',
              scheduledAt: DateTime(2026, 9, 25),
              remindBefore: 10,
              createdAt: _t0,
              updatedAt: _t0,
            ),
            ContentPost(
              id: 'e',
              contentId: 'c',
              accountId: 'ig',
              status: PostStatus.scheduled,
              scheduledAt: DateTime(2026, 9, 24, 9),
              remindBefore: 0,
              createdAt: _t0,
              updatedAt: _t0,
            ),
            ContentPost(
              id: 'f',
              contentId: 'c',
              accountId: 'ig',
              status: PostStatus.posted,
              scheduledAt: DateTime(2026, 9, 25),
              remindBefore: 10,
              createdAt: _t0,
              updatedAt: _t0,
            ),
          ],
          items,
          accounts,
          now,
        );
        expect(r.map((x) => x.key), ['content-post-b', 'content-post-a']);
        expect(r.first.title, '[IG-TAYANG] Tips hemat');
        expect(r.first.body, 'Hari ini 12.00 · @ig');
        expect(r.first.route, '/content/posts/b');
        expect(r.last.title, '[TT-TAYANG] Tips hemat');
        expect(r.last.fireAt, DateTime(2026, 9, 24, 18, 30));
      },
    );
  });

  test('idea inbox: Ide Konten notes not converted, not archived', () {
    final now = DateTime(2026, 9, 24);
    final label = NoteLabel(
      id: 'label-ide-konten-u1',
      name: 'Ide Konten',
      createdAt: now,
      updatedAt: now,
    );
    Note n(
      String id, {
      List<String> labels = const ['label-ide-konten-u1'],
      bool archived = false,
      String? linked,
    }) => Note(
      id: id,
      body: id,
      labelIds: labels,
      archived: archived,
      linkedContentId: linked,
      createdAt: now,
      updatedAt: now,
    );
    expect(
      ideaInbox(
        [
          n('a'),
          n('b', archived: true),
          n('c', linked: 'x'),
          n('d', labels: const []),
        ],
        [label],
      ).map((x) => x.id),
      ['a'],
    );
    expect(ideaInbox([n('a')], const []), isEmpty);
  });
}
