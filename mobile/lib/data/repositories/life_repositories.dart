import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/mappers.dart';
import '../models/wire.dart';
import 'local_store.dart';
import 'photo_store.dart';

class DriftPrayerRepository implements PrayerRepository {
  DriftPrayerRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<PrayerEntry>> watchRange(String fromKey, String toKey) =>
      (_db.select(_db.prayers)
            ..where((p) => p.date.isBetweenValues(fromKey, toKey))
            ..orderBy([(p) => OrderingTerm.asc(p.date)]))
          .watch()
          .map(
            (r) => r.map((x) => x.toEntity()).whereType<PrayerEntry>().toList(),
          );

  @override
  Future<PrayerEntry?> findByKey(String dateKey, Prayer prayer) async =>
      (await (_db.select(_db.prayers)..where(
                (p) => p.date.equals(dateKey) & p.prayer.equals(prayer.wire),
              ))
              .getSingleOrNull())
          ?.toEntity();

  @override
  Future<void> save(PrayerEntry entry) => _s.write(() async {
    final exists =
        await (_db.select(
          _db.prayers,
        )..where((p) => p.id.equals(entry.id))).getSingleOrNull() !=
        null;
    await _db.into(_db.prayers).insertOnConflictUpdate(entry.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.prayers,
      entityId: entry.id,
      data: prayerToWire(entry),
      clientUpdatedAt: entry.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.prayers,
    )..where((p) => p.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.prayers,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftHealthRepository implements HealthRepository {
  DriftHealthRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<HealthEntry>> watchAll({DateTime? from, DateTime? to}) {
    final q = _db.select(_db.health)
      ..orderBy([
        (h) => OrderingTerm.desc(h.date),
        (h) => OrderingTerm.desc(h.createdAt),
      ]);
    if (from != null) {
      q.where((h) => h.date.isBiggerOrEqualValue(from.millisecondsSinceEpoch));
    }
    if (to != null) {
      q.where((h) => h.date.isSmallerOrEqualValue(to.millisecondsSinceEpoch));
    }
    return q.watch().map((r) => [for (final x in r) x.toEntity()]);
  }

  @override
  Stream<HealthEntry?> watchById(String id) =>
      (_db.select(_db.health)..where((h) => h.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<HealthEntry?> getById(String id) async => (await (_db.select(
    _db.health,
  )..where((h) => h.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(HealthEntry entry) => _s.write(() async {
    final exists = await getById(entry.id) != null;
    await _db.into(_db.health).insertOnConflictUpdate(entry.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.health,
      entityId: entry.id,
      data: healthToWire(entry),
      clientUpdatedAt: entry.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.health,
    )..where((h) => h.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.health,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftFoodRepository implements FoodRepository {
  DriftFoodRepository(this._s, this._photos);
  final LocalStore _s;
  final PhotoStore _photos;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<FoodLog>> watchAll({DateTime? from, DateTime? to}) {
    final q = _db.select(_db.food)
      ..orderBy([
        (f) => OrderingTerm.desc(f.date),
        (f) => OrderingTerm.desc(f.createdAt),
      ]);
    if (from != null) {
      q.where((f) => f.date.isBiggerOrEqualValue(from.millisecondsSinceEpoch));
    }
    if (to != null) {
      q.where((f) => f.date.isSmallerOrEqualValue(to.millisecondsSinceEpoch));
    }
    return q.watch().map((r) => [for (final x in r) x.toEntity()]);
  }

  @override
  Stream<FoodLog?> watchById(String id) =>
      (_db.select(_db.food)..where((f) => f.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<FoodLog?> getById(String id) async => (await (_db.select(
    _db.food,
  )..where((f) => f.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(FoodLog log, {String? newPhotoPath}) async {
    // Copy the picked file outside the DB transaction (file IO).
    final stored = newPhotoPath == null
        ? null
        : await _photos.importPhoto(newPhotoPath, log.id);
    final old = await getById(log.id);
    final row = stored == null
        ? log
        : FoodLog(
            id: log.id,
            date: log.date,
            name: log.name,
            meal: log.meal,
            calories: log.calories,
            photoUrl: null,
            localPhotoPath: stored,
            note: log.note,
            createdAt: log.createdAt,
            updatedAt: log.updatedAt,
          );
    await _s.write(() async {
      await _db.into(_db.food).insertOnConflictUpdate(row.toCompanion());
      await _s.outbox.enqueueUpsert(
        entity: SyncEntity.food,
        entityId: row.id,
        data: foodToWire(row),
        clientUpdatedAt: row.updatedAt,
        isCreate: old == null,
      );
    });
    if (old?.localPhotoPath != null &&
        old!.localPhotoPath != row.localPhotoPath) {
      await _photos.delete(old.localPhotoPath);
    }
  }

  @override
  Future<void> delete(String id) async {
    final old = await getById(id);
    if (old == null) return;
    await _s.write(() async {
      await (_db.delete(_db.food)..where((f) => f.id.equals(id))).go();
      await _s.outbox.enqueueDelete(
        entity: SyncEntity.food,
        entityId: id,
        clientUpdatedAt: _s.clock.now(),
      );
    });
    await _photos.delete(old.localPhotoPath);
  }
}
