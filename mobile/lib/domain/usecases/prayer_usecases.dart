/// Prayer use cases (spec `docs/prayer-quality.md`). Scoring lives in
/// `prayer_quality.dart`.
library;

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'prayer_quality.dart';
import 'validation.dart';

/// Prayer entries between two local days (inclusive).
final class WatchPrayers {
  const WatchPrayers(this._repo);
  final PrayerRepository _repo;

  Stream<List<PrayerEntry>> call(DateTime from, DateTime to) =>
      _repo.watchRange(dateKey(from), dateKey(to));
}

/// `YYYY-MM-DD` → fardhu **prayed** that day (sunnah and missed/excused rows
/// are left out).
Map<String, Set<Prayer>> prayersByDate(List<PrayerEntry> entries) {
  final out = <String, Set<Prayer>>{};
  for (final e in entries) {
    if (!e.prayer.isFardhu || !e.status.isPrayed) continue;
    out.putIfAbsent(e.date, () => <Prayer>{}).add(e.prayer);
  }
  return out;
}

/// `YYYY-MM-DD` → prayer → row (every row, any status).
Map<String, Map<Prayer, PrayerEntry>> prayerEntriesByDate(
  List<PrayerEntry> entries,
) {
  final out = <String, Map<Prayer, PrayerEntry>>{};
  for (final e in entries) {
    out.putIfAbsent(e.date, () => {})[e.prayer] = e;
  }
  return out;
}

/// Shared upsert: validates, keeps id/createdAt of an existing row.
Future<PrayerEntry> _upsert(
  PrayerRepository repo,
  Clock clock,
  DateTime day,
  Prayer prayer,
  PrayerEntry Function(PrayerEntry base) change,
) async {
  final key = dateKey(day);
  final now = clock.now();
  final existing = await repo.findByKey(key, prayer);
  final base =
      existing ??
      PrayerEntry(
        id: newId(),
        date: key,
        prayer: prayer,
        status: prayer.isSunnah ? PrayerStatus.done : PrayerStatus.quick,
        createdAt: now,
        updatedAt: now,
      );
  final next = change(base).copyWith(updatedAt: now);
  validatePrayerEntry(next);
  if (existing != null && next == existing.copyWith(updatedAt: now)) {
    return existing; // nothing changed
  }
  await repo.save(next);
  return next;
}

/// Quick toggle (kept for compatibility): no row → a row with the quick status
/// (fardhu: jamaah, sunnah: done); a row → deleted. Returns true when now recorded.
final class TogglePrayer {
  const TogglePrayer(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Future<Result<bool>> call(DateTime day, Prayer prayer) => guard(() async {
    final existing = await _repo.findByKey(dateKey(day), prayer);
    if (existing != null) {
      await _repo.delete(existing.id);
      return false;
    }
    await _upsert(_repo, _clock, day, prayer, (b) => b);
    return true;
  });
}

/// Sets the status of a fardhu (tap = [PrayerStatus.quick] = jamaah). Rawatib
/// are kept while the status is a prayed one and cleared on missed/excused.
final class SetPrayerStatus {
  const SetPrayerStatus(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Future<Result<PrayerEntry>> call(
    DateTime day,
    Prayer prayer,
    PrayerStatus status,
  ) => guard(() {
    if (!prayer.isFardhu || !PrayerStatus.fardhu.contains(status)) {
      throw const ValidationFailure(
        'Status salat tidak valid',
        field: 'status',
      );
    }
    return _upsert(
      _repo,
      _clock,
      day,
      prayer,
      (b) => b.copyWith(
        status: status,
        qobliyah: status.isPrayed && b.qobliyah,
        badiyah: status.isPrayed && b.badiyah,
      ),
    );
  });
}

/// Which rawatib of a fardhu.
enum RawatibSlot {
  qobliyah('Qobliyah'),
  badiyah("Ba'diyah");

  const RawatibSlot(this.label);
  final String label;

