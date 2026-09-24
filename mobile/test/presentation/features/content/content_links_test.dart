import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';

import '_content_harness.dart';

void main() {
  group('Links', () {
    testWidgets('Markdown links show the real URL before opening', (
      tester,
    ) async {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(
        item(
          'a',
          'Tips hemat ngopi',
        ).copyWith(idea: '[Promo](https://evil.example/x)'),
      );
      await pumpContent(tester, h, location: '/content/a');
      await tester.ensureVisible(find.text('Pratinjau'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pratinjau'));
      await settle(tester, 3);

      await tester.tap(find.text('Promo', findRichText: true));
      await settle(tester);
      // Nothing opened yet: the sheet shows where the link really goes.
      expect(h.opened, isEmpty);
      expect(find.text('https://evil.example/x'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('link-confirm-open')));
      await settle(tester);
      expect(h.opened, ['https://evil.example/x']);
      await settleLong(tester);
    });

    testWidgets('stored non-http links are never launched', (tester) async {
      final h = ContentHarness()..seedBasics();
      h.items.s.put(
        item('a', 'Tips hemat ngopi').copyWith(
          assetLinks: const [
            AssetLink(url: 'intent://evil#Intent;end', label: 'Draft'),
          ],
        ),
      );
      await pumpContent(tester, h, location: '/content/a');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('asset-0')),
        300,
        scrollable: vertical,
      );
      await tester.tap(find.byKey(const ValueKey('asset-0')));
      await settle(tester);
      expect(h.opened, isEmpty);
      expect(find.text('Link-nya belum bisa dibuka'), findsOneWidget);
      await settleLong(tester);
    });
  });
}
