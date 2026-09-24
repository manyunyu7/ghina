// Schema migrations of the on-device database.
//
// The app is installed on real phones with v1 data, so every upgrade path is
// tested against the exact old schema (snapshots in `drift_schemas/`,
// helpers generated into `generated_migrations/` by
// `dart run drift_dev schema generate drift_schemas/ test/data/local/generated_migrations/`).
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/models/mappers.dart';
import 'package:ghina/domain/entities/entities.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v1.dart' as v1;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('upgrade v1 → v2 yields exactly the v2 schema', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    await db.close();
  });

  test('fresh install creates the v2 schema', () async {
    final schema = await verifier.schemaAt(2);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    await db.close();
  });

  test('v1 data survives on a real database file: prayers become ontime', () async {
    final dir = await Directory.systemTemp.createTemp('ghina_migration');
    final file = File('${dir.path}/ghina.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // 1. Build a v1 database file like the one on the phone.
    final old = v1.DatabaseAtV1(NativeDatabase(file));
    await old.customStatement(
      "INSERT INTO wallets (id, name, type, balance, currency, color, icon, archived, created_at, updated_at) "
      "VALUES ('w1', 'Tunai', 'cash', 150000, 'IDR', '#22c55e', 'wallet', 0, 1, 1)",
    );
    await old.customStatement(
      "INSERT INTO transactions (id, wallet_id, type, amount, date, created_at, updated_at) "
      "VALUES ('t1', 'w1', 'expense', 25000, 1000, 1000, 1000)",
    );
    for (final (id, prayer) in [
      ('p1', 'subuh'),
      ('p2', 'dzuhur'),
      ('p3', 'isya'),
    ]) {
      await old.customStatement(
        "INSERT INTO prayers (id, date, prayer, created_at, updated_at) "
        "VALUES ('$id', '2026-09-20', '$prayer', 1000, 2000)",
      );
    }
    await old.customStatement(
      "INSERT INTO outbox (mutation_id, entity, op, entity_id, data, is_create, in_flight, client_updated_at) "
      "VALUES ('m1', 'prayers', 'upsert', 'p3', '{\"date\":\"2026-09-20\",\"prayer\":\"isya\"}', 1, 0, 2000)",
    );
    final v1Version = await old.customSelect('PRAGMA user_version').getSingle();
    expect(v1Version.read<int>('user_version'), 1);
    await old.close();

    // 2. Open it with the current app database → onUpgrade(1, 2).
    final db = AppDatabase(NativeDatabase(file));
    final rows = await (db.select(
      db.prayers,
    )..orderBy([(p) => OrderingTerm.asc(p.id)])).get();
    expect(rows.map((r) => r.id), ['p1', 'p2', 'p3']);
    for (final r in rows) {
      expect(r.status, 'ontime');
      expect(r.qobliyah, isFalse);
      expect(r.badiyah, isFalse);
      expect(r.rakaat, isNull);
      expect(r.prayedAt, isNull);
      expect(r.note, isNull);
      expect(r.createdAt, DateTime.fromMillisecondsSinceEpoch(1000));
    }
    final entity = rows.first.toEntity()!;
    expect(entity.prayer, Prayer.subuh);
    expect(entity.status, PrayerStatus.ontime);
    expect(entity.isPrayed, isTrue);

    // Other tables and the pending outbox are untouched.
    final wallet = await db.select(db.wallets).getSingle();
    expect(wallet.balance, 150000);
    expect(await db.select(db.transactions).get(), hasLength(1));
    expect((await db.select(db.outbox).getSingle()).entityId, 'p3');

    // The new columns are writable and unique (date, prayer) still holds.
    await (db.update(db.prayers)..where((p) => p.id.equals('p1'))).write(
      const PrayersCompanion(status: Value('masjid'), qobliyah: Value(true)),
    );
    final p1 = await (db.select(
      db.prayers,
    )..where((p) => p.id.equals('p1'))).getSingle();
    expect(p1.status, 'masjid');
    expect(p1.qobliyah, isTrue);
    await expectLater(
      db.customStatement(
        "INSERT INTO prayers (id, date, prayer, created_at, updated_at) "
        "VALUES ('dup', '2026-09-20', 'subuh', 1, 1)",
      ),
      throwsA(anything),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 2);
    await db.close();

    // 3. Re-opening a migrated database is a no-op.
    final again = AppDatabase(NativeDatabase(file));
    expect(await again.select(again.prayers).get(), hasLength(3));
    await again.close();
  });
}
