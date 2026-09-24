// Screenshots of the Konten screens for visual review:
// GHINA_SHOTS_DIR=/some/dir flutter test test/presentation/features/content/content_shots_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/content/widgets/today_posts_card.dart';

import '../../design_system/_helpers.dart';
import '_content_harness.dart';

const _key = ValueKey('shot');

ContentHarness _seeded() {
  final h = ContentHarness()..seedBasics();
  h.accounts.s.put(
    account(
      'yt',
      platform: SocialPlatform.youtube,
      handle: 'Ghina Hemat',
      target: 1,
      order: 2,
    ),
  );
  h.accounts.s.put(
    account('x', platform: SocialPlatform.x, handle: 'ghinahemat', order: 3),
  );
  h.pillars.s
    ..put(pillar('p3', 'Promo', '#FF4B4B', 2))
    ..put(pillar('p4', 'Behind the scene', '#CE82FF', 3));
  h.wallets.s.put(wallet('w1', 'BCA'));
  h.labels.s.put(
    NoteLabel(
      id: 'lbl',
      name: 'Ide Konten',
      color: '#FF9600',
      createdAt: contentNow,
      updatedAt: contentNow,
    ),
  );
  h.notes.s
    ..put(
      Note(
        id: 'n1',
        title: 'Rutinitas pagi hemat',
        body:
            'Bangun, catat pengeluaran kemarin, cek budget hari ini. Bisa jadi series 7 hari!',
        labelIds: const ['lbl'],
        createdAt: contentNow,
        updatedAt: contentNow,
      ),
    )
    ..put(
      Note(
        id: 'n2',
        body: 'Duet sama teman: tebak harga barang di minimarket 🛒',
        labelIds: const ['lbl'],
        checklist: const [ChecklistItem(id: 'x', text: 'Ajak Rani')],
        createdAt: contentNow,
        updatedAt: contentNow,
      ),
    );
  h.items.s
    ..put(
      item(
        'a',
        '5 tips hemat ngopi tiap hari',
        format: ContentFormat.reel,
        pillar: 'Edukasi',
      ),
    )
    ..put(
      item('b', 'Behind the scene bikin konten', pillar: 'Behind the scene'),
    )
    ..put(
      item(
        'c',
        'Review dompet digital terbaru',
        stage: ContentStage.naskah,
        format: ContentFormat.video,
        pillar: 'Edukasi',
        checklist: const [
          ChecklistItem(id: 'c1', text: 'Riset fitur', done: true),
          ChecklistItem(id: 'c2', text: 'Tulis naskah'),
        ],
      ),
    )
    ..put(
      item(
        'd',
        'Endorse kopi susu gula aren',
        stage: ContentStage.terjadwal,
        format: ContentFormat.carousel,
        pillar: 'Promo',
        sponsor: const Sponsor(
          brand: 'Kopi Kita',
          amount: 750000,
          due: '2026-09-30',
        ),
        checklist: const [
          ChecklistItem(id: 'd1', text: 'Foto produk', done: true),
          ChecklistItem(id: 'd2', text: 'Brief disetujui', done: true),
          ChecklistItem(id: 'd3', text: 'Edit carousel', done: true),
        ],
      ),
    )
    ..put(
      item(
        'e',
        'Challenge 30 hari nabung',
        stage: ContentStage.tayang,
        format: ContentFormat.reel,
        pillar: 'Hiburan',
      ),
    )
    ..put(
      item(
        'f',
        'Cara bikin budget bulanan',
        stage: ContentStage.tayang,
        format: ContentFormat.carousel,
        pillar: 'Edukasi',
        sponsor: const Sponsor(
          brand: 'Bank Sejahtera',
          amount: 1500000,
          paid: true,
          due: '2026-09-10',
        ),
      ),
    );
  h.posts.s
    ..put(
      post(
        'd-ig',
        'd',
        'ig',
        status: PostStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 24, 19),
        remindBefore: 30,
        caption:
            'Ngopi tiap hari tapi tetap hemat? Bisa banget! ☕\nSwipe buat lihat caraku bikin kopi susu gula aren sendiri di rumah.',
        hashtags: '#kopisusu #hemat #endorse #kopikita',
      ),
    )
    ..put(
      post(
        'd-tt',
        'd',
        'tt',
        status: PostStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 26, 12),
      ),
    )
    ..put(post('c-yt', 'c', 'yt'))
    ..put(
      post(
        'e-ig',
        'e',
        'ig',
        status: PostStatus.posted,
        scheduledAt: DateTime(2026, 9, 21, 19),
        postedAt: DateTime(2026, 9, 21, 19, 10),
      ),
    )
    ..put(
      post(
        'e-tt',
        'e',
        'tt',
        status: PostStatus.posted,
        scheduledAt: DateTime(2026, 9, 15, 19),
        postedAt: DateTime(2026, 9, 15, 20),
        metrics: const PostMetrics(
          views: 12400,
          likes: 830,
          comments: 42,
          shares: 61,
          saves: 120,
        ),
      ),
    )
    ..put(
      post(
        'f-ig',
        'f',
        'ig',
        status: PostStatus.posted,
        scheduledAt: DateTime(2026, 9, 10, 12),
        postedAt: DateTime(2026, 9, 10, 12),
        metrics: const PostMetrics(
          views: 5300,
          likes: 410,
          comments: 18,
          saves: 95,
        ),
      ),
    )
    ..put(
      post(
        'f-yt',
        'f',
        'yt',
        status: PostStatus.posted,
        scheduledAt: DateTime(2026, 9, 12, 17),
        postedAt: DateTime(2026, 9, 12, 17),
        metrics: const PostMetrics(views: 2100, likes: 150, comments: 30),
      ),
    );
  return h;
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Widget? home,
  Future<void> Function(WidgetTester t)? act,
}) async {
  await loadGhinaFonts();
  final h = _seeded();
  await pumpContent(
    tester,
    h,
    location: location,
    dark: dark,
    size: size,
    textScale: textScale,
    boundaryKey: _key,
    home: home,
  );
  if (act != null) await act(tester);
  await saveShot(tester, _key, name);
  expect(tester.takeException(), isNull);
  await settle(tester, 40);
}

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.text(label));
  await settle(t, 5);
}

