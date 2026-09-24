import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    Budgets,
    Subscriptions,
    Planned,
    Prayers,
    Health,
    Food,
    Outbox,
    SyncMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-device database (`ghina.sqlite` in the app documents directory).
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'ghina'));

  /// In-memory database for tests.
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  /// v1: initial schema. v2: prayer quality columns on `prayers`.
  ///
  /// Bumping? Add a step below, run
  /// `dart run drift_dev schema dump lib/data/datasources/local/app_database.dart drift_schemas/`
  /// and `dart run drift_dev schema generate drift_schemas/ test/data/local/generated_migrations/`,
  /// then extend `test/data/local/migration_test.dart`.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Existing rows mean "performed" → status defaults to 'ontime'.
        await m.addColumn(prayers, prayers.status);
        await m.addColumn(prayers, prayers.qobliyah);
        await m.addColumn(prayers, prayers.badiyah);
        await m.addColumn(prayers, prayers.rakaat);
        await m.addColumn(prayers, prayers.prayedAt);
        await m.addColumn(prayers, prayers.note);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = OFF');
    },
  );

  /// The 9 synced tables.
  List<TableInfo<Table, dynamic>> get syncedTables => [
    wallets,
    categories,
    transactions,
    budgets,
    subscriptions,
    planned,
    prayers,
    health,
    food,
  ];

  /// Deletes all synced rows and the outbox. With [includeMeta] the sync meta
  /// (cursor, epoch, owner) is reset too.
  Future<void> wipe({bool includeMeta = false}) => transaction(() async {
    for (final t in syncedTables) {
      await delete(t).go();
    }
    await delete(outbox).go();
    if (includeMeta) await delete(syncMeta).go();
  });

  // ---------------------------------------------------------------- meta

  Future<SyncMetaRow> getMeta() async {
    final row = await (select(
      syncMeta,
    )..where((m) => m.id.equals(1))).getSingleOrNull();
    if (row != null) return row;
    await into(syncMeta).insert(
      const SyncMetaCompanion(id: Value(1)),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(syncMeta)..where((m) => m.id.equals(1))).getSingle();
  }

  Stream<SyncMetaRow?> watchMeta() =>
      (select(syncMeta)..where((m) => m.id.equals(1))).watchSingleOrNull();

  Future<void> updateMeta(SyncMetaCompanion patch) async {
    await getMeta();
    await (update(syncMeta)..where((m) => m.id.equals(1))).write(patch);
  }

  // ---------------------------------------------------------------- reactive helper

  /// Emits `load()` now and again whenever any of [tables] changes. Reloads are
  /// coalesced (at most one pending reload while a load runs).
  Stream<T> watchTables<T>(
    Iterable<ResultSetImplementation<dynamic, dynamic>> tables,
    Future<T> Function() load,
  ) {
    late StreamController<T> controller;
    StreamSubscription<Set<TableUpdate>>? sub;
    var loading = false;
    var dirty = false;
    var cancelled = false;

    Future<void> run() async {
      if (loading) {
        dirty = true;
        return;
      }
      loading = true;
      do {
        dirty = false;
        try {
          final v = await load();
          if (!cancelled) controller.add(v);
        } catch (e, st) {
          if (!cancelled) controller.addError(e, st);
        }
      } while (dirty && !cancelled);
      loading = false;
    }

    controller = StreamController<T>(
      onListen: () {
        sub = tableUpdates(
          TableUpdateQuery.allOf([
            for (final t in tables) TableUpdateQuery.onTable(t),
          ]),
        ).listen((_) => run());
        run();
      },
      onCancel: () async {
        cancelled = true;
        await sub?.cancel();
      },
    );
    return controller.stream;
  }
}
