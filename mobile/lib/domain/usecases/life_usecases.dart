/// Prayers, health and food log use cases.
library;

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

// ---------------------------------------------------------------- prayers

/// Prayer entries between two local days (inclusive).
final class WatchPrayers {
  const WatchPrayers(this._repo);
  final PrayerRepository _repo;

  Stream<List<PrayerEntry>> call(DateTime from, DateTime to) =>
      _repo.watchRange(dateKey(from), dateKey(to));
}

/// `YYYY-MM-DD` → prayers done that day.
Map<String, Set<Prayer>> prayersByDate(List<PrayerEntry> entries) {
  final out = <String, Set<Prayer>>{};
  for (final e in entries) {
    out.putIfAbsent(e.date, () => <Prayer>{}).add(e.prayer);
  }
  return out;
}

/// Toggles one prayer on [day]; returns true when it is now marked done.
final class TogglePrayer {
  const TogglePrayer(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Future<Result<bool>> call(DateTime day, Prayer prayer) => guard(() async {
    final key = dateKey(day);
    final existing = await _repo.findByKey(key, prayer);
    if (existing != null) {
      await _repo.delete(existing.id);
      return false;
    }
    final now = _clock.now();
    await _repo.save(
      PrayerEntry(
        id: newId(),
        date: key,
        prayer: prayer,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return true;
  });
}

// ---------------------------------------------------------------- health

final class HealthInput {
  const HealthInput({
    required this.date,
    this.weight,
    this.systolic,
    this.diastolic,
    this.pulse,
    this.note,
  });

  final DateTime date;
  final double? weight;
  final int? systolic;
  final int? diastolic;
  final int? pulse;
  final String? note;
}

/// Web `health/actions.ts` parse rules.
void validateHealth(HealthInput i) {
  final w = i.weight, s = i.systolic, d = i.diastolic, p = i.pulse;
  if (w != null && (!w.isFinite || w < 1 || w > 500)) {
    throw const ValidationFailure(
      'Berat badan sepertinya salah (1–500 kg)',
      field: 'weight',
    );
  }
  if (s != null && (s < 50 || s > 300)) {
    throw const ValidationFailure(
      'Sistolik sepertinya salah (50–300)',
      field: 'systolic',
    );
  }
  if (d != null && (d < 30 || d > 200)) {
    throw const ValidationFailure(
      'Diastolik sepertinya salah (30–200)',
      field: 'diastolic',
    );
  }
  if (p != null && (p < 20 || p > 250)) {
    throw const ValidationFailure(
      'Denyut nadi sepertinya salah (20–250)',
      field: 'pulse',
    );
  }
  if ((s != null) != (d != null)) {
    throw const ValidationFailure(
      'Isi sistolik dan diastolik untuk tekanan darah',
      field: 'systolic',
    );
  }
  if (w == null && s == null && p == null) {
    throw const ValidationFailure('Isi minimal satu pengukuran');
  }
}

HealthEntry _health(
  String id,
  HealthInput i,
  DateTime createdAt,
  DateTime now,
) {
  validateHealth(i);
  return HealthEntry(
    id: id,
    date: i.date,
    weight: i.weight,
    systolic: i.systolic,
    diastolic: i.diastolic,
    pulse: i.pulse,
    note: optionalText(i.note),
    createdAt: createdAt,
    updatedAt: now,
  );
}

/// Newest first; optional inclusive range.
final class WatchHealthEntries {
  const WatchHealthEntries(this._repo);
  final HealthRepository _repo;

  Stream<List<HealthEntry>> call({DateTime? from, DateTime? to}) =>
      _repo.watchAll(from: from, to: to);
}

final class WatchHealthEntry {
  const WatchHealthEntry(this._repo);
  final HealthRepository _repo;

  Stream<HealthEntry?> call(String id) => _repo.watchById(id);
}

final class CreateHealthEntry {
  const CreateHealthEntry(this._repo, this._clock);
  final HealthRepository _repo;
  final Clock _clock;

  Future<Result<HealthEntry>> call(HealthInput input) => guard(() async {
    final now = _clock.now();
    final e = _health(newId(), input, now, now);
    await _repo.save(e);
    return e;
  });
}

final class UpdateHealthEntry {
  const UpdateHealthEntry(this._repo, this._clock);
  final HealthRepository _repo;
  final Clock _clock;

  Future<Result<HealthEntry>> call(String id, HealthInput input) =>
      guard(() async {
        final old = await _repo.getById(id);
        if (old == null) throw const NotFoundFailure('Catatan tidak ditemukan');
        final e = _health(id, input, old.createdAt, _clock.now());
        await _repo.save(e);
        return e;
      });
}

final class DeleteHealthEntry {
  const DeleteHealthEntry(this._repo);
  final HealthRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

// ---------------------------------------------------------------- food

final class FoodInput {
  const FoodInput({
    required this.date,
    required this.name,
    this.meal,
    this.calories,
    this.note,
  });

  final DateTime date;
  final String name;
  final MealType? meal;
  final num? calories;
  final String? note;
}

int? _calories(num? c) {
  if (c == null) return null;
  if (!c.isFinite || c < 0 || c > 20000) {
    throw const ValidationFailure(
      'Kalori sepertinya salah (0–20000)',
      field: 'calories',
    );
  }
  return c.round();
}

/// Newest first; optional inclusive range.
final class WatchFoodLogs {
  const WatchFoodLogs(this._repo);
  final FoodRepository _repo;

  Stream<List<FoodLog>> call({DateTime? from, DateTime? to}) =>
      _repo.watchAll(from: from, to: to);
}

final class WatchFoodLog {
  const WatchFoodLog(this._repo);
  final FoodRepository _repo;

  Stream<FoodLog?> call(String id) => _repo.watchById(id);
}

/// Logs food. [photoPath] is a picked image file (compress it first, ≤ 5 MB); it is
/// kept locally and uploaded on the next sync.
final class CreateFoodLog {
  const CreateFoodLog(this._repo, this._clock);
  final FoodRepository _repo;
  final Clock _clock;

  Future<Result<FoodLog>> call(FoodInput input, {String? photoPath}) =>
      guard(() async {
        final now = _clock.now();
        final log = FoodLog(
          id: newId(),
          date: input.date,
          name: requireName(input.name, max: 120),
          meal: input.meal,
          calories: _calories(input.calories),
          note: optionalText(input.note),
          createdAt: now,
          updatedAt: now,
        );
        await _repo.save(log, newPhotoPath: photoPath);
        return log;
      });
}

/// Updates a food log. Pass [photoPath] to replace the photo, or [removePhoto].
final class UpdateFoodLog {
  const UpdateFoodLog(this._repo, this._clock);
  final FoodRepository _repo;
  final Clock _clock;

  Future<Result<FoodLog>> call(
    String id,
    FoodInput input, {
    String? photoPath,
    bool removePhoto = false,
  }) => guard(() async {
    final old = await _repo.getById(id);
    if (old == null) throw const NotFoundFailure('Catatan tidak ditemukan');
    final keepPhoto = !removePhoto && photoPath == null;
    final log = FoodLog(
      id: id,
      date: input.date,
      name: requireName(input.name, max: 120),
      meal: input.meal,
      calories: _calories(input.calories),
      photoUrl: keepPhoto ? old.photoUrl : null,
      localPhotoPath: keepPhoto ? old.localPhotoPath : null,
      note: optionalText(input.note),
      createdAt: old.createdAt,
      updatedAt: _clock.now(),
    );
    await _repo.save(log, newPhotoPath: photoPath);
    return log;
  });
}

final class DeleteFoodLog {
  const DeleteFoodLog(this._repo);
  final FoodRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}
