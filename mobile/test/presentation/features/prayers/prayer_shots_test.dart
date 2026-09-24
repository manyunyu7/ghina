/// Prayer quality screens (tiles, edit sheet, report, color map) at 390×844
/// light + dark and 360×640 at 1.3× text. Always asserts no layout exceptions;
/// set GHINA_SHOTS_DIR to also write PNGs:
///   GHINA_SHOTS_DIR=/tmp/shots flutter test test/presentation/features/prayers/prayer_shots_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/prayers/pages/prayer_report_page.dart';
import 'package:ghina/presentation/features/prayers/pages/prayers_page.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/_helpers.dart';
import '../profile/_harness.dart';

final _routes = <RouteBase>[
  GoRoute(path: '/prayers', builder: (_, _) => const PrayersPage()),
  GoRoute(
    path: '/prayers/report',
    builder: (_, _) => const PrayerReportPage(),
  ),
];

/// A realistic, colourful fortnight.
Harness _seeded() {
  final h = Harness();
  const s = PrayerStatus.values;
  for (var i = 0; i < 16; i++) {
    final d = addDays(harnessNow, -i);
    if (i == 0) {
      h.prayers.seedStatuses(
        d,
        {
          Prayer.subuh: PrayerStatus.masjid,
          Prayer.dzuhur: PrayerStatus.late,
          Prayer.dhuha: PrayerStatus.done,
        },
        qobliyah: {Prayer.subuh},
      );
      continue;
    }
    if (i == 6 || i == 7) {
      h.prayers.seedStatuses(d, {
        for (final p in Prayer.fardhu) p: PrayerStatus.excused,
      });
      continue;
    }
    if (i == 11) continue; // a blank day
    h.prayers.seedStatuses(
      d,
      {
        Prayer.subuh: s[(i * 3) % 5],
        Prayer.dzuhur: s[(i + 1) % 3],
        Prayer.ashar: i % 4 == 0 ? PrayerStatus.missed : s[(i + 2) % 4],
        Prayer.maghrib: i.isEven ? PrayerStatus.masjid : PrayerStatus.jamaah,
        Prayer.isya: i % 5 == 0 ? PrayerStatus.qadha : PrayerStatus.masjid,
        if (i % 3 == 0) Prayer.tahajud: PrayerStatus.done,
        if (i.isEven) Prayer.witir: PrayerStatus.done,
        if (i % 4 == 1) Prayer.dhuha: PrayerStatus.done,
      },
      qobliyah: {if (i.isOdd) Prayer.subuh, Prayer.dzuhur},
      badiyah: {Prayer.maghrib, if (i % 3 != 1) Prayer.isya},
    );
  }
  return h;
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Future<void> Function()? then,
}) async {
  const key = ValueKey('shot');
  await pumpScreen(
    tester,
    _seeded(),
    location: location,
    routes: _routes,
    dark: dark,
    size: size,
    textScale: textScale,
    boundaryKey: key,
  );
  await settle(tester, 6);
  if (then != null) await then();
  await settle(tester, 10);
  expect(tester.takeException(), isNull);
  await saveShot(tester, key, name, pixelRatio: 2);
  await drain(tester);
}

void main() {
  setUpAll(loadGhinaFonts);

  final screens = <(String, String, Future<void> Function(WidgetTester)?)>[
    ('prayerq_tiles', '/prayers', null),
    (
      'prayerq_sunnah',
      '/prayers',
      (t) async {
        await scrollTo(t, find.byKey(const ValueKey('prayer-report-card')));
      },
    ),
    (
      'prayerq_sheet',
      '/prayers',
      (t) async {
        await t.longPress(find.byKey(const ValueKey('prayer-dzuhur')));
        await settle(t, 8);
      },
    ),
    ('prayerq_report', '/prayers/report', null),
    (
      'prayerq_report_bars',
      '/prayers/report',
      (t) async {
        await scrollTo(t, find.byKey(const ValueKey('report-sunnah')));
      },
    ),
    (
      'prayerq_colormap',
      '/prayers/report',
      (t) async {
        await t.ensureVisible(find.text('Bulan ini'));
        await t.tap(find.text('Bulan ini'));
        await settle(t, 6);
        await scrollTo(
          t,
          find.byKey(
            ValueKey(
              'map-${dateKey(addDays(harnessNow, -8))}-isya',
            ),
          ),
          delta: 400,
        );
      },
    ),
  ];

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final (name, loc, then) in screens) {
      testWidgets('$name renders ($mode)', (tester) async {
        await _shot(
          tester,
          '${name}_$mode',
          loc,
          dark: dark,
          then: then == null ? null : () => then(tester),
        );
      });
    }
  }

  for (final (name, loc, then) in screens) {
    testWidgets('$name fits 360×640 at 1.3× text', (tester) async {
      await _shot(
        tester,
        '${name}_small',
        loc,
        size: const Size(360, 640),
        textScale: 1.3,
        then: then == null ? null : () => then(tester),
      );
    });
  }
}