  bool allowedFor(Prayer p) => switch (this) {
    RawatibSlot.qobliyah => p.hasQobliyah,
    RawatibSlot.badiyah => p.hasBadiyah,
  };
}

/// Ticks/unticks one rawatib of a recorded fardhu. Only where it exists and
/// only on a prayed status. Returns the new value.
final class ToggleRawatib {
  const ToggleRawatib(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Future<Result<bool>> call(DateTime day, Prayer prayer, RawatibSlot slot) =>
      guard(() async {
        if (!prayer.isFardhu || !slot.allowedFor(prayer)) {
          throw ValidationFailure(
            '${prayer.label} nggak punya ${slot.label.toLowerCase()}',
            field: 'rawatib',
          );
        }
        final existing = await _repo.findByKey(dateKey(day), prayer);
        if (existing == null || !existing.status.isPrayed) {
          throw const ValidationFailure(
            'Catat salat fardhunya dulu, ya',
            field: 'rawatib',
          );
        }
        final e = await _upsert(
          _repo,
          _clock,
          day,
          prayer,
          (b) => slot == RawatibSlot.qobliyah
              ? b.copyWith(qobliyah: !b.qobliyah)
              : b.copyWith(badiyah: !b.badiyah),
        );
        return slot == RawatibSlot.qobliyah ? e.qobliyah : e.badiyah;
      });
}

/// Marks a daily sunnah done (optionally with [rakaat]) or not done (row
/// deleted). Returns the row, or null when cleared.
final class SetSunnah {
  const SetSunnah(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Future<Result<PrayerEntry?>> call(
    DateTime day,
    Prayer prayer, {
    required bool done,
    int? rakaat,
  }) => guard(() async {
    if (!prayer.isSunnah) {
      throw const ValidationFailure(
        'Bukan salat sunnah harian',
        field: 'prayer',
      );
    }
    if (!done) {
      final existing = await _repo.findByKey(dateKey(day), prayer);
      if (existing != null) await _repo.delete(existing.id);
      return null;
    }
    return _upsert(
      _repo,
      _clock,
      day,
      prayer,
      (b) => b.copyWith(status: PrayerStatus.done, rakaat: () => rakaat),
    );
  });
}

/// Everything the edit sheet can change on a fardhu.
final class PrayerDetailsInput {
  const PrayerDetailsInput({
    required this.status,
    this.qobliyah = false,
    this.badiyah = false,
    this.prayedAt,
    this.note,
  });

  final PrayerStatus status;
  final bool qobliyah;
  final bool badiyah;
  final DateTime? prayedAt;
  final String? note;
}

/// Saves a fardhu from the edit sheet. Rawatib are dropped when the status is
/// missed/excused; rawatib that don't exist for the prayer are rejected.
final class SavePrayerDetails {
  const SavePrayerDetails(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Future<Result<PrayerEntry>> call(
    DateTime day,
    Prayer prayer,
    PrayerDetailsInput input,
  ) => guard(() {
    if (!prayer.isFardhu) {
      throw const ValidationFailure('Bukan salat fardhu', field: 'prayer');
    }
    final prayed = input.status.isPrayed;
    return _upsert(
      _repo,
      _clock,
      day,
      prayer,
      (b) => b.copyWith(
        status: input.status,
        qobliyah: prayed && input.qobliyah,
        badiyah: prayed && input.badiyah,
        prayedAt: () => input.prayedAt,
        note: () => optionalText(input.note, max: prayerNoteMax),
      ),
    );
  });
}

/// Removes the row of [prayer] on [day] ("Belum diisi" again).
final class ClearPrayer {
  const ClearPrayer(this._repo);
  final PrayerRepository _repo;

  Future<Result<void>> call(DateTime day, Prayer prayer) => guard(() async {
    final existing = await _repo.findByKey(dateKey(day), prayer);
    if (existing != null) await _repo.delete(existing.id);
  });
}

/// Report for an inclusive local-day range (clipped to today), live.
final class WatchPrayerReport {
  const WatchPrayerReport(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Stream<PrayerReport> call(DateTime from, DateTime to) => _repo
      .watchRange(dateKey(from), dateKey(to))
      .map(
        (entries) =>
            buildPrayerReport(entries, from: from, to: to, today: _clock.now()),
      );
}
