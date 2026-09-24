import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';

void main() {
  late InMemoryPrayerRepository repo;
  final clock = FixedClock(DateTime(2026, 9, 24, 19));
  final day = DateTime(2026, 9, 24);

  setUp(() => repo = InMemoryPrayerRepository());

  PrayerEntry? row(Prayer p) => repo.s.items.values
      .where((e) => e.prayer == p && e.date == '2026-09-24')
      .firstOrNull;

  group('SetPrayerStatus', () {
    test(
      'quick log = jamaah; changing status keeps id and createdAt',
      () async {
        final set = SetPrayerStatus(repo, FixedClock(DateTime(2026, 9, 24, 5)));
        final r = await set(day, Prayer.subuh, PrayerStatus.quick);
        final first = r.valueOrNull!;
        expect(first.status, PrayerStatus.jamaah);
        expect(first.date, '2026-09-24');

        final r2 = await SetPrayerStatus(repo, clock)(
          day,
          Prayer.subuh,
          PrayerStatus.masjid,
        );
        expect(r2.valueOrNull!.id, first.id);
        expect(r2.valueOrNull!.createdAt, first.createdAt);
        expect(r2.valueOrNull!.updatedAt, clock.now());
        expect(repo.s.items, hasLength(1));
      },
    );

    test('switching to missed / excused clears rawatib', () async {
      await SetPrayerStatus(repo, clock)(day, Prayer.dzuhur, PrayerStatus.late);
      await ToggleRawatib(repo, clock)(
        day,
        Prayer.dzuhur,
        RawatibSlot.qobliyah,
      );
      await ToggleRawatib(repo, clock)(day, Prayer.dzuhur, RawatibSlot.badiyah);
      expect(row(Prayer.dzuhur)!.rawatibCount, 2);

      await SetPrayerStatus(repo, clock)(
        day,
        Prayer.dzuhur,
        PrayerStatus.qadha,
      );
      expect(row(Prayer.dzuhur)!.rawatibCount, 2, reason: 'still prayed');

      await SetPrayerStatus(repo, clock)(
        day,
        Prayer.dzuhur,
        PrayerStatus.missed,
      );
      expect(row(Prayer.dzuhur)!.qobliyah, isFalse);
      expect(row(Prayer.dzuhur)!.badiyah, isFalse);
    });

    test('rejects sunnah prayers and the sunnah status', () async {
      final set = SetPrayerStatus(repo, clock);
      expect(
        (await set(day, Prayer.dhuha, PrayerStatus.jamaah)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await set(day, Prayer.isya, PrayerStatus.done)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(repo.s.items, isEmpty);
    });

    test('setting the same status again writes nothing', () async {
      final set = SetPrayerStatus(repo, clock);
      await set(day, Prayer.isya, PrayerStatus.ontime);
      final saves = repo.saves;
      await set(day, Prayer.isya, PrayerStatus.ontime);
      expect(repo.saves, saves);
    });
  });

  group('ToggleRawatib', () {
    test('only where allowed', () async {
      await SetPrayerStatus(repo, clock)(
        day,
        Prayer.ashar,
        PrayerStatus.jamaah,
      );
      await SetPrayerStatus(repo, clock)(
        day,
        Prayer.subuh,
        PrayerStatus.jamaah,
      );
      final toggle = ToggleRawatib(repo, clock);
      expect(
        (await toggle(day, Prayer.ashar, RawatibSlot.qobliyah)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await toggle(day, Prayer.subuh, RawatibSlot.badiyah)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await toggle(day, Prayer.subuh, RawatibSlot.qobliyah)).valueOrNull,
        isTrue,
      );
      expect(
        (await toggle(day, Prayer.subuh, RawatibSlot.qobliyah)).valueOrNull,
        isFalse,
      );
    });

    test('needs a recorded prayed status', () async {
      final toggle = ToggleRawatib(repo, clock);
      expect(
        (await toggle(day, Prayer.isya, RawatibSlot.badiyah)).failureOrNull,
        isA<ValidationFailure>(),
      );
      await SetPrayerStatus(repo, clock)(
        day,
        Prayer.isya,
        PrayerStatus.excused,
      );
      expect(
        (await toggle(day, Prayer.isya, RawatibSlot.badiyah)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(row(Prayer.isya)!.badiyah, isFalse);
    });
  });

  group('SetSunnah', () {
    test('done with valid rakaat, cleared by deleting the row', () async {
      final set = SetSunnah(repo, clock);
      final r = await set(day, Prayer.witir, done: true, rakaat: 3);
      expect(r.valueOrNull!.status, PrayerStatus.done);
      expect(r.valueOrNull!.rakaat, 3);

      // Changing rakaat keeps the row.
      final id = r.valueOrNull!.id;
      final r2 = await set(day, Prayer.witir, done: true, rakaat: 5);
      expect(r2.valueOrNull!.id, id);
      expect(row(Prayer.witir)!.rakaat, 5);

      // Rakaat optional.
      await set(day, Prayer.witir, done: true);
      expect(row(Prayer.witir)!.rakaat, isNull);

      final r3 = await set(day, Prayer.witir, done: false);
      expect(r3.valueOrNull, isNull);
      expect(row(Prayer.witir), isNull);
    });

    test('rakaat parity and range validated', () async {
      final set = SetSunnah(repo, clock);
      for (final (p, bad) in [
        (Prayer.witir, 2),
        (Prayer.witir, 13),
        (Prayer.dhuha, 3),
        (Prayer.tahajud, 14),
        (Prayer.tahajud, 0),
      ]) {
        expect(
          (await set(day, p, done: true, rakaat: bad)).failureOrNull,
          isA<ValidationFailure>(),
          reason: '${p.wire} $bad',
        );
      }
      expect(
        (await set(day, Prayer.subuh, done: true)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(repo.s.items, isEmpty);
    });
  });

  group('SavePrayerDetails', () {
    test('saves status, rawatib, time and trimmed note', () async {
      final at = DateTime(2026, 9, 24, 19, 5);
      final r = await SavePrayerDetails(repo, clock)(
        day,
        Prayer.maghrib,
        PrayerDetailsInput(
          status: PrayerStatus.masjid,
          badiyah: true,
          prayedAt: at,
          note: '  masjid kantor  ',
        ),
      );
      final e = r.valueOrNull!;
      expect(e.status, PrayerStatus.masjid);
      expect(e.badiyah, isTrue);
      expect(e.qobliyah, isFalse);
      expect(e.prayedAt, at);
      expect(e.note, 'masjid kantor');
    });

    test(
      'drops rawatib on missed/excused, rejects impossible rawatib',
      () async {
        final save = SavePrayerDetails(repo, clock);
        final r = await save(
          day,
          Prayer.subuh,
          const PrayerDetailsInput(status: PrayerStatus.missed, qobliyah: true),
        );
        expect(r.valueOrNull!.qobliyah, isFalse);
        expect(
          (await save(
            day,
            Prayer.ashar,
            const PrayerDetailsInput(
              status: PrayerStatus.jamaah,
              badiyah: true,
            ),
          )).failureOrNull,
          isA<ValidationFailure>(),
        );
        expect(
          (await save(
            day,
            Prayer.isya,
            PrayerDetailsInput(status: PrayerStatus.jamaah, note: 'x' * 501),
          )).failureOrNull,
          isA<ValidationFailure>(),
        );
      },
    );

    test(
      'ClearPrayer removes the row; TogglePrayer quick-logs jamaah',
      () async {
        final toggle = TogglePrayer(repo, clock);
        expect((await toggle(day, Prayer.isya)).valueOrNull, isTrue);
        expect(row(Prayer.isya)!.status, PrayerStatus.jamaah);
        await ClearPrayer(repo)(day, Prayer.isya);
        expect(row(Prayer.isya), isNull);
        expect((await toggle(day, Prayer.dhuha)).valueOrNull, isTrue);
        expect(row(Prayer.dhuha)!.status, PrayerStatus.done);
      },
    );
  });

  test('WatchPrayerReport streams the report for the range', () async {
    await SetPrayerStatus(repo, clock)(day, Prayer.subuh, PrayerStatus.masjid);
    await SetPrayerStatus(repo, clock)(day, Prayer.dzuhur, PrayerStatus.late);
    final r = await WatchPrayerReport(repo, clock)(
      DateTime(2026, 9, 24),
      DateTime(2026, 9, 24),
    ).first;
    expect(r.counted, 2);
    expect(r.score, 65);
  });

  test('prayersByDate only lists prayed fardhu', () {
    PrayerEntry p(Prayer pr, PrayerStatus s) => PrayerEntry(
      id: pr.wire,
      date: '2026-09-24',
      prayer: pr,
      status: s,
      createdAt: clock.now(),
      updatedAt: clock.now(),
    );
    final m = prayersByDate([
      p(Prayer.subuh, PrayerStatus.late),
      p(Prayer.isya, PrayerStatus.missed),
      p(Prayer.ashar, PrayerStatus.excused),
      p(Prayer.dhuha, PrayerStatus.done),
    ]);
    expect(m['2026-09-24'], {Prayer.subuh});
  });
}
