// Mirrors the web's `scripts/test-prayer-quality.mjs` case for case, so both
// platforms agree on constants, validation, scoring, streaks and ranges.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' show XpRules;
import 'package:ghina/domain/usecases/usecases.dart';

final _t = DateTime(2026, 9, 24);
final _now = DateTime(2026, 9, 24, 12);
var _seq = 0;

PrayerEntry e(
  String date,
  String prayer,
  String status, {
  bool qobliyah = false,
  bool badiyah = false,
  int? rakaat,
}) {
  final p = Prayer.fromWire(prayer)!;
  return PrayerEntry(
    id: 'e${_seq++}',
    date: date,
    prayer: p,
    status: PrayerStatus.fromWire(status),
    qobliyah: qobliyah,
    badiyah: badiyah,
    rakaat: rakaat,
    createdAt: _now,
    updatedAt: _now,
  );
}

List<PrayerEntry> full(String date, String status) => [
  for (final p in Prayer.fardhu) e(date, p.wire, status),
];

/// Web `fields({...})` defaults: subuh jamaah on 2026-09-20.
PrayerEntry fields({
  String date = '2026-09-20',
  Prayer prayer = Prayer.subuh,
  PrayerStatus status = PrayerStatus.jamaah,
  bool qobliyah = false,
  bool badiyah = false,
  int? rakaat,
  String? note,
}) => PrayerEntry(
  id: 'x',
  date: date,
  prayer: prayer,
  status: status,
  qobliyah: qobliyah,
  badiyah: badiyah,
  rakaat: rakaat,
  note: note,
  createdAt: _now,
  updatedAt: _now,
);

DateTime d(String key) => parseDateKey(key);

PrayerReport report(List<PrayerEntry> entries, String from, String to) =>
    buildPrayerReport(entries, from: d(from), to: d(to), today: _t);