Future<void> _stage(WidgetTester t, String stage) async {
  await t.ensureVisible(find.byKey(ValueKey('stage-$stage')));
  await t.pump();
  await t.tap(find.byKey(ValueKey('stage-$stage')));
  await settle(t, 4);
}

void main() {
  testWidgets('board', (t) => _shot(t, 'content_board_light', '/content'));
  testWidgets(
    'board terjadwal dark',
    (t) => _shot(
      t,
      'content_board_dark',
      '/content',
      dark: true,
      act: (t) => _stage(t, 'terjadwal'),
    ),
  );
  testWidgets(
    'board small',
    (t) => _shot(
      t,
      'content_board_small',
      '/content',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) => _stage(t, 'terjadwal'),
    ),
  );
  testWidgets(
    'calendar',
    (t) => _shot(
      t,
      'content_calendar_light',
      '/content',
      act: (t) => _tab(t, 'Kalender'),
    ),
  );
  testWidgets(
    'calendar month dark',
    (t) => _shot(
      t,
      'content_calendar_month_dark',
      '/content',
      dark: true,
      act: (t) async {
        await _tab(t, 'Kalender');
        await t.tap(find.text('Bulan'));
        await settle(t, 4);
      },
    ),
  );
  testWidgets(
    'calendar small',
    (t) => _shot(
      t,
      'content_calendar_small',
      '/content',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) => _tab(t, 'Kalender'),
    ),
  );
  testWidgets(
    'inbox',
    (t) =>
        _shot(t, 'content_inbox', '/content', act: (t) => _tab(t, 'Ide masuk')),
  );
  testWidgets(
    'quick add',
    (t) => _shot(
      t,
      'content_quick_add',
      '/content',
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('content-add')));
        await settle(t, 5);
      },
    ),
  );
  testWidgets(
    'post',
    (t) => _shot(t, 'content_post_light', '/content/posts/d-ig'),
  );
  testWidgets(
    'post dark',
    (t) => _shot(t, 'content_post_dark', '/content/posts/d-ig', dark: true),
  );
  testWidgets(
    'post small',
    (t) => _shot(
      t,
      'content_post_small',
      '/content/posts/d-ig',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'post posted metrics',
    (t) => _shot(t, 'content_post_metrics', '/content/posts/e-ig'),
  );
  testWidgets('item', (t) => _shot(t, 'content_item_light', '/content/d'));
  testWidgets(
    'item sponsor dark',
    (t) => _shot(
      t,
      'content_item_sponsor_dark',
      '/content/d',
      dark: true,
      act: (t) async {
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('sponsor-paid')),
          300,
          scrollable: vertical,
        );
        await settle(t, 3);
      },
    ),
  );
  testWidgets(
    'item small',
    (t) => _shot(
      t,
      'content_item_small',
      '/content/c',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'accounts',
    (t) => _shot(t, 'content_accounts_light', '/content/accounts'),
  );
  testWidgets(
    'account sheet dark',
    (t) => _shot(
      t,
      'content_account_sheet_dark',
      '/content/accounts',
      dark: true,
      act: (t) async {
        await t.tap(find.text('@ghina.hemat'));
        await settle(t, 5);
      },
    ),
  );
  testWidgets(
    'report',
    (t) => _shot(t, 'content_report_light', '/content/report'),
  );
  testWidgets(
    'report lower dark',
    (t) => _shot(
      t,
      'content_report_dark',
      '/content/report',
      dark: true,
      act: (t) async {
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('averages')),
          300,
          scrollable: vertical,
        );
        await t.ensureVisible(find.byKey(const ValueKey('dim-weekday')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('dim-weekday')));
        await settle(t, 3);
        await t.drag(vertical, const Offset(0, -120));
        await settle(t, 5);
      },
    ),
  );
  testWidgets(
    'report sponsors',
    (t) => _shot(
      t,
      'content_report_sponsors',
      '/content/report',
      act: (t) async {
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('report-sponsors')),
          300,
          scrollable: vertical,
        );
        await t.drag(vertical, const Offset(0, -300));
        await settle(t, 5);
      },
    ),
  );
  testWidgets(
    'report small',
    (t) => _shot(
      t,
      'content_report_small',
      '/content/report',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'today card',
    (t) => _shot(
      t,
      'content_today_card',
      '/',
      home: const Scaffold(
        body: SafeArea(
          child: Padding(padding: EdgeInsets.all(20), child: TodayPostsCard()),
        ),
      ),
    ),
  );
}
