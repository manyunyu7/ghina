import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';

import '_content_harness.dart';

void main() {
  group('Posting form', () {
    ContentHarness withPost({DateTime? scheduledAt, int? remindBefore}) {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(item('a', 'Tips hemat ngopi', stage: ContentStage.siap));
      h.posts.s.put(
        post(
          'p1',
          'a',
          'ig',
          status: scheduledAt == null ? PostStatus.draft : PostStatus.scheduled,
          scheduledAt: scheduledAt,
          caption: 'Ngopi tetap jalan',
          remindBefore: remindBefore,
        ),
      );
      return h;
    }

    testWidgets('"Hapus jadwal" + Simpan leaves the form clean', (
      tester,
    ) async {
      final h = withPost(
        scheduledAt: DateTime(2026, 9, 24, 19),
        remindBefore: 30,
      );
      await pumpContent(tester, h, location: '/content/posts/p1');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('post-unschedule')),
        300,
        scrollable: vertical,
      );
      await tester.drag(vertical, const Offset(0, -200));
      await settle(tester, 3);
      await tester.tap(find.byKey(const ValueKey('post-unschedule')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('post-save')));
      await settle(tester, 20);
      final p = h.posts.s.items['p1']!;
      expect(p.scheduledAt, isNull);
      expect(p.remindBefore, isNull);
      expect(p.status, PostStatus.draft);
      // Saved: no pending "Simpan", back pops without the discard prompt.
      expect(find.byKey(const ValueKey('post-save')), findsNothing);
      await settleLong(tester);
    });

    testWidgets('hashtags with a trailing space save clean', (tester) async {
      final h = withPost();
      await pumpContent(tester, h, location: '/content/posts/p1');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('post-hashtags')),
        300,
        scrollable: vertical,
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('post-hashtags')),
          matching: find.byType(EditableText),
        ),
        '#hemat #kopi ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('post-save')));
      await settle(tester, 20);
      expect(h.posts.s.items['p1']!.hashtags, '#hemat #kopi');
      expect(find.byKey(const ValueKey('post-save')), findsNothing);
      await settleLong(tester);
    });

    testWidgets('a reminder without a date (web data) is not a change', (
      tester,
    ) async {
      final h = withPost(remindBefore: 30);
      await pumpContent(tester, h, location: '/content/posts/p1');
      expect(find.byKey(const ValueKey('post-save')), findsNothing);
    });
  });
}
