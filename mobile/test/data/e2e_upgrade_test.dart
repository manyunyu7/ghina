// Upgrade safety against the REAL server: a phone on app v1.0.3 (drift schema v2)
// with a realistic amount of data and a pending outbox is upgraded to the current
// app (schema v3). Nothing may be lost, the old outbox must push, and everything
// the old app could not store (task areas/tasks, transaction photos) must arrive.
// Skipped unless GHINA_E2E_BASE_URL is set:
//   GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_upgrade_test.dart
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
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';

import 'local/generated_migrations/schema_v2.dart' as v2;

const emailPrefix = 'mobile-test-dart-up-';
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
    'v1.0.3 phone (schema v2, ~1500 tx, pending outbox) upgrades and syncs',
    () async {
      final rnd = Random(7);
      final tokens = MemoryTokenStore();
      final client = ApiClient(baseUrl: base!, tokens: tokens);
      final api = DioSyncApi(client);
      final email =
          '$emailPrefix${DateTime.now().millisecondsSinceEpoch}@example.test';
      final auth = await AuthApi(
        client,
      ).register('Upgrade', email, 'rahasia123');
      await tokens.writeToken(auth.token);
      final epoch = auth.user.syncEpoch;

      var mseq = 0;
      PushMutation up(String entity, String id, Json data, [DateTime? at]) =>
          PushMutation(
            id: 'seed-${mseq++}',
            entity: entity,
            op: MutationOp.upsert,
            entityId: id,
            data: data,
            clientUpdatedAt: at ?? DateTime.now(),
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

      // ---- 1. The account as the old app built it (server side).
      final start = await api.pull(0);
      final cats = start.changes[SyncEntity.categories]!;
      final expenseCats = [
        for (final c in cats)
          if (c['type'] == 'expense') c['id'] as String,
      ];
      final incomeCats = [
        for (final c in cats)
          if (c['type'] == 'income') c['id'] as String,
      ];
      final walletIds = ['up-w-bca', 'up-w-gopay', 'up-w-tunai'];
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
      final txs = <PushMutation>[];
      for (var i = 0; i < 1500; i++) {
        final kind = i % 20 == 0
            ? 'income'
            : i % 25 == 1
            ? 'transfer'
            : 'expense';
        final w = walletIds[rnd.nextInt(3)];
        txs.add(
          up(SyncEntity.transactions, 'up-t-$i', {
            'walletId': w,
            'toWalletId': kind == 'transfer'
                ? walletIds.firstWhere((x) => x != w)
                : null,
            'categoryId': switch (kind) {
              'income' => incomeCats[i % incomeCats.length],
              'expense' => expenseCats[i % expenseCats.length],
              _ => null,
            },
            'type': kind,
            'amount': 1000 + rnd.nextInt(200) * 500,
            'note': i % 3 == 0 ? 'Catatan $i' : null,
            'date': iso(now.subtract(Duration(hours: i * 5))),
          }),
        );
      }
      await pushAll(txs);
      final prayers = <PushMutation>[];
      const fardhu = ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya'];
      const statuses = ['masjid', 'jamaah', 'ontime', 'late', 'missed'];
      for (var d = 0; d < 60; d++) {
        final day = now.subtract(Duration(days: d + 1));
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        for (final (i, p) in fardhu.indexed) {
          final st = statuses[(d + i) % statuses.length];
          prayers.add(
            up(SyncEntity.prayers, 'up-p-$d-$p', {
              'date': key,
              'prayer': p,
              'status': st,
              'qobliyah': p == 'dzuhur' && st == 'masjid',
              'badiyah': false,
              'rakaat': null,
              'prayedAt': null,
              'note': null,
            }),
          );
        }
      }
      await pushAll(prayers);

      // The web (new version) already has tasks and a photo on a transaction; the
      // old app pulled past them without storing them.
      final uid = auth.user.id;
      await pushAll([
        up(SyncEntity.taskAreas, 'up-area-kuliah', {
          'name': 'Kuliah',
          'code': 'KUL',
          'color': '#123456',
          'icon': 'book-open',
          'schedule': null,
          'sortOrder': 2,
          'archived': false,
        }),
        up(SyncEntity.tasks, 'up-task-1', {
          'areaId': 'up-area-kuliah',
          'title': 'Skripsi bab 2',
          'bucket': 'fire',
        }),
        up(SyncEntity.tasks, 'up-task-2', {
          'areaId': 'area-kerjaan-$uid',
          'title': 'Rapat',
          'bucket': 'want',
        }),
      ]);
      final photoFile = File(
        '${Directory.systemTemp.path}/ghina_up_${DateTime.now().millisecondsSinceEpoch}.jpg',
      )..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0xFF, 0xD9]);
      addTearDown(photoFile.delete);
      final photoUrl = await api.upload(photoFile.path);
      final t7 = txs[7].data!;
      await pushAll([
        up(SyncEntity.transactions, 'up-t-7', {
          ...t7,
          'photos': [photoUrl],
        }),
      ]);

      // The old app's last sync happened after all of that.
      await Future<void>.delayed(const Duration(seconds: 6));
      final snap = await api.pull(0);
      expect(snap.changes[SyncEntity.transactions], hasLength(1500));
      expect(snap.changes[SyncEntity.taskAreas], hasLength(3));

      // ---- 2. The v2 database file on the phone.
      final dir = await Directory.systemTemp.createTemp('ghina_upgrade');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/ghina.sqlite');
      final old = v2.DatabaseAtV2(NativeDatabase(file));
      Future<void> ins(String sql, List<Object?> args) =>
          old.customStatement(sql, args);
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
            'INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [
              t['id'],
              t['walletId'],
              t['toWalletId'],
              t['categoryId'],
              t['type'],
              t['amount'],
              t['note'],
              ms(t['date']),
              ms(t['createdAt']),
              ms(t['updatedAt']),
            ],
          );
        }
        for (final p in snap.changes[SyncEntity.prayers]!) {
          await ins(
            'INSERT INTO prayers (id, date, prayer, status, qobliyah, badiyah, rakaat, prayed_at, note, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            [
              p['id'],
              p['date'],
              p['prayer'],
              p['status'],
              p['qobliyah'] == true ? 1 : 0,
              p['badiyah'] == true ? 1 : 0,
              p['rakaat'],
              null,
              p['note'],
              ms(p['createdAt']),
              ms(p['updatedAt']),
            ],
          );
        }
        await ins(
          'INSERT INTO sync_meta (id, cursor, epoch, user_id, last_sync_at, full_pull_required) VALUES (1,?,?,?,?,0)',
          [snap.serverTime, snap.epoch, uid, snap.serverTime],
        );

        // Pending offline work, exactly as the v2 app queued it (no `photos`).
        final at = DateTime.now().millisecondsSinceEpoch;
        Map<String, Object?> wire(Json t) => {
          'walletId': t['walletId'],
          'toWalletId': t['toWalletId'],
          'categoryId': t['categoryId'],
          'type': t['type'],
          'amount': t['amount'],
          'note': t['note'],
          'date': t['date'],
        };
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
        // (a) new expense created offline
        final newTx = {
          'walletId': 'up-w-tunai',
          'toWalletId': null,
          'categoryId': expenseCats.first,
          'type': 'expense',
          'amount': 35000,
          'note': 'Offline sebelum update',
          'date': iso(now),
        };
        await ins(
          'INSERT INTO transactions (id, wallet_id, to_wallet_id, category_id, type, amount, note, date, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            'up-new-1',
            'up-w-tunai',
            null,
            expenseCats.first,
            'expense',
            35000,
            'Offline sebelum update',
            now.millisecondsSinceEpoch,
            at,
            at,
          ],
        );
        await outbox('transactions', 'upsert', 'up-new-1', newTx, null, true);
        // (b) an edited transaction (amount changed) — tx 7 has a web photo
        final serverTx = {
          for (final t in snap.changes[SyncEntity.transactions]!)
            t['id'] as String: t,
        };
        final before7 = wire(serverTx['up-t-7']!);
        final after7 = {...before7, 'amount': 99000, 'note': 'diubah offline'};
        await old.customStatement(
          "UPDATE transactions SET amount = 99000, note = 'diubah offline' WHERE id = 'up-t-7'",
        );
        await outbox(
          'transactions',
          'upsert',
          'up-t-7',
          after7,
          before7,
          false,
        );
        // (c) a deleted transaction
        final before9 = wire(serverTx['up-t-9']!);
        await old.customStatement(
          "DELETE FROM transactions WHERE id = 'up-t-9'",
        );
        await outbox('transactions', 'delete', 'up-t-9', null, before9, false);
        // (d) a balance adjustment
        final adj = {
          'walletId': 'up-w-bca',
          'toWalletId': null,
          'categoryId': null,
          'type': 'adjustment',
          'amount': -12345,
          'note': 'Penyesuaian saldo',
          'date': iso(now),
        };
        await ins(
          'INSERT INTO transactions (id, wallet_id, type, amount, note, date, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)',
          [
            'up-adj-1',
            'up-w-bca',
            'adjustment',
            -12345,
            'Penyesuaian saldo',
            now.millisecondsSinceEpoch,
            at,
            at,
          ],
        );
        await outbox('transactions', 'upsert', 'up-adj-1', adj, null, true);
        // (e) today's prayer, with quality fields
        final today = snap.changes[SyncEntity.prayers]!.firstWhere(
          (p) => p['prayer'] == 'dzuhur',
        );
        await old.customStatement(
          "UPDATE prayers SET status = 'masjid', qobliyah = 1 WHERE id = ?",
          [today['id']],
        );
        await outbox(
          'prayers',
          'upsert',
          today['id'] as String,
          {
            'date': today['date'],
            'prayer': today['prayer'],
            'status': 'masjid',
            'qobliyah': true,
            'badiyah': false,
            'rakaat': null,
            'prayedAt': null,
            'note': 'offline',
          },
          null,
          false,
        );
      });
      final todayId = snap.changes[SyncEntity.prayers]!.firstWhere(
        (p) => p['prayer'] == 'dzuhur',
      )['id'];
      final v2Counts = {
        for (final t in [
          'wallets',
          'categories',
          'transactions',
          'prayers',
          'outbox',
        ])
          t:
              (await old
                      .customSelect('SELECT COUNT(*) AS c FROM $t')
                      .getSingle())
                  .read<int>('c'),
      };
      expect(v2Counts['transactions'], 1501); // 1500 + new + adj − deleted
      expect(v2Counts['outbox'], 5);
      expect(
        (await old.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        2,
      );
      await old.close();

      // ---- 3. Upgrade: open with the current app database.
      final db = AppDatabase(NativeDatabase(file));
      final outbox = Outbox(db);
      for (final t in [
        'wallets',
        'categories',
        'transactions',
        'prayers',
        'outbox',
      ]) {
        final c = await db
            .customSelect('SELECT COUNT(*) AS c FROM $t')
            .getSingle();
        expect(c.read<int>('c'), v2Counts[t], reason: t);
      }
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        3,
      );
      final meta0 = await db.getMeta();
      expect(meta0.epoch, snap.epoch);
      expect(meta0.userId, uid);

      // Displayed balances before the sync = server + pending effects.
      final store = LocalStore(db, outbox, const SystemClock());
      final wallets = DriftWalletRepository(store);
      final serverBal = {
        for (final w in snap.changes[SyncEntity.wallets]!)
          w['id'] as String: (w['balance'] as num).toDouble(),
      };
      final expected = Map.of(serverBal);
      expected['up-w-tunai'] = expected['up-w-tunai']! - 35000;
      expected['up-w-bca'] = expected['up-w-bca']! - 12345;
      final t7w = serverTx7Wallet(snap);
      expected[t7w.$1] =
          expected[t7w.$1]! + t7w.$2 - 99000; // edit: reverse old, apply new
      final t9 = snap.changes[SyncEntity.transactions]!.firstWhere(
        (t) => t['id'] == 'up-t-9',
      );
      applyReverse(expected, t9);
      final shown = {for (final w in await wallets.getAll()) w.id: w.balance};
      for (final id in walletIds) {
        expect(shown[id], closeTo(expected[id]!, 0.001), reason: id);
      }

      // ---- 4. First sync of the upgraded app.
      final engine = SyncEngine(
        db: db,
        outbox: outbox,
        api: api,
        photos: InMemoryPhotoStore(),
      );
      await engine.syncNow();
      final meta = await db.getMeta();
      expect(meta.lastError, isNull);
      expect(await outbox.all(), isEmpty);

      final after = await api.pull(0);
      final st = {
        for (final t in after.changes[SyncEntity.transactions]!)
          t['id'] as String: t,
      };
      expect(st['up-new-1']?['amount'], 35000);
      expect(st['up-t-7']?['amount'], 99000);
      expect(st['up-t-7']?['photos'], [photoUrl], reason: 'old app kept photo');
      expect(st.containsKey('up-t-9'), isFalse);
      expect(st['up-adj-1']?['amount'], -12345);
      final sp = after.changes[SyncEntity.prayers]!.firstWhere(
        (p) => p['id'] == todayId,
      );
      expect(sp['status'], 'masjid');
      expect(sp['note'], 'offline');

      final serverAfter = {
        for (final w in after.changes[SyncEntity.wallets]!)
          w['id'] as String: (w['balance'] as num).toDouble(),
      };
      final localAfter = {
        for (final w in await wallets.getAll()) w.id: w.balance,
      };
      for (final id in walletIds) {
        expect(serverAfter[id], closeTo(expected[id]!, 0.001), reason: id);
        expect(localAfter[id], closeTo(serverAfter[id]!, 0.001), reason: id);
      }
      expect(await db.select(db.transactions).get(), hasLength(1501));
      expect(await db.select(db.prayers).get(), hasLength(300));

      // What the old app couldn't store arrives now.
      final areas = await db.select(db.taskAreas).get();
      expect(areas.map((a) => a.id).toSet(), {
        'area-kerjaan-$uid',
        'area-life-$uid',
        'up-area-kuliah',
      });
      expect((await db.select(db.tasks).get()).map((t) => t.id).toSet(), {
        'up-task-1',
        'up-task-2',
      });
      final local7 = (await DriftTransactionRepository(
        store,
      ).getById('up-t-7'))!;
      expect(local7.photos, [TransactionPhoto.remote(photoUrl)]);
      expect(local7.amount, 99000);
      expect(
        (await api.pull(0)).changes[SyncEntity.taskAreas],
        hasLength(3),
        reason: 'no duplicate areas after the device seeded',
      );

      await engine.dispose();
      await db.close();
    },
    skip: base == null ? 'set GHINA_E2E_BASE_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// (walletId, amount) of transaction up-t-7 on the server before the edit
/// (asserted to be an expense or income without transfer for simple math).
(String, double) serverTx7Wallet(PullResponse snap) {
  final t = snap.changes[SyncEntity.transactions]!.firstWhere(
    (t) => t['id'] == 'up-t-7',
  );
  expect(t['type'], 'expense');
  return (t['walletId'] as String, (t['amount'] as num).toDouble());
}

/// Undo the balance effect of a deleted server transaction.
void applyReverse(Map<String, double> bal, Json t) {
  final a = (t['amount'] as num).toDouble();
  final w = t['walletId'] as String;
  switch (t['type']) {
    case 'income':
    case 'adjustment':
      bal[w] = bal[w]! - a;
    case 'expense':
      bal[w] = bal[w]! + a;
    case 'transfer':
      bal[w] = bal[w]! + a;
      final to = t['toWalletId'] as String;
      bal[to] = bal[to]! - a;
  }
}
