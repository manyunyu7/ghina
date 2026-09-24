// Upgrade safety against the REAL server: a phone on app 1.0.4 (drift schema v3:
// transactions with photos, task areas, tasks) with a realistic amount of data
// and a pending outbox is upgraded to the current app (schema v4, notes +
// content). Nothing may be lost, the old outbox must push, and the notes/content
// the web created meanwhile (which the v3 app pulled past without storing) must
// arrive through the forced full re-pull — without the device re-seeding
// defaults the user deleted on the web.
// Skipped unless GHINA_E2E_BASE_URL is set:
//   GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_upgrade_v3_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/auth_api.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart' show Json;
import 'package:ghina/data/repositories/content_repositories.dart';
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/notes_repositories.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'local/generated_migrations/schema_v3.dart' as v3;

const emailPrefix = 'mobile-test-dart-up3-';
final repoRoot = Directory.current.parent.path;

String iso(DateTime d) => d.toUtc().toIso8601String();
int ms(Object? isoString) =>
    DateTime.parse(isoString! as String).millisecondsSinceEpoch;

void main() {
  final base = Platform.environment['GHINA_E2E_BASE_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDownAll(() async {
    if (base == null) return;
    await Process.run('node', [
      'scripts/e2e-helper.mjs',
      'cleanup',
      emailPrefix,
    ], workingDirectory: repoRoot);
  });

  test(
    'v1.0.4 phone (schema v3, ~1500 tx, tasks, photos, pending outbox) upgrades to v4 and syncs',
    () async {
      final rnd = Random(11);
      final tokens = MemoryTokenStore();
      final client = ApiClient(baseUrl: base!, tokens: tokens);
      final api = DioSyncApi(client);
      final email =
          '$emailPrefix${DateTime.now().millisecondsSinceEpoch}@example.test';
      final auth = await AuthApi(client).register('Up3', email, 'rahasia123');
      await tokens.writeToken(auth.token);
      final epoch = auth.user.syncEpoch;
      final uid = auth.user.id;

      var mseq = 0;
      PushMutation up(String entity, String id, Json data) => PushMutation(
        id: 'seed-${mseq++}',
        entity: entity,
        op: MutationOp.upsert,
        entityId: id,
        data: data,
        clientUpdatedAt: DateTime.now(),
      );
      PushMutation del(String entity, String id) => PushMutation(
        id: 'seed-${mseq++}',
        entity: entity,
        op: MutationOp.delete,
        entityId: id,
        clientUpdatedAt: DateTime.now(),
      );
      Future<void> pushAll(List<PushMutation> ms) async {
        for (var i = 0; i < ms.length; i += 500) {
          final res = await api.push(
            ms.sublist(i, min(i + 500, ms.length)),
            epoch: epoch,
          );
          final bad = res.results.where((r) => r.status != PushStatus.applied);
          expect(bad, isEmpty, reason: '${bad.map((r) => r.error)}');
        }
      }

      // ---- 1. The account as the v3 app + web built it (server side).
      final start = await api.pull(0);
      final cats = start.changes[SyncEntity.categories]!;
      final expenseCats = [
        for (final c in cats)
          if (c['type'] == 'expense') c['id'] as String,
      ];
      final walletIds = ['u3-w-bca', 'u3-w-gopay', 'u3-w-tunai'];
      await pushAll([
        for (final (i, id) in walletIds.indexed)
          up(SyncEntity.wallets, id, {
            'name': ['BCA', 'GoPay', 'Tunai'][i],
            'type': ['bank', 'ewallet', 'cash'][i],
            'balance': [15000000, 500000, 750000][i],
            'currency': 'IDR',
            'color': '#22c55e',
            'icon': 'wallet',
          }),
      ]);
      final now = DateTime.now();
      await pushAll([
        for (var i = 0; i < 1500; i++)
          up(SyncEntity.transactions, 'u3-t-$i', {
            'walletId': walletIds[rnd.nextInt(3)],
            'toWalletId': null,
            'categoryId': expenseCats[i % expenseCats.length],
            'type': 'expense',
            'amount': 1000 + rnd.nextInt(200) * 500,
            'note': i % 3 == 0 ? 'Catatan $i' : null,
            'date': iso(now.subtract(Duration(hours: i * 5))),
          }),
      ]);
      final kerja = 'area-kerjaan-$uid';
      await pushAll([
        up(SyncEntity.taskAreas, 'u3-area-kuliah', {
          'name': 'Kuliah',
          'code': 'KUL',
          'color': '#123456',
          'icon': 'book-open',
          'schedule': null,
          'sortOrder': 2,
          'archived': false,
        }),
        for (var i = 0; i < 300; i++)
          up(SyncEntity.tasks, 'u3-k-$i', {
            'areaId': i % 2 == 0 ? kerja : 'u3-area-kuliah',
            'title': 'Tugas $i',
            'bucket': ['fire', 'want', 'should'][i % 3],
            'dueDate': i % 5 == 0 ? '2026-10-0${1 + i % 9}' : null,
            'done': i % 4 == 0,
            'doneAt': i % 4 == 0 ? iso(now) : null,
          }),
      ]);
      final photoFile = File(
        '${Directory.systemTemp.path}/ghina_up3_${DateTime.now().millisecondsSinceEpoch}.jpg',
      )..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0xFF, 0xD9]);
      addTearDown(() {
        if (photoFile.existsSync()) photoFile.deleteSync();
      });
      final photoUrl = await api.upload(photoFile.path);
      await pushAll([
        up(SyncEntity.transactions, 'u3-t-3', {
          'walletId': walletIds[0],
          'toWalletId': null,
          'categoryId': expenseCats.first,
          'type': 'expense',
          'amount': 12000,
          'note': 'Dengan struk',
          'date': iso(now),
          'photos': [photoUrl],
        }),
      ]);

      // The web (already on the notes/content release) used the new features;
      // the v3 app pulled past all of it without storing it.
      final labelIde = 'label-ide-konten-$uid';
      await pushAll([
        up(SyncEntity.noteLabels, 'u3-l-kerja', {
          'name': 'Kerjaan',
          'color': '#1CB0F6',
          'pinnedTab': true,
          'sortOrder': 1,
        }),
        for (var i = 0; i < 20; i++)
          up(SyncEntity.notes, 'u3-n-$i', {
            'title': 'Catatan web $i',
            'body': 'Isi $i https://contoh.example.test/$i',
            'checklist': [
              {'id': 'c$i', 'text': 'Langkah $i', 'done': i.isEven},
            ],
            'labels': [if (i % 2 == 0) labelIde else 'u3-l-kerja'],
            'color': i % 3 == 0 ? 'blue' : null,
            'pinned': i == 0,
            'archived': i == 19,
            'photos': [if (i == 1) photoUrl],
          }),
        up(SyncEntity.socialAccounts, 'u3-sa-ig', {
          'platform': 'instagram',
          'platformName': null,
          'handle': 'ghina',
          'color': '#E1306C',
          'targetPerWeek': 3,
          'archived': false,
          'sortOrder': 0,
        }),
        up(SyncEntity.contentPillars, 'u3-p-review', {
          'name': 'Review',
          'color': '#FF9600',
          'sortOrder': 9,
        }),
        for (var i = 0; i < 5; i++)
          up(SyncEntity.contentItems, 'u3-ci-$i', {
            'title': 'Konten web $i',
            'stage': ['ide', 'naskah', 'terjadwal', 'tayang', 'siap'][i],
            'pillar': i.isEven ? 'Review' : 'Edukasi',
            'noteId': i == 0 ? 'u3-n-0' : null,
            'sponsor': i == 3
                ? {'brand': 'Kopi', 'amount': 250000, 'paid': false}
                : null,
          }),
        for (var i = 2; i < 4; i++)
          up(SyncEntity.contentPosts, 'u3-cp-$i', {
            'contentId': 'u3-ci-$i',
            'accountId': 'u3-sa-ig',
            'caption': 'Caption $i',
            'status': i == 2 ? 'scheduled' : 'posted',
            'scheduledAt': iso(now.add(const Duration(days: 2))),
            'remindBefore': 60,
            'postedAt': i == 3 ? iso(now) : null,
          }),
        // The user deleted a default pillar on the web.
        del(SyncEntity.contentPillars, 'pillar-promo-$uid'),
      ]);

      // The old app's last sync happened after all of that.
      await Future<void>.delayed(const Duration(seconds: 6));
      final snap = await api.pull(0);
      expect(snap.changes[SyncEntity.transactions], hasLength(1500));
      expect(snap.changes[SyncEntity.tasks], hasLength(300));
      final serverNotes = snap.changes[SyncEntity.notes]!;
      expect(serverNotes, hasLength(20));
      final serverPillars = {
        for (final p in snap.changes[SyncEntity.contentPillars]!)
          p['id'] as String,
      };
      expect(serverPillars, hasLength(5)); // 5 defaults − Promo + Review

      // ---- 2. The v3 database file on the phone.
      final dir = await Directory.systemTemp.createTemp('ghina_upgrade_v3');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/ghina.sqlite');
      final old = v3.DatabaseAtV3(NativeDatabase(file));
      Future<void> ins(String sql, List<Object?> args) =>
          old.customStatement(sql, args);
      final pendingPhoto = File('${dir.path}/pending.jpg')
        ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0xFF, 0xD9]);
      await old.transaction(() async {
        for (final w in snap.changes[SyncEntity.wallets]!) {
          await ins(
            'INSERT INTO wallets (id, name, type, balance, currency, color, icon, archived, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              w['id'],
              w['name'],
              w['type'],
              w['balance'],
              w['currency'],
              w['color'],
              w['icon'],
              w['archived'] == true ? 1 : 0,
              ms(w['createdAt']),
              ms(w['updatedAt']),
            ],
          );
        }
        for (final c in cats) {
          await ins(
            'INSERT INTO categories (id, name, type, color, icon, created_at, updated_at) VALUES (?,?,?,?,?,?,?)',
            [
              c['id'],
              c['name'],
              c['type'],
              c['color'],
              c['icon'],
              ms(c['createdAt']),
              ms(c['updatedAt']),
            ],
          );
        }
        for (final t in snap.changes[SyncEntity.transactions]!) {
          await ins(
            'INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, photos, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            [
              t['id'],
              t['walletId'],
              t['toWalletId'],
              t['categoryId'],
              t['type'],
              t['amount'],
              t['note'],
              ms(t['date']),
              jsonEncode(t['photos'] ?? const []),
              ms(t['createdAt']),
              ms(t['updatedAt']),
            ],
          );
        }
        for (final a in snap.changes[SyncEntity.taskAreas]!) {
          await ins(
            'INSERT INTO task_areas (id, name, code, color, icon, schedule, sort_order, archived, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              a['id'],
              a['name'],
              a['code'],
              a['color'],
              a['icon'],
              a['schedule'] == null ? null : jsonEncode(a['schedule']),
              a['sortOrder'],
              a['archived'] == true ? 1 : 0,
              ms(a['createdAt']),
              ms(a['updatedAt']),
            ],
          );
        }
        for (final t in snap.changes[SyncEntity.tasks]!) {
          await ins(
            'INSERT INTO tasks (id, area_id, title, note, bucket, due_date, due_time, remind_before, recurrence, series_id, done, done_at, sort_order, amount, wallet_id, category_id, transaction_id, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              t['id'],
              t['areaId'],
              t['title'],
              t['note'],
              t['bucket'],
              t['dueDate'],
              t['dueTime'],
              t['remindBefore'],
              t['recurrence'] == null ? null : jsonEncode(t['recurrence']),
              t['seriesId'],
              t['done'] == true ? 1 : 0,
              t['doneAt'] == null ? null : ms(t['doneAt']),
              t['sortOrder'],
              t['amount'],
              t['walletId'],
              t['categoryId'],
              t['transactionId'],
              ms(t['createdAt']),
              ms(t['updatedAt']),
            ],
          );
        }
        await ins(
          'INSERT INTO sync_meta (id, cursor, epoch, user_id, last_sync_at, full_pull_required, tasks_seeded) VALUES (1,?,?,?,?,0,1)',
          [snap.serverTime, snap.epoch, uid, snap.serverTime],
        );

        // Pending offline work, exactly as the v3 app queued it.
        final at = DateTime.now().millisecondsSinceEpoch;
        Future<void> outbox(
          String entity,
          String op,
          String id,
          Object? data,
          Object? base,
          bool create,
        ) => ins(
          'INSERT INTO outbox (mutation_id, entity, op, entity_id, data, base, is_create, in_flight, client_updated_at) VALUES (?,?,?,?,?,?,?,0,?)',
          [
            'old-$entity-$op-$id',
            entity,
            op,
            id,
            data == null ? null : jsonEncode(data),
            base == null ? null : jsonEncode(base),
            create ? 1 : 0,
            at,
          ],
        );
        // (a) an expense with a photo taken offline (not uploaded yet)
        final newTx = {
          'walletId': 'u3-w-tunai',
          'toWalletId': null,
          'categoryId': expenseCats.first,
          'type': 'expense',
          'amount': 42000,
          'note': 'Offline + foto',
          'date': iso(now),
          'photos': <String>[],
        };
        await ins(
          'INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, photos, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [
            'u3-new-1',
            'u3-w-tunai',
            null,
            expenseCats.first,
            'expense',
            42000,
            'Offline + foto',
            now.millisecondsSinceEpoch,
            jsonEncode(['local:${pendingPhoto.path}']),
            at,
            at,
          ],
        );
        await outbox('transactions', 'upsert', 'u3-new-1', newTx, null, true);
        // (b) an edited task (title + done)
        final t5 = snap.changes[SyncEntity.tasks]!.firstWhere(
          (t) => t['id'] == 'u3-k-5',
        );
        await old.customStatement(
          "UPDATE tasks SET title = 'Diubah offline', done = 1, done_at = ? WHERE id = 'u3-k-5'",
          [at],
        );
        await outbox(
          'tasks',
          'upsert',
          'u3-k-5',
          {
            for (final k in [
              'areaId',
              'note',
              'bucket',
              'dueDate',
              'dueTime',
              'remindBefore',
              'recurrence',
              'seriesId',
              'sortOrder',
              'amount',
              'walletId',
              'categoryId',
              'transactionId',
            ])
              k: t5[k],
            'title': 'Diubah offline',
            'done': true,
            'doneAt': iso(DateTime.fromMillisecondsSinceEpoch(at)),
          },
          null,
          false,
        );
        // (c) a task created offline
        await ins(
          'INSERT INTO tasks (id, area_id, title, bucket, done, sort_order, created_at, updated_at) VALUES (?,?,?,?,0,0,?,?)',
          ['u3-k-new', 'u3-area-kuliah', 'Tugas offline', 'fire', at, at],
        );
        await outbox(
          'tasks',
          'upsert',
          'u3-k-new',
          {
            'areaId': 'u3-area-kuliah',
            'title': 'Tugas offline',
            'note': null,
            'bucket': 'fire',
            'dueDate': null,
            'dueTime': null,
            'remindBefore': null,
            'recurrence': null,
            'seriesId': null,
            'done': false,
            'doneAt': null,
            'sortOrder': 0,
            'amount': null,
            'walletId': null,
            'categoryId': null,
            'transactionId': null,
          },
          null,
          true,
        );
        // (d) a deleted transaction
        final t9 = snap.changes[SyncEntity.transactions]!.firstWhere(
          (t) => t['id'] == 'u3-t-9',
        );
        await old.customStatement(
          "DELETE FROM transactions WHERE id = 'u3-t-9'",
        );
        await outbox('transactions', 'delete', 'u3-t-9', null, {
          for (final k in [
            'walletId',
            'toWalletId',
            'categoryId',
            'type',
            'amount',
            'note',
            'date',
          ])
            k: t9[k],
        }, false);
      });
      final v3Counts = <String, int>{};
      for (final t in [
        'wallets',
        'categories',
        'transactions',
        'task_areas',
        'tasks',
        'outbox',
      ]) {
        v3Counts[t] =
            (await old.customSelect('SELECT COUNT(*) AS c FROM $t').getSingle())
                .read<int>('c');
      }
      expect(v3Counts['transactions'], 1500); // + new − deleted
      expect(v3Counts['tasks'], 301);
      expect(v3Counts['outbox'], 4);
      expect(
        (await old.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        3,
      );
      await old.close();

      // ---- 3. Upgrade: open with the current app database.
      final db = AppDatabase(NativeDatabase(file));
      final outbox = Outbox(db);
      for (final e in v3Counts.entries) {
        final c = await db
            .customSelect('SELECT COUNT(*) AS c FROM ${e.key}')
            .getSingle();
        expect(c.read<int>('c'), e.value, reason: e.key);
      }
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        4,
      );
      final meta0 = await db.getMeta();
      expect(meta0.fullPullRequired, isTrue);
      expect(meta0.notesSeeded || meta0.contentSeeded, isFalse);
      expect(meta0.userId, uid);

      // ---- 4. First sync of the upgraded app.
      final clock = const SystemClock();
      final store = LocalStore(db, outbox, clock);
      final photos = InMemoryPhotoStore();
      final engine = SyncEngine(
        db: db,
        outbox: outbox,
        api: api,
        photos: photos,
      );
      final sw = Stopwatch()..start();
      await engine.syncNow();
      sw.stop();
      // ignore: avoid_print
      print(
        'upgrade first sync (push 4 + upload + full pull): ${sw.elapsedMilliseconds} ms',
      );
      final meta = await db.getMeta();
      expect(meta.lastError, isNull);
      expect(await outbox.all(), isEmpty);
      expect(meta.notesSeeded && meta.contentSeeded, isTrue);
      expect(meta.fullPullRequired, isFalse);

      final after = await api.pull(0);
      final st = {
        for (final t in after.changes[SyncEntity.transactions]!)
          t['id'] as String: t,
      };
      expect(st['u3-new-1']?['amount'], 42000);
      final uploaded = (st['u3-new-1']!['photos'] as List).single as String;
      expect(uploaded, startsWith('/uploads/'));
      expect(st.containsKey('u3-t-9'), isFalse);
      expect(st['u3-t-3']?['photos'], [photoUrl]);
      final tasksAfter = {
        for (final t in after.changes[SyncEntity.tasks]!) t['id'] as String: t,
      };
      expect(tasksAfter['u3-k-5']?['title'], 'Diubah offline');
      expect(tasksAfter['u3-k-5']?['done'], isTrue);
      expect(tasksAfter['u3-k-new']?['title'], 'Tugas offline');
      expect(tasksAfter, hasLength(301));

      // Local = server, nothing lost.
      expect(await db.select(db.transactions).get(), hasLength(1500));
      expect(await db.select(db.tasks).get(), hasLength(301));
      expect(await db.select(db.taskAreas).get(), hasLength(3));
      final wallets = DriftWalletRepository(store);
      final serverBal = {
        for (final w in after.changes[SyncEntity.wallets]!)
          w['id'] as String: (w['balance'] as num).toDouble(),
      };
      for (final w in await wallets.getAll()) {
        expect(w.balance, closeTo(serverBal[w.id]!, 0.001), reason: w.id);
      }
      final localTx = (await DriftTransactionRepository(
        store,
        photos,
      ).getById('u3-new-1'))!;
      expect(localTx.photos, [TransactionPhoto.remote(uploaded)]);

      // What the v3 app never stored arrives now.
      final notes = DriftNoteRepository(store, photos);
      final labels = DriftNoteLabelRepository(store);
      final localNotes = await notes.getAll();
      expect(localNotes, hasLength(20));
      final n0 = (await notes.getById('u3-n-0'))!;
      expect(n0.pinned, isTrue);
      expect(n0.labelIds, [labelIde]);
      expect(n0.checklist.single.done, isTrue);
      expect(n0.links.single.url, 'https://contoh.example.test/0');
      expect((await notes.getById('u3-n-1'))!.photos, [
        TransactionPhoto.remote(photoUrl),
      ]);
      expect((await notes.getById('u3-n-19'))!.archived, isTrue);
      expect(
        {for (final l in await labels.getAll()) l.id},
        {labelIde, 'u3-l-kerja'},
      );
      final pillars = DriftContentPillarRepository(store);
      expect({for (final p in await pillars.getAll()) p.id}, serverPillars);
      final items = DriftContentItemRepository(store, photos);
      expect(await items.getAll(), hasLength(5));
      expect((await items.getById('u3-ci-0'))!.noteId, 'u3-n-0');
      expect((await items.getById('u3-ci-3'))!.sponsor!.brand, 'Kopi');
      expect((await items.getById('u3-ci-3'))!.stage, ContentStage.tayang);
      final posts = DriftContentPostRepository(store);
      expect(await posts.getAll(), hasLength(2));
      expect(await DriftSocialAccountRepository(store).getAll(), hasLength(1));
      // Stages from the web are kept as they were (a full pull never re-advances).
      expect((await items.getById('u3-ci-4'))!.stage, ContentStage.siap);

      // The device never seeds the deleted default pillar / a second label.
      final seedState = DriftDefaultsSeedState(db);
      expect(
        (await SeedDefaultNoteLabel(labels, seedState, clock)(
          uid,
        )).valueOrThrow,
        0,
      );
      expect(
        (await SeedDefaultContentPillars(
          pillars,
          seedState,
          DriftUnitOfWork(store),
          clock,
        )(uid)).valueOrThrow,
        0,
      );
      await engine.syncNow();
      final again = await api.pull(0);
      expect({
        for (final p in again.changes[SyncEntity.contentPillars]!)
          p['id'] as String,
      }, serverPillars);
      expect(again.changes[SyncEntity.noteLabels], hasLength(2));
      expect(again.changes[SyncEntity.taskAreas], hasLength(3));

      await engine.dispose();
      await db.close();
    },
    skip: base == null ? 'set GHINA_E2E_BASE_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