void main() {
  group('constants', () {
    test('7 statuses in spec order, points, colors', () {
      expect(PrayerStatus.fardhu.map((s) => s.wire), [
        'masjid',
        'jamaah',
        'ontime',
        'late',
        'qadha',
        'missed',
        'excused',
      ]);
      expect(PrayerStatus.fardhu.map((s) => s.points), [
        10,
        8,
        6,
        3,
        1,
        0,
        null,
      ]);
      expect(
        PrayerStatus.fardhu.map(
          (s) =>
              '#${(s.argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        ),
        [
          '#1B7A2E',
          '#58CC02',
          '#1CB0F6',
          '#FFC800',
          '#FF9600',
          '#FF4B4B',
          '#CE82FF',
        ],
      );
      expect(PrayerStatus.fardhu.map((s) => s.label), [
        'Jamaah di masjid',
        'Jamaah',
        'Sendiri, awal waktu',
        'Sendiri, telat',
        'Qadha',
        'Terlewat',
        'Berhalangan (haid/nifas)',
      ]);
      expect(PrayerStatus.emptyArgb, 0xFFE5E5E5);
      expect(PrayerStatus.emptyArgbDark, 0xFF37464F);
    });

    test('8 prayer ids, quick status, rawatib table, rakaat options', () {
      expect(Prayer.values.map((p) => p.wire), [
        'subuh',
        'dzuhur',
        'ashar',
        'maghrib',
        'isya',
        'dhuha',
        'tahajud',
        'witir',
      ]);
      expect(PrayerStatus.quick, PrayerStatus.jamaah);
      expect(
        {
          for (final p in Prayer.fardhu)
            p.wire: (q: p.hasQobliyah, b: p.hasBadiyah),
        },
        {
          'subuh': (q: true, b: false),
          'dzuhur': (q: true, b: true),
          'ashar': (q: false, b: false),
          'maghrib': (q: false, b: true),
          'isya': (q: false, b: true),
        },
      );
      expect(rakaatOptions(Prayer.witir), [1, 3, 5, 7, 9, 11]);
      expect(rakaatOptions(Prayer.dhuha), [2, 4, 6, 8, 10, 12]);
    });

    test('XP points mirror the status points', () {
      for (final s in PrayerStatus.fardhu) {
        expect(XpRules.prayerXp(s.wire), s.points ?? 0, reason: s.wire);
      }
      expect(XpRules.rawatib, 2);
      expect(XpRules.sunnah, 3);
      expect(XpRules.allPrayersBonus, 15);
    });
  });

  group('validation', () {
    bool ok(PrayerEntry x) => prayerEntryError(x) == null;

    test('mirrors the server', () {
      expect(ok(fields()), isTrue);
      expect(ok(fields(date: '2026-02-30')), isFalse);
      expect(ok(fields(status: PrayerStatus.done)), isFalse);
      expect(ok(fields(qobliyah: true)), isTrue);
      expect(ok(fields(badiyah: true)), isFalse);
      expect(ok(fields(prayer: Prayer.ashar, qobliyah: true)), isFalse);
      expect(ok(fields(prayer: Prayer.maghrib, badiyah: true)), isTrue);
      expect(ok(fields(status: PrayerStatus.missed, qobliyah: true)), isFalse);
      expect(ok(fields(status: PrayerStatus.excused, qobliyah: true)), isFalse);
      expect(ok(fields(status: PrayerStatus.qadha, qobliyah: true)), isTrue);
      expect(ok(fields(rakaat: 2)), isFalse);
      expect(
        ok(fields(prayer: Prayer.dhuha, status: PrayerStatus.done)),
        isTrue,
      );
      expect(
        ok(fields(prayer: Prayer.dhuha, status: PrayerStatus.jamaah)),
        isFalse,
      );
      expect(
        ok(
          fields(
            prayer: Prayer.tahajud,
            status: PrayerStatus.done,
            qobliyah: true,
          ),
        ),
        isFalse,
      );
      PrayerEntry sunnah(Prayer p, int r) =>
          fields(prayer: p, status: PrayerStatus.done, rakaat: r);
      expect(ok(sunnah(Prayer.dhuha, 4)), isTrue);
      expect(ok(sunnah(Prayer.dhuha, 3)), isFalse);
      expect(ok(sunnah(Prayer.dhuha, 14)), isFalse);
      expect(ok(sunnah(Prayer.witir, 3)), isTrue);
      expect(ok(sunnah(Prayer.witir, 2)), isFalse);
      expect(ok(sunnah(Prayer.witir, 13)), isFalse);
      expect(ok(fields(note: 'x' * 501)), isFalse);
      expect(ok(fields(note: 'x' * 500)), isTrue);
      expect(
        prayerEntryError(sunnah(Prayer.witir, 2)),
        'Rakaat Witir harus ganjil 1–11',
      );
    });

    test('tolerant parse: missing/unknown status → ontime (fardhu) / done', () {
      expect(PrayerStatus.forPrayer(Prayer.isya, null), PrayerStatus.ontime);
      expect(PrayerStatus.forPrayer(Prayer.isya, 'bogus'), PrayerStatus.ontime);
      expect(PrayerStatus.forPrayer(Prayer.isya, 'done'), PrayerStatus.ontime);
      expect(PrayerStatus.forPrayer(Prayer.isya, 'late'), PrayerStatus.late);
      expect(PrayerStatus.forPrayer(Prayer.witir, null), PrayerStatus.done);
      expect(PrayerStatus.forPrayer(Prayer.witir, 'late'), PrayerStatus.done);
    });
  });

  group('scoring', () {
    test('empty today → score null, nothing counted', () {
      final r = report([], '2026-09-24', '2026-09-24');
      expect(r.score, isNull);
      expect(r.counted, 0);
    });

    test('empty yesterday → 5 unfilled slots, score 0', () {
      final r = report([], '2026-09-23', '2026-09-24');
      expect(r.counted, 5);
      expect(r.unfilled, 5);
      expect(r.score, 0);
    });

    test('all masjid → 100, 1 complete day', () {
      final r = report(
        full('2026-09-23', 'masjid'),
        '2026-09-23',
        '2026-09-23',
      );
      expect(r.score, 100);
      expect(r.completeDays, 1);
    });

    test('mixed day: (10+8+6+3+0)/50 = 54, jamaah% = 40', () {
      final r = report(
        [
          e('2026-09-23', 'subuh', 'masjid'),
          e('2026-09-23', 'dzuhur', 'jamaah'),
          e('2026-09-23', 'ashar', 'ontime'),
          e('2026-09-23', 'maghrib', 'late'),
          e('2026-09-23', 'isya', 'missed'),
        ],
        '2026-09-23',
        '2026-09-23',
      );
      expect(r.score, 54);
      expect(r.points, 27);
      expect(r.completeDays, 0);
      expect(r.jamaahPct, 40);
      expect(r.pct(PrayerStatus.masjid), 20);
      expect(r.pct(PrayerStatus.missed), 20);
    });

    test('today counts only recorded slots (8/10 → 80)', () {
      final r = report(
        [e('2026-09-24', 'subuh', 'jamaah')],
        '2026-09-24',
        '2026-09-24',
      );
      expect(r.counted, 1);
      expect(r.score, 80);
    });

    test('all excused → nothing counted, neutral day', () {
      final r = report(
        full('2026-09-23', 'excused'),
        '2026-09-23',
        '2026-09-23',
      );
      expect(r.counted, 0);
      expect(r.score, isNull);
      expect(r.neutralDays, 1);
      expect(r.completeDays, 0);
      expect(r.count(PrayerStatus.excused), 5);
      expect(r.pct(PrayerStatus.excused), 0);
    });

    test('excused excluded from slots; unfilled past slots count', () {
      final r = report(
        [
          e('2026-09-23', 'subuh', 'jamaah'),
          e('2026-09-23', 'dzuhur', 'excused'),
        ],
        '2026-09-23',
        '2026-09-23',
      );
      expect(r.counted, 4);
      expect(r.points, 8);
      expect(r.score, 20);
    });

    test('future days ignored (but listed, faded)', () {
      final r = report(
        full('2026-09-25', 'masjid'),
        '2026-09-24',
        '2026-09-30',
      );
      expect(r.counted, 0);
      expect(r.daysElapsed, 1);
      expect(r.days, hasLength(7));
      expect(r.days.first.key, '2026-09-30');
      expect(r.days.first.isFuture, isTrue);
      expect(r.days.last.isToday, isTrue);
    });

    test('rawatib only on prayed rows; sunnah counts; sunnah is not a slot', () {
      final r = report(
        [
          e('2026-09-23', 'subuh', 'jamaah', qobliyah: true),
          e('2026-09-23', 'dzuhur', 'late', qobliyah: true, badiyah: true),
          // Invalid combo (never written by the app) — not counted.
          e('2026-09-23', 'maghrib', 'missed', badiyah: true),
          e('2026-09-23', 'dhuha', 'done', rakaat: 4),
          e('2026-09-22', 'dhuha', 'done'),
          e('2026-09-23', 'witir', 'done'),
        ],
        '2026-09-22',
        '2026-09-23',
      );
      expect((r.rawatibQobliyah, r.rawatibBadiyah, r.rawatibCount), (2, 1, 3));
      expect(r.sunnahCounts, {
        Prayer.dhuha: 2,
        Prayer.tahajud: 0,
        Prayer.witir: 1,
      });
      expect(r.counted, 10);
      // Color map rows: newest first; cells never show a mark on a missed row.
      expect(r.days.first.key, '2026-09-23');
      expect(r.days.first.cell(Prayer.dzuhur).badiyah, isTrue);
      expect(r.days.first.cell(Prayer.maghrib).badiyah, isFalse);
      expect(r.days.first.sunnah.keys, {Prayer.dhuha, Prayer.witir});
    });

    test('per-prayer scores, weakest and strongest', () {
      final r = report(
        [
          ...full('2026-09-22', 'masjid'),
          e('2026-09-23', 'subuh', 'late'),
          e('2026-09-23', 'dzuhur', 'masjid'),
          e('2026-09-23', 'ashar', 'missed'),
          e('2026-09-23', 'maghrib', 'masjid'),
          e('2026-09-23', 'isya', 'jamaah'),
        ],
        '2026-09-22',
        '2026-09-23',
      );
      expect(r.breakdown.map((b) => b.score), [65, 100, 50, 100, 90]);
      expect(r.weakest, Prayer.ashar);
      expect(r.strongest, Prayer.dzuhur);
    });

    test('all equal → no weakest/strongest', () {
      final r = report(
        full('2026-09-23', 'masjid'),
        '2026-09-23',
        '2026-09-23',
      );
      expect(r.weakest, isNull);
      expect(r.strongest, isNull);
    });

    test('fewer than 2 prayers with counted slots → none highlighted', () {
      final r = report(
        [e('2026-09-24', 'subuh', 'late')],
        '2026-09-24',
        '2026-09-24',
      );
      expect(r.weakest, isNull);
      expect(r.strongest, isNull);
    });

    test('percentages round to 1 decimal', () {
      // 3 days × 5 = 15 slots, 1 masjid → 6.666… → 6.7
      final r = report(
        [e('2026-09-21', 'subuh', 'masjid')],
        '2026-09-21',
        '2026-09-23',
      );
      expect(r.counted, 15);
      expect(r.pct(PrayerStatus.masjid), 6.7);
      expect(r.unfilledPct, 93.3);
    });
  });

  group('streak', () {
    final entries = [
      ...full('2026-09-20', 'jamaah'),
      ...full('2026-09-21', 'excused'), // neutral
      ...full('2026-09-22', 'qadha'),
      ...full('2026-09-23', 'late'),
      e('2026-09-24', 'subuh', 'jamaah'), // today in progress
    ];

    test('skips neutral day and incomplete today → 3', () {
      expect(completeDayStreak(entries, _t), 3);
    });

    test('complete today counts → 4', () {
      expect(
        completeDayStreak([...entries, ...full('2026-09-24', 'masjid')], _t),
        4,
      );
    });

    test('missed breaks streak', () {
      expect(
        completeDayStreak([
          ...full('2026-09-22', 'jamaah'),
          ...full('2026-09-23', 'missed'),
        ], _t),
        0,
      );
    });

    test('partial excused day with the rest prayed is neutral', () {
      final day = {
        Prayer.subuh: e('', 'subuh', 'jamaah'),
        Prayer.dzuhur: e('', 'dzuhur', 'jamaah'),
        Prayer.ashar: e('', 'ashar', 'excused'),
        Prayer.maghrib: e('', 'maghrib', 'excused'),
        Prayer.isya: e('', 'isya', 'excused'),
      };
      expect(prayerDayState(day), PrayerDayState.neutral);
      expect(prayerDayState(null), PrayerDayState.broken);
    });
  });

  group('report ranges', () {
    ({String from, String to}) keys(({DateTime from, DateTime to}) r) =>
        (from: dateKey(r.from), to: dateKey(r.to));

    test('presets', () {
      expect(keys(PrayerRangePreset.last7Days.resolve(_now)), (
        from: '2026-09-18',
        to: '2026-09-24',
      ));
      expect(keys(PrayerRangePreset.thisMonth.resolve(_now)), (
        from: '2026-09-01',
        to: '2026-09-30',
      ));
      expect(keys(PrayerRangePreset.lastMonth.resolve(_now)), (
        from: '2026-08-01',
        to: '2026-08-31',
      ));
      expect(keys(PrayerRangePreset.last3Months.resolve(_now)), (
        from: '2026-06-27',
        to: '2026-09-24',
      ));
      // January → last month is December of the previous year.
      expect(keys(PrayerRangePreset.lastMonth.resolve(DateTime(2027, 1, 5))), (
        from: '2026-12-01',
        to: '2026-12-31',
      ));
    });

    test('custom: swapped and clamped to 366 days', () {
      expect(keys(customPrayerRange(d('2026-09-10'), d('2026-09-01'))), (
        from: '2026-09-01',
        to: '2026-09-10',
      ));
      expect(
        keys(customPrayerRange(d('2000-01-01'), d('2026-09-24'))).from,
        '2025-09-24',
      );
    });
  });
}
