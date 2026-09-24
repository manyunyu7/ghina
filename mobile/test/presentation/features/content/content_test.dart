import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/content/content_format.dart';
import 'package:ghina/presentation/features/content/widgets/today_posts_card.dart';

import '_content_harness.dart';

void main() {
  group('Papan', () {
    testWidgets('stage chips count items; "Lanjut" moves forward with XP', (
      tester,
    ) async {
      final h = ContentHarness()..seedBasics();
      h.items.s
        ..put(item('a', 'Tips hemat ngopi', format: ContentFormat.reel))
        ..put(item('b', 'Review dompet digital', stage: ContentStage.naskah));
      await pumpContent(tester, h, location: '/content');

      expect(find.byKey(const ValueKey('stage-count-ide')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('stage-count-ide'))).data,
        '1',
      );
      expect(find.text('Tips hemat ngopi'), findsOneWidget);
      expect(find.text('Review dompet digital'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('content-advance-a')));
      await settle(tester, 20);
      expect(h.items.s.items['a']!.stage, ContentStage.naskah);
      expect(find.textContaining('+3 XP'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('stage-count-naskah')))
            .data,
        '2',
      );
      await settleLong(tester);
    });

    testWidgets('"Pindah tahap" sheet moves to any stage', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(item('a', 'Tips hemat ngopi'));
      await pumpContent(tester, h, location: '/content');

      await tester.tap(find.byKey(const ValueKey('content-menu-a')));
      await settle(tester);
      expect(find.text('Pindah tahap'), findsWidgets);
      expect(find.text('+12 XP'), findsOneWidget); // naskah+produksi+siap
      await tester.tap(find.byKey(const ValueKey('stage-pick-siap')));
      await settle(tester, 20);
      expect(h.items.s.items['a']!.stage, ContentStage.siap);
      await settleLong(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('stage-siap')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stage-siap')));
      await settle(tester);
      expect(find.text('Tips hemat ngopi'), findsOneWidget);
      await settleLong(tester);
    });

    testWidgets('filter by account keeps only its items', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.items.s
        ..put(item('a', 'Konten IG'))
        ..put(item('b', 'Konten TikTok'));
      h.posts.s
        ..put(post('pa', 'a', 'ig'))
        ..put(post('pb', 'b', 'tt'));
      await pumpContent(tester, h, location: '/content');
      expect(find.text('Konten IG'), findsOneWidget);
      expect(find.text('Konten TikTok'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-account')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pick-tt')));
      await settle(tester);
      expect(find.text('Konten IG'), findsNothing);
      expect(find.text('Konten TikTok'), findsOneWidget);
    });

    testWidgets('quick add creates an idea', (tester) async {
      final h = ContentHarness()..seedBasics();
      await pumpContent(tester, h, location: '/content');
      expect(find.text('Papan masih kosong'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('content-add')));
      await settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('quick-idea-title')),
          matching: find.byType(EditableText),
        ),
        'Challenge 30 hari nabung',
      );
      await tester.tap(find.byKey(const ValueKey('format-carousel')));
      await tester.tap(find.byKey(const ValueKey('pillar-Edukasi')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick-idea-save')));
      await settle(tester);

      final created = h.items.s.items.values.single;
      expect(created.title, 'Challenge 30 hari nabung');
      expect(created.format, ContentFormat.carousel);
      expect(created.pillar, 'Edukasi');
      expect(find.text('Challenge 30 hari nabung'), findsOneWidget);
    });

    testWidgets('seeds default pillars offline on open', (tester) async {
      final h = ContentHarness()..seed.contentSeeded = false;
      await pumpContent(tester, h, location: '/content');
      expect(h.pillars.s.items.length, 5);
    });

    testWidgets('idea inbox → "Jadikan konten"', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.labels.s.put(
        NoteLabel(
          id: 'lbl',
          name: 'Ide Konten',
          color: '#FF9600',
          createdAt: contentNow,
          updatedAt: contentNow,
        ),
      );
      h.notes.s.put(
        Note(
          id: 'n1',
          title: 'Rutinitas pagi hemat',
          body: 'Bangun, catat pengeluaran kemarin.',
          labelIds: const ['lbl'],
          createdAt: contentNow,
          updatedAt: contentNow,
        ),
      );
      await pumpContent(tester, h, location: '/content');
      await tester.tap(find.text('Ide masuk'));
      await settle(tester);
      expect(find.text('Rutinitas pagi hemat'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('convert-n1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('format-reel')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('convert-idea-save')));
      await settle(tester);

      final created = h.items.s.items.values.single;
      expect(created.noteId, 'n1');
      expect(created.format, ContentFormat.reel);
      expect(created.stage, ContentStage.ide);
      expect(find.text('Detail konten'), findsOneWidget);
    });
  });

  group('Posting', () {
    final at = DateTime(2026, 9, 24, 19);

    ContentHarness scheduled() {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(
        item('a', 'Tips hemat ngopi', stage: ContentStage.terjadwal),
      );
      h.posts.s.put(
        post(
          'p1',
          'a',
          'ig',
          status: PostStatus.scheduled,
          scheduledAt: at,
          caption: 'Ngopi tetap jalan, dompet aman ☕',
          hashtags: '#hemat #kopi',
          remindBefore: 30,
        ),
      );
      return h;
    }

    testWidgets('Salin caption copies caption + hashtags', (tester) async {
      final h = scheduled();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpContent(tester, h, location: '/content/posts/p1');
      expect(find.text('Jadwal Hari ini 19.00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('post-copy')));
      await settle(tester);
      expect(copied, 'Ngopi tetap jalan, dompet aman ☕\n\n#hemat #kopi');
      expect(find.text('Caption + hashtag disalin 📋'), findsOneWidget);
      await settleLong(tester);
    });

    testWidgets('Buka Instagram tries the app link first', (tester) async {
      final h = scheduled();
      await pumpContent(tester, h, location: '/content/posts/p1');
      expect(find.text('BUKA INSTAGRAM'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('post-open')));
      await settle(tester);
      expect(h.opened.first, 'instagram://user?username=ghina.hemat');

      h.openResult = false;
      await tester.tap(find.byKey(const ValueKey('post-open')));
      await settle(tester);
      expect(h.opened.last, 'https://www.instagram.com/ghina.hemat/');
      expect(find.textContaining('Belum bisa membuka'), findsOneWidget);
      await settleLong(tester);
    });

    testWidgets('Sudah tayang marks posted + URL and moves the item', (
      tester,
    ) async {
      final h = scheduled();
      await pumpContent(tester, h, location: '/content/posts/p1');
      await tester.tap(find.byKey(const ValueKey('post-posted')));
      await settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('posted-url')),
          matching: find.byType(EditableText),
        ),
        'https://www.instagram.com/p/abc',
      );
      await tester.tap(find.byKey(const ValueKey('posted-confirm')));
      await settle(tester, 20);

      final p = h.posts.s.items['p1']!;
      expect(p.status, PostStatus.posted);
      expect(p.url, 'https://www.instagram.com/p/abc');
      expect(h.items.s.items['a']!.stage, ContentStage.tayang);
      expect(find.textContaining('XP'), findsOneWidget);
      // Posted → metrics form + "Lihat postingan".
      expect(find.byKey(const ValueKey('post-metrics')), findsOneWidget);
      expect(find.byKey(const ValueKey('post-posted')), findsNothing);
      await settleLong(tester);
    });

    testWidgets('metrics prompt after 3 days; saving the form', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(item('a', 'Tips hemat ngopi', stage: ContentStage.tayang));
      h.posts.s.put(
        post(
          'p1',
          'a',
          'ig',
          status: PostStatus.posted,
          scheduledAt: DateTime(2026, 9, 20, 19),
          postedAt: DateTime(2026, 9, 20, 19, 5),
        ),
      );
      await pumpContent(tester, h, location: '/content/posts/p1');
      expect(find.byKey(const ValueKey('post-metrics-prompt')), findsOneWidget);

      Future<void> type(String key, String v) => tester.enterText(
        find.descendant(
          of: find.byKey(ValueKey('metric-$key')),
          matching: find.byType(EditableText),
        ),
        v,
      );
      await type('views', '1200');
      await type('likes', '85');
      await type('saves', '12');
      await tester.ensureVisible(find.byKey(const ValueKey('metrics-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('metrics-save')));
      await settle(tester);

      final m = h.posts.s.items['p1']!.metrics;
      expect(m.views, 1200);
      expect(m.likes, 85);
      expect(m.saves, 12);
      expect(m.comments, isNull);
      expect(find.byKey(const ValueKey('post-metrics-prompt')), findsNothing);
      await settleLong(tester);
    });

    testWidgets('editing the caption shows Simpan and saves', (tester) async {
      final h = scheduled();
      await pumpContent(tester, h, location: '/content/posts/p1');
      expect(find.byKey(const ValueKey('post-save')), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('post-caption')),
          matching: find.byType(EditableText),
        ),
        'Caption baru',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('post-save')));
      await settle(tester);
      expect(h.posts.s.items['p1']!.caption, 'Caption baru');
      expect(find.byKey(const ValueKey('post-save')), findsNothing);
    });
  });

  group('Kalender', () {
    testWidgets('weekly target meter and empty-slot hint', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.items.s
        ..put(item('a', 'Tips hemat', stage: ContentStage.terjadwal))
        ..put(item('b', 'Review app', stage: ContentStage.tayang));
      h.posts.s
        ..put(
          post(
            'p1',
            'a',
            'ig',
            status: PostStatus.scheduled,
            scheduledAt: DateTime(2026, 9, 25, 19),
          ),
        )
        ..put(
          post(
            'p2',
            'b',
            'ig',
            status: PostStatus.posted,
            scheduledAt: DateTime(2026, 9, 22, 19),
            postedAt: DateTime(2026, 9, 22, 19),
          ),
        );
      await pumpContent(tester, h, location: '/content');
      await tester.tap(find.text('Kalender'));
      await settle(tester);

      expect(find.text('21–27 Sep 2026'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('meter-label-ig'))).data,
        'IG 2/3',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('meter-label-tt'))).data,
        'TT 0/2',
      );
      expect(find.textContaining('Masih ada 3 slot kosong'), findsOneWidget);

      // Tap Friday → its post.
      await tester.tap(find.byKey(const ValueKey('cal-day-2026-09-25')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cal-post-p1')),
        200,
        scrollable: vertical,
      );
      expect(find.byKey(const ValueKey('cal-post-p1')), findsOneWidget);

      // Next week: empty.
      await tester.tap(find.byTooltip('Berikutnya'));
      await settle(tester);
      expect(find.text('28 Sep – 4 Okt 2026'), findsOneWidget);
    });
  });

  group('Sponsor', () {
    testWidgets('Tandai dibayar records an income transaction', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.wallets.s.put(wallet('w1', 'BCA'));
      h.items.s.put(
        item(
          'a',
          'Review kopi susu',
          stage: ContentStage.produksi,
          sponsor: const Sponsor(brand: 'Kopi Kita', amount: 750000),
        ),
      );
      await pumpContent(tester, h, location: '/content/a');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sponsor-paid')),
        300,
        scrollable: vertical,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('sponsor-paid')));
      await settle(tester);
      expect(
        find.text('Catat Endorse Kopi Kita sebagai pemasukan?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('sponsor-record')));
      await settle(tester, 5);
      await settle(tester, 15);

      final tx = h.transactions.s.items.values.single;
      expect(tx.type, TxType.income);
      expect(tx.amount, 750000);
      expect(tx.walletId, 'w1');
      expect(tx.note, 'Endorse Kopi Kita');
      final s = h.items.s.items['a']!.sponsor!;
      expect(s.paid, isTrue);
      expect(s.transactionId, tx.id);
      expect(find.textContaining('Tercatat sebagai pemasukan'), findsOneWidget);
      await settleLong(tester);

      // Reverse, deleting the income too.
      expect(find.byKey(const ValueKey('item-save')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('sponsor-unpaid')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('sponsor-unpaid')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('unpaid-delete-tx')));
      await settle(tester);
      expect(h.items.s.items['a']!.sponsor!.paid, isFalse);
      expect(h.transactions.s.items, isEmpty);
      await settleLong(tester);
    });
  });

  group('Item', () {
    testWidgets('idea preview renders Markdown safely', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(item('a', 'Tips hemat ngopi'));
      await pumpContent(tester, h, location: '/content/a');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('item-idea')),
          matching: find.byType(EditableText),
        ),
        '# Hook\n- **Kopi** sachet\n<script>x</script>',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('item-save')), findsOneWidget);
      await tester.ensureVisible(find.text('Pratinjau'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pratinjau'));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('idea-preview')), findsOneWidget);
      expect(find.text('Hook', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('item-save')));
      await settle(tester);
      expect(h.items.s.items['a']!.idea, contains('**Kopi**'));
    });
  });

  group('Laporan', () {
    testWidgets('renders accounts, best posts and pillar balance', (
      tester,
    ) async {
      final h = ContentHarness()..seedBasics();
      h.items.s
        ..put(
          item(
            'a',
            'Tips hemat ngopi',
            stage: ContentStage.tayang,
            pillar: 'Edukasi',
            format: ContentFormat.reel,
          ),
        )
        ..put(
          item(
            'b',
            'Sketsa lucu',
            stage: ContentStage.tayang,
            pillar: 'Hiburan',
            format: ContentFormat.post,
          ),
        );
      h.posts.s
        ..put(
          post(
            'p1',
            'a',
            'ig',
            status: PostStatus.posted,
            postedAt: DateTime(2026, 9, 15, 19),
            metrics: const PostMetrics(views: 5000, likes: 300),
          ),
        )
        ..put(
          post(
            'p2',
            'b',
            'ig',
            status: PostStatus.posted,
            postedAt: DateTime(2026, 9, 17, 12),
            metrics: const PostMetrics(views: 800, likes: 40),
          ),
        );
      await pumpContent(tester, h, location: '/content/report');
      expect(find.text('Laporan konten'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-account-ig')), findsOneWidget);
      // 30 days, 3/week → expected round(3 × 30 / 7) = 13.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('report-account-count-ig')))
            .data,
        '2/13',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('best-p1')),
        300,
        scrollable: vertical,
      );
      expect(find.byKey(const ValueKey('best-p2')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pillar-balance')),
        300,
        scrollable: vertical,
      );
      expect(find.text('Edukasi 50%'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('dim-weekday')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dim-weekday')));
      await settle(tester);
      expect(find.byKey(const ValueKey('avg-chart-weekday')), findsOneWidget);
    });

    testWidgets('empty range shows the empty state', (tester) async {
      final h = ContentHarness()..seedBasics();
      await pumpContent(tester, h, location: '/content/report');
      expect(find.text('Belum ada data'), findsOneWidget);
    });
  });

  group('Akun & pilar', () {
    testWidgets('adds an account with a weekly target', (tester) async {
      final h = ContentHarness();
      await pumpContent(tester, h, location: '/content/accounts');
      expect(find.text('Belum ada akun'), findsOneWidget);
      await tester.tap(find.text('TAMBAH AKUN'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('platform-tiktok')));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('account-handle')),
          matching: find.byType(EditableText),
        ),
        '@ghinahemat',
      );
      await tester.tap(find.byKey(const ValueKey('account-target-plus')));
      await tester.pump();
      expect(find.text('4 posting'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await settle(tester);

      final a = h.accounts.s.items.values.single;
      expect(a.platform, SocialPlatform.tiktok);
      expect(a.targetPerWeek, 4);
      expect(find.text('@ghinahemat'), findsOneWidget);
    });

    testWidgets('deleting a pillar warns first', (tester) async {
      final h = ContentHarness()..seedBasics();
      await pumpContent(tester, h, location: '/content/accounts');
      await tester.tap(find.text('Hiburan'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pillar-delete')));
      await settle(tester);
      expect(find.textContaining('jadi tanpa pilar'), findsOneWidget);
      await tester.tap(find.text('HAPUS'));
      await settle(tester);
      expect(h.pillars.s.items.containsKey('p2'), isFalse);
    });
  });

  group('Home card', () {
    testWidgets('Tayang hari ini lists today and hides when empty', (
      tester,
    ) async {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(
        item('a', 'Tips hemat ngopi', stage: ContentStage.terjadwal),
      );
      h.posts.s.put(
        post(
          'p1',
          'a',
          'ig',
          status: PostStatus.scheduled,
          scheduledAt: DateTime(2026, 9, 24, 19),
        ),
      );
      await pumpContent(
        tester,
        h,
        location: '/',
        home: const Scaffold(body: TodayPostsCard()),
      );
      expect(find.text('Tayang hari ini'), findsOneWidget);
      expect(find.text('1 LAGI'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-post-p1')));
      await settle(tester);
      expect(find.text('Posting'), findsOneWidget);
    });

    testWidgets('renders nothing without posts today', (tester) async {
      final h = ContentHarness()..seedBasics();
      await pumpContent(
        tester,
        h,
        location: '/',
        home: const Scaffold(body: TodayPostsCard()),
      );
      expect(find.text('Tayang hari ini'), findsNothing);
    });
  });

  group('format helpers', () {
    test('labels', () {
      final now = DateTime(2026, 9, 24, 10);
      expect(contentWhenLabel(DateTime(2026, 9, 25, 8, 5), now), 'Besok 08.05');
      expect(contentDayLabel(DateTime(2026, 9, 29), now), 'Sel 29/9');
      expect(remindLabel(null), 'Tanpa');
      expect(remindLabel(60), '1 jam');
      expect(remindLabel(1440), '1 hari');
      expect(compactCount(12345), '12,3 rb');
      expect(compactCount(1200000), '1,2 jt');
      expect(hashtagCount('#a #b c #d'), 3);
      expect(percentLabel(0.045), '4,5%');
    });

    test('moveXp counts stages not reached yet', () {
      final i = item('a', 'x', reached: {ContentStage.naskah: contentNow});
      expect(moveXp(i, ContentStage.siap), 4 + 5);
      expect(moveXp(item('b', 'y'), ContentStage.tayang), 3 + 4 + 5 + 6 + 10);
    });
  });
}
