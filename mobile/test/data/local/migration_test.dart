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
import 'package:ghina/data/models/notes_content_mappers.dart';
import 'package:ghina/domain/entities/entities.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v1.dart' as v1;
import 'generated_migrations/schema_v2.dart' as v2;
import 'generated_migrations/schema_v3.dart' as v3;

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

  test('upgrade v1 → v3 yields exactly the v3 schema', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);
    await db.close();
  });

  test('upgrade v2 → v3 yields exactly the v3 schema', () async {
    final schema = await verifier.schemaAt(2);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);
    await db.close();
  });

  test('fresh install creates the v3 schema', () async {
    final schema = await verifier.schemaAt(3);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);
    await db.close();
  });

  for (final from in [1, 2, 3]) {
    test('upgrade v$from → v4 yields exactly the v4 schema', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);
      await db.close();
    });
  }

  test('fresh install creates the v4 schema', () async {
    final schema = await verifier.schemaAt(4);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);
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
    expect(version.read<int>('user_version'), 4);
    // v3 columns on the migrated rows.
    expect((await db.select(db.transactions).getSingle()).photos, '[]');
    await db.close();

    // 3. Re-opening a migrated database is a no-op.
    final again = AppDatabase(NativeDatabase(file));
    expect(await again.select(again.prayers).get(), hasLength(3));
    await again.close();
  });

  test('v2 data (the installed app) survives v2 → v3 on a real file', () async {
    final dir = await Directory.systemTemp.createTemp('ghina_migration_v3');
    final file = File('${dir.path}/ghina.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // 1. A v2 database like the one on the phone: every table has data, plus a
    //    pending outbox entry and sync meta.
    final old = v2.DatabaseAtV2(NativeDatabase(file));
    for (final sql in [
      "INSERT INTO wallets (id, name, type, balance, currency, color, icon, archived, created_at, updated_at) "
          "VALUES ('w1', 'Tunai', 'cash', 150000, 'IDR', '#22c55e', 'wallet', 0, 1, 1)",
      "INSERT INTO wallets (id, name, type, balance, currency, color, icon, archived, created_at, updated_at) "
          "VALUES ('w2', 'BCA', 'bank', 2000000, 'IDR', '#3b82f6', 'landmark', 0, 2, 2)",
      "INSERT INTO categories (id, name, type, color, icon, created_at, updated_at) "
          "VALUES ('c1', 'Makan', 'expense', '#ef4444', 'utensils', 1, 1)",
      "INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, created_at, updated_at) "
          "VALUES ('t1', 'w1', NULL, 'c1', 'expense', 25000, 'Nasi', 1000, 1000, 1000)",
      "INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, created_at, updated_at) "
          "VALUES ('t2', 'w2', 'w1', NULL, 'transfer', 50000, NULL, 2000, 2000, 2000)",
      "INSERT INTO transactions (id, wallet_id, type, amount, date, created_at, updated_at) "
          "VALUES ('t3', 'w1', 'adjustment', -5000, 3000, 3000, 3000)",
      "INSERT INTO budgets (id, category_id, amount, month, year, created_at, updated_at) "
          "VALUES ('b1', 'c1', 1000000, 9, 2026, 1, 1)",
      "INSERT INTO subscriptions (id, name, amount, currency, cycle, next_billing, wallet_id, color, icon, active, created_at, updated_at) "
          "VALUES ('s1', 'Netflix', 54000, 'IDR', 'monthly', 5000, 'w2', '#e50914', 'tv', 1, 1, 1)",
      "INSERT INTO planned (id, type, amount, date, done, created_at, updated_at) "
          "VALUES ('pl1', 'expense', 300000, 6000, 0, 1, 1)",
      "INSERT INTO prayers (id, date, prayer, status, qobliyah, badiyah, rakaat, prayed_at, note, created_at, updated_at) "
          "VALUES ('p1', '2026-09-20', 'subuh', 'masjid', 1, 0, NULL, 1500, 'Alhamdulillah', 1000, 2000)",
      "INSERT INTO prayers (id, date, prayer, status, qobliyah, badiyah, rakaat, created_at, updated_at) "
          "VALUES ('p2', '2026-09-20', 'witir', 'done', 0, 0, 3, 1000, 2000)",
      "INSERT INTO health (id, date, weight, systolic, diastolic, pulse, created_at, updated_at) "
          "VALUES ('h1', 1000, 70.5, 120, 80, 72, 1, 1)",
      "INSERT INTO food (id, date, name, meal, calories, photo_url, local_photo_path, created_at, updated_at) "
          "VALUES ('f1', 1000, 'Soto', 'lunch', 450, NULL, '/data/food.jpg', 1, 1)",
      "INSERT INTO outbox (mutation_id, entity, op, entity_id, data, base, is_create, in_flight, client_updated_at) "
          "VALUES ('m1', 'transactions', 'upsert', 't1', '{\"walletId\":\"w1\",\"type\":\"expense\",\"amount\":25000}', NULL, 1, 0, 2000)",
      "INSERT INTO sync_meta (id, cursor, epoch, user_id, last_sync_at, full_pull_required) "
          "VALUES (1, 1790000000000, 'epoch-1', 'u1', 1790000000001, 0)",
    ]) {
      await old.customStatement(sql);
    }
    expect(
      (await old.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      2,
    );
    await old.close();

    // 2. Open with the current app → onUpgrade(2, 4).
    final db = AppDatabase(NativeDatabase(file));
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      4,
    );
    expect(await db.select(db.wallets).get(), hasLength(2));
    expect((await db.select(db.categories).getSingle()).name, 'Makan');
    final txs = await (db.select(
      db.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(txs.map((t) => t.id), ['t1', 't2', 't3']);
    expect(txs.map((t) => t.photos), ['[]', '[]', '[]']);
    expect(txs.first.note, 'Nasi');
    expect(txs[1].toWalletId, 'w1');
    expect(txs[2].amount, -5000);
    final entities = txs.toEntities();
    expect(entities, hasLength(3));
    expect(entities.every((t) => t.photos.isEmpty), isTrue);
    expect(await db.select(db.budgets).get(), hasLength(1));
    expect((await db.select(db.subscriptions).getSingle()).walletId, 'w2');
    expect(await db.select(db.planned).get(), hasLength(1));
    final prayers = await (db.select(
      db.prayers,
    )..orderBy([(p) => OrderingTerm.asc(p.id)])).get();
    expect(prayers.first.status, 'masjid');
    expect(prayers.first.qobliyah, isTrue);
    expect(prayers.first.note, 'Alhamdulillah');
    expect(prayers.last.rakaat, 3);
    expect((await db.select(db.health).getSingle()).weight, 70.5);
    expect(
      (await db.select(db.food).getSingle()).localPhotoPath,
      '/data/food.jpg',
    );
    final outbox = await db.select(db.outbox).getSingle();
    expect(outbox.entityId, 't1');
    expect(outbox.isCreate, isTrue);
    final meta = await db.getMeta();
    expect(meta.cursor, 1790000000000);
    expect(meta.epoch, 'epoch-1');
    expect(meta.userId, 'u1');
    expect(meta.tasksSeeded, isFalse);
    // The old app pulled past tasks/photos without storing them: re-pull once.
    expect(meta.fullPullRequired, isTrue);

    // New tables exist, are empty and writable; the new column is writable.
    expect(await db.select(db.taskAreas).get(), isEmpty);
    expect(await db.select(db.tasks).get(), isEmpty);
    final now = DateTime(2026, 9, 24);
    await db
        .into(db.taskAreas)
        .insert(
          TaskArea(
            id: 'a1',
            name: 'Kerjaan',
            code: 'KERJA',
            schedule: AreaSchedule.workHours,
            createdAt: now,
            updatedAt: now,
          ).toCompanion(),
        );
    await db
        .into(db.tasks)
        .insert(
          Task(
            id: 'k1',
            areaId: 'a1',
            title: 'Kirim revisi',
            bucket: TaskBucket.fire,
            dueDate: '2026-09-24',
            dueTime: '14:00',
            remindBefore: 30,
            recurrence: const Recurrence.weekly(weekdays: [4]),
            seriesId: 'k1',
            amount: 50000,
            createdAt: now,
            updatedAt: now,
          ).toCompanion(),
        );
    final task = (await db.select(db.tasks).getSingle()).toEntity();
    expect(task.recurrence, const Recurrence.weekly(weekdays: [4]));
    expect(task.dueAt, DateTime(2026, 9, 24, 14));
    expect(
      (await db.select(db.taskAreas).getSingle()).toEntity().schedule,
      AreaSchedule.workHours,
    );
    await (db.update(db.transactions)..where((t) => t.id.equals('t1'))).write(
      const TransactionsCompanion(photos: Value('["/uploads/a.jpg"]')),
    );
    expect(
      (await (db.select(
        db.transactions,
      )..where((t) => t.id.equals('t1'))).getSingle()).toEntityOrNull()!.photos,
      [const TransactionPhoto.remote('/uploads/a.jpg')],
    );
    await db.close();

    // 3. Re-opening is a no-op and keeps everything.
    final again = AppDatabase(NativeDatabase(file));
    expect(await again.select(again.transactions).get(), hasLength(3));
    expect(await again.select(again.tasks).get(), hasLength(1));
    await again.close();
  });

  test('v3 data (the installed app) survives v3 → v4 on a real file, '
      'and forces one full re-pull', () async {
    final dir = await Directory.systemTemp.createTemp('ghina_migration_v4');
    final file = File('${dir.path}/ghina.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    // 1. A v3 database like the one on the phone: tasks, photos, pending outbox,
    //    sync meta mid-life (cursor set, tasks seeded, no full pull pending).
    final old = v3.DatabaseAtV3(NativeDatabase(file));
    for (final sql in [
      "INSERT INTO wallets (id, name, type, balance, currency, color, icon, archived, created_at, updated_at) "
          "VALUES ('w1', 'Tunai', 'cash', 150000, 'IDR', '#22c55e', 'wallet', 0, 1, 1)",
      "INSERT INTO transactions (id, wallet_id, type, amount, note, date, photos, created_at, updated_at) "
          "VALUES ('t1', 'w1', 'expense', 25000, 'Nasi', 1000, '[\"/uploads/a.jpg\",\"local:/data/b.jpg\"]', 1000, 1000)",
      "INSERT INTO task_areas (id, name, code, color, icon, schedule, sort_order, archived, created_at, updated_at) "
          "VALUES ('area-kerjaan-u1', 'Kerjaan', 'KERJA', '#1CB0F6', 'briefcase', '{\"days\":[1,2,3,4,5],\"start\":\"09:00\",\"end\":\"17:00\"}', 0, 0, 1, 1)",
      "INSERT INTO tasks (id, area_id, title, bucket, due_date, due_time, remind_before, done, sort_order, created_at, updated_at) "
          "VALUES ('k1', 'area-kerjaan-u1', 'Kirim revisi', 'fire', '2026-09-25', '14:00', 30, 0, 0, 1, 1)",
      "INSERT INTO outbox (mutation_id, entity, op, entity_id, data, base, is_create, in_flight, client_updated_at) "
          "VALUES ('m1', 'tasks', 'upsert', 'k1', '{\"areaId\":\"area-kerjaan-u1\",\"title\":\"Kirim revisi\"}', NULL, 1, 0, 2000)",
      "INSERT INTO sync_meta (id, cursor, epoch, user_id, last_sync_at, full_pull_required, tasks_seeded) "
          "VALUES (1, 1790000000000, 'epoch-1', 'u1', 1790000000001, 0, 1)",
    ]) {
      await old.customStatement(sql);
    }
    expect(
      (await old.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      3,
    );
    await old.close();

    // 2. Open with the current app → onUpgrade(3, 4).
    final db = AppDatabase(NativeDatabase(file));
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      4,
    );
    expect((await db.select(db.wallets).getSingle()).balance, 150000);
    final tx = (await db.select(db.transactions).getSingle()).toEntityOrNull()!;
    expect(tx.photos, [
      const TransactionPhoto.remote('/uploads/a.jpg'),
      const TransactionPhoto.local('/data/b.jpg'),
    ]);
    final task = (await db.select(db.tasks).getSingle()).toEntity();
    expect(task.dueAt, DateTime(2026, 9, 25, 14));
    expect(
      (await db.select(db.taskAreas).getSingle()).toEntity().schedule,
      AreaSchedule.workHours,
    );
    final outbox = await db.select(db.outbox).getSingle();
    expect(outbox.entityId, 'k1');
    final meta = await db.getMeta();
    expect(meta.cursor, 1790000000000);
    expect(meta.epoch, 'epoch-1');
    expect(meta.userId, 'u1');
    expect(meta.tasksSeeded, isTrue);
    expect(meta.notesSeeded, isFalse);
    expect(meta.contentSeeded, isFalse);
    // The v3 app pulled past notes/content from the web without storing them:
    // re-download everything once (pending outbox rows still win).
    expect(meta.fullPullRequired, isTrue);

    // New tables exist, are empty and writable.
    for (final t in <TableInfo<Table, dynamic>>[
      db.notes,
      db.noteLabels,
      db.socialAccounts,
      db.contentItems,
      db.contentPosts,
      db.contentPillars,
    ]) {
      expect(await db.select(t).get(), isEmpty);
    }
    final now = DateTime(2026, 9, 24, 10);
    await db
        .into(db.notes)
        .insert(
          Note(
            id: 'n1',
            title: 'Ide video',
            body: 'Cek https://x.id',
            checklist: const [ChecklistItem(id: 'c1', text: 'Rekam')],
            labelIds: const ['label-ide-konten-u1'],
            color: 'yellow',
            audio: const [
              NoteAudio.local(
                '/data/rec.m4a',
                durationSec: 12,
                transcript: 'halo',
              ),
            ],
            createdAt: now,
            updatedAt: now,
          ).toCompanion(),
        );
    final n = (await db.select(db.notes).getSingle());
    expect(n.searchText, contains('halo'));
    expect(n.toEntity().audio.single.isPending, isTrue);
    await db
        .into(db.contentItems)
        .insert(
          ContentItem(
            id: 'i1',
            title: 'Review',
            stage: ContentStage.siap,
            sponsor: const Sponsor(brand: 'Kopi', amount: 0),
            stageReachedAt: {ContentStage.siap: now},
            createdAt: now,
            updatedAt: now,
          ).toCompanion(),
        );
    final item = (await db.select(db.contentItems).getSingle()).toEntity();
    expect(item.stage, ContentStage.siap);
    expect(item.sponsor!.amount, 0);
    expect(item.stageReachedAt[ContentStage.siap], now);
    await db.close();

    // 3. Re-opening is a no-op and keeps everything.
    final again = AppDatabase(NativeDatabase(file));
    expect(await again.select(again.notes).get(), hasLength(1));
    expect(await again.select(again.tasks).get(), hasLength(1));
    expect((await again.getMeta()).fullPullRequired, isTrue);
    await again.close();
  });
}
