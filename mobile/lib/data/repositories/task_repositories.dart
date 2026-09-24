import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/mappers.dart';
import '../models/wire.dart';
import 'local_store.dart';

class DriftTaskAreaRepository implements TaskAreaRepository {
  DriftTaskAreaRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$TaskAreasTable, TaskAreaRow> get _all =>
      _db.select(_db.taskAreas)..orderBy([
        (a) => OrderingTerm.asc(a.sortOrder),
        (a) => OrderingTerm.asc(a.name),
      ]);

  @override
  Stream<List<TaskArea>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<TaskArea>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Stream<TaskArea?> watchById(String id) =>
      (_db.select(_db.taskAreas)..where((a) => a.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<TaskArea?> getById(String id) async => (await (_db.select(
    _db.taskAreas,
  )..where((a) => a.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(TaskArea area) => _s.write(() async {
    final exists = await getById(area.id) != null;
    await _db.into(_db.taskAreas).insertOnConflictUpdate(area.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.taskAreas,
      entityId: area.id,
      data: taskAreaToWire(area),
      clientUpdatedAt: area.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.taskAreas,
    )..where((a) => a.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.taskAreaDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.taskAreas,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftTaskRepository implements TaskRepository {
  DriftTaskRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<Task>> watchAll() => _db
      .select(_db.tasks)
      .watch()
      .map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<Task>> getAll({String? areaId}) async {
    final q = _db.select(_db.tasks);
    if (areaId != null) q.where((t) => t.areaId.equals(areaId));
    return [for (final x in await q.get()) x.toEntity()];
  }

  @override
  Stream<Task?> watchById(String id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<Task?> getById(String id) async => (await (_db.select(
    _db.tasks,
  )..where((t) => t.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(Task task) => _s.write(() async {
    final exists = await getById(task.id) != null;
    await _db.into(_db.tasks).insertOnConflictUpdate(task.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.tasks,
      entityId: task.id,
      data: taskToWire(task),
      clientUpdatedAt: task.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.taskDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.tasks,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}
