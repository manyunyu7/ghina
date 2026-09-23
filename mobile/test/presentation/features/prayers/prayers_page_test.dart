import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/prayers/pages/prayers_page.dart';
import 'package:go_router/go_router.dart';

import '../profile/_harness.dart';

final _routes = [
  GoRoute(path: '/prayers', builder: (_, _) => const PrayersPage()),
];

Future<void> _dismissRewards(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    final btn = find.text('LANJUT').evaluate().isNotEmpty
        ? find.text('LANJUT')
        : find.text('MANTAP!');
    if (btn.evaluate().isEmpty) return;
    await tester.tap(btn.last);
    await settle(tester, 8);
  }
}

void main() {
  testWidgets('shows the five prayers of today', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    expect(find.text('Hari ini'), findsWidgets);
    for (final p in Prayer.values) {
      expect(find.text(p.label), findsOneWidget);
    }
    expect(find.text('0/5 SALAT'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Kalender'), 300);
    expect(find.text('Kalender'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('tapping a tile marks it done, tapping again undoes it', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    await tester.tap(find.byKey(const ValueKey('prayer-subuh')));
    await settle(tester, 15);
    await _dismissRewards(tester);
    expect(h.prayers.s.items.values.single.prayer, Prayer.subuh);
    expect(h.prayers.s.items.values.single.date, dateKey(harnessNow));
    expect(find.text('1/5 SALAT'), findsOneWidget);
    expect(find.text('Sudah, alhamdulillah'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prayer-subuh')));
    await settle(tester, 15);
    expect(h.prayers.s.items, isEmpty);
    expect(find.text('0/5 SALAT'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('completing all five celebrates the bonus', (tester) async {
    final h = Harness();
    h.prayers.seed(harnessNow, [
      Prayer.subuh,
      Prayer.dzuhur,
      Prayer.ashar,
      Prayer.maghrib,
    ]);
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    expect(find.text('4/5 SALAT'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prayer-isya')));
    await settle(tester, 15);
    expect(find.text('Lima waktu lengkap! 🕌'), findsOneWidget);
    await _dismissRewards(tester);
    expect(h.prayers.s.items, hasLength(5));
    expect(find.text('LENGKAP 5/5'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('navigating to yesterday toggles that day', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    await tester.tap(find.byTooltip('Hari sebelumnya'));
    await settle(tester, 5);
    expect(find.text('Kemarin'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prayer-maghrib')));
    await settle(tester, 15);
    await _dismissRewards(tester);
    expect(
      h.prayers.s.items.values.single.date,
      dateKey(addDays(harnessNow, -1)),
    );
    await drain(tester);
  });

  testWidgets('pull to refresh syncs', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1200);
    await settle(tester, 20);
    expect(h.sync.syncs, 1);
    await drain(tester);
  });
}
