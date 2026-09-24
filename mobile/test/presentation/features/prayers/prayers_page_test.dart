import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/prayers/pages/prayer_report_page.dart';
import 'package:ghina/presentation/features/prayers/pages/prayers_page.dart';
import 'package:go_router/go_router.dart';

import '../profile/_harness.dart';

final _routes = [
  GoRoute(path: '/prayers', builder: (_, _) => const PrayersPage()),
  GoRoute(path: '/prayers/report', builder: (_, _) => const PrayerReportPage()),
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

PrayerEntry? _row(Harness h, Prayer p, [DateTime? day]) => h
    .prayers
    .s
    .items
    .values
    .where((e) => e.prayer == p && e.date == dateKey(day ?? harnessNow))
    .firstOrNull;

void main() {
  testWidgets('shows the five fardhu and the daily sunnah of today', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    expect(find.text('Hari ini'), findsWidgets);
    for (final p in Prayer.fardhu) {
      expect(find.text(p.label), findsOneWidget);
    }
    expect(find.text('0/5 SALAT'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('sunnah-witir')));
    for (final p in Prayer.sunnah) {
      expect(find.byKey(ValueKey('sunnah-${p.wire}')), findsOneWidget);
    }
    await scrollTo(tester, find.text('Kalender'));
    expect(find.text('Kalender'), findsOneWidget);
    await drain(tester);
  });

  testWidgets(
    'tap = jamaah (+8 XP pop); tapping a filled tile opens the sheet',
    (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, location: '/prayers', routes: _routes);
      await tester.tap(find.byKey(const ValueKey('prayer-subuh')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('+8 XP'), findsWidgets);
      await settle(tester, 15);
      await _dismissRewards(tester);
      expect(_row(h, Prayer.subuh)!.status, PrayerStatus.jamaah);
      expect(find.text('1/5 SALAT'), findsOneWidget);
      expect(find.text('Jamaah'), findsWidgets);

      // Tap again → the edit sheet (never an accidental delete).
      await tester.tap(find.byKey(const ValueKey('prayer-subuh')));
      await settle(tester, 8);
      expect(find.byKey(const ValueKey('status-masjid')), findsOneWidget);
      // "Kosongkan" clears the row.
      await tester.ensureVisible(find.byKey(const ValueKey('prayer-clear')));
      await tester.tap(find.byKey(const ValueKey('prayer-clear')));
      await settle(tester, 15);
      expect(h.prayers.s.items, isEmpty);
      expect(find.text('0/5 SALAT'), findsOneWidget);
      await drain(tester);
    },
  );

  testWidgets('long-press: pick a status + rawatib in the sheet', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    await tester.longPress(find.byKey(const ValueKey('prayer-dzuhur')));
    await settle(tester, 8);
    // Only the rawatib that exist for Dzuhur are offered.
    expect(find.text('Qobliyah +2'), findsOneWidget);
    expect(find.text("Ba'diyah +2"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('status-masjid')));
    await settle(tester, 2);
    await tester.ensureVisible(find.text('Qobliyah +2'));
    await settle(tester, 2);
    await tester.tap(find.text('Qobliyah +2'));
    await settle(tester, 2);
    await tester.tap(find.text("Ba'diyah +2"));
    await settle(tester, 2);
    expect(find.text('+14 XP'), findsOneWidget);

    // Switching to missed disables and clears rawatib.
    await tester.ensureVisible(find.byKey(const ValueKey('status-missed')));
    await tester.tap(find.byKey(const ValueKey('status-missed')));
    await settle(tester, 2);
    expect(
      find.text('Rawatib bisa dicentang kalau salatnya dikerjakan.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('status-masjid')));
    await settle(tester, 2);
    await tester.ensureVisible(find.byKey(const ValueKey('prayer-save')));
    await tester.tap(find.byKey(const ValueKey('prayer-save')));
    await settle(tester, 15);
    await _dismissRewards(tester);
    final e = _row(h, Prayer.dzuhur)!;
    expect(e.status, PrayerStatus.masjid);
    expect(e.qobliyah && e.badiyah, isTrue);
    expect(find.textContaining("Qobliyah & Ba'diyah"), findsOneWidget);

    // Subuh offers only qobliyah; Ashar none.
    await tester.tap(find.byKey(const ValueKey('prayer-more-subuh')));
    await settle(tester, 8);
    expect(find.text('Qobliyah +2'), findsOneWidget);
    expect(find.text("Ba'diyah +2"), findsNothing);
    await tester.tap(find.byTooltip('Tutup'));
    await settle(tester, 8);
    await tester.tap(find.byKey(const ValueKey('prayer-more-ashar')));
    await settle(tester, 8);
    expect(find.text('RAWATIB'), findsNothing);
    await tester.tap(find.byTooltip('Tutup'));
    await settle(tester, 8);
    await drain(tester);
  });

  testWidgets('completing all five prayed celebrates the bonus', (
    tester,
  ) async {
    final h = Harness();
    h.prayers.seedStatuses(harnessNow, {
      Prayer.subuh: PrayerStatus.masjid,
      Prayer.dzuhur: PrayerStatus.late,
      Prayer.ashar: PrayerStatus.qadha,
      Prayer.maghrib: PrayerStatus.ontime,
    });
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

  testWidgets('sunnah chips toggle; rakaat stepper follows the parity rule', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/prayers', routes: _routes);
    await scrollTo(tester, find.byKey(const ValueKey('sunnah-witir')));
    await tester.tap(find.byKey(const ValueKey('sunnah-witir')));
    await settle(tester, 15);
    await _dismissRewards(tester);
    expect(_row(h, Prayer.witir)!.status, PrayerStatus.done);
    expect(_row(h, Prayer.witir)!.rakaat, isNull);

    await scrollTo(tester, find.byKey(const ValueKey('rakaat-witir')));
    await tester.tap(find.byTooltip('Tambah rakaat Witir'));
    await settle(tester, 6);
    expect(_row(h, Prayer.witir)!.rakaat, 1);
    await tester.tap(find.byTooltip('Tambah rakaat Witir'));
    await settle(tester, 6);
    expect(_row(h, Prayer.witir)!.rakaat, 3);
    expect(find.text('3 rakaat'), findsOneWidget);
    await tester.tap(find.byTooltip('Kurangi rakaat Witir'));
    await settle(tester, 6);
    await tester.tap(find.byTooltip('Kurangi rakaat Witir'));
    await settle(tester, 6);
    expect(_row(h, Prayer.witir)!.rakaat, isNull);

    await scrollTo(tester, find.byKey(const ValueKey('sunnah-witir')));
    await tester.tap(find.byKey(const ValueKey('sunnah-witir')));
    await settle(tester, 10);
    expect(_row(h, Prayer.witir), isNull);
    await drain(tester);
  });

  testWidgets('navigating to yesterday logs that day', (tester) async {
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

  group('report', () {
    Harness seeded() {
      final h = Harness();
      final y = addDays(harnessNow, -1);
      h.prayers.seedStatuses(
        y,
        {
          Prayer.subuh: PrayerStatus.late,
          Prayer.dzuhur: PrayerStatus.masjid,
          Prayer.ashar: PrayerStatus.missed,
          Prayer.maghrib: PrayerStatus.masjid,
          Prayer.isya: PrayerStatus.jamaah,
          Prayer.tahajud: PrayerStatus.done,
        },
        qobliyah: {Prayer.dzuhur},
      );
      h.prayers.seedStatuses(addDays(harnessNow, -2), {
        for (final p in Prayer.fardhu) p: PrayerStatus.masjid,
      });
      return h;
    }

    testWidgets('score, callouts and the color map; tap a cell to edit', (
      tester,
    ) async {
      final h = seeded();
      await pumpScreen(tester, h, location: '/prayers/report', routes: _routes);
      await settle(tester, 6);
      // 7 hari: 4 empty past days + today (nothing recorded) → counted =
      // 2 full days (10 slots) + 4×5 unfilled = 30 slots; points 50 + 31 = 81
      // → 81 / 300 = 27.
      expect(find.byKey(const ValueKey('report-score')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('report-score'))).data,
        '27',
      );
      await scrollTo(tester, find.byKey(const ValueKey('report-weakest')));
      expect(find.text('Perlu dikejar: Ashar'), findsOneWidget);
      expect(find.text('Paling kuat: Dzuhur'), findsOneWidget);

      final cell = find.byKey(
        ValueKey('map-${dateKey(addDays(harnessNow, -1))}-ashar'),
      );
      await scrollTo(tester, cell);
      await tester.tap(cell);
      await settle(tester, 8);
      await tester.tap(find.byKey(const ValueKey('status-qadha')));
      await tester.ensureVisible(find.byKey(const ValueKey('prayer-save')));
      await tester.tap(find.byKey(const ValueKey('prayer-save')));
      await settle(tester, 15);
      await _dismissRewards(tester);
      expect(
        _row(h, Prayer.ashar, addDays(harnessNow, -1))!.status,
        PrayerStatus.qadha,
      );
      await drain(tester);
    });

    testWidgets('range presets switch the range', (tester) async {
      final h = seeded();
      await pumpScreen(tester, h, location: '/prayers/report', routes: _routes);
      await settle(tester, 6);
      expect(find.textContaining('7 hari'), findsWidgets);
      await tester.ensureVisible(find.text('Bulan ini'));
      await tester.tap(find.text('Bulan ini'));
      await settle(tester, 6);
      final label = tester
          .widget<Text>(find.byKey(const ValueKey('report-range')))
          .data!;
      expect(label, contains('30 hari'));
      await tester.ensureVisible(find.text('Bulan lalu'));
      await tester.tap(find.text('Bulan lalu'));
      await settle(tester, 6);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('report-range'))).data,
        contains('31 hari'),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('report-score'))).data,
        '0',
      );
      await tester.ensureVisible(find.text('3 bulan'));
      await tester.tap(find.text('3 bulan'));
      await settle(tester, 6);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('report-range'))).data,
        contains('90 hari'),
      );
      await drain(tester);
    });
  });
}
