// End-to-end: the real mobile data layer (drift in memory, outbox, sync engine,
// repositories, use cases) on two simulated devices against the REAL server —
// tasks/areas, transaction photos, prayer/adjustment regression, web reset.
// Skipped unless GHINA_E2E_BASE_URL is set:
//   (cd .. && npx next dev -p 3100)
//   GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_tasks_photos_test.dart
// Throwaway users `mobile-test-dart-tp-*@example.test` and their upload files are
// removed at the end (`node scripts/e2e-helper.mjs cleanup …`).
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/auth_api.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart' show Json;
import 'package:ghina/data/repositories/auth_repository_impl.dart';
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/life_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/repositories/task_repositories.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

/// Real wall clock shifted by [offset] (device clocks differ; LWW uses them).
final class OffsetClock implements Clock {
  Duration offset = Duration.zero;
  @override
  DateTime now() => DateTime.now().add(offset);
}

const _password = 'rahasia123';
const emailPrefix = 'mobile-test-dart-tp-';

/// A 4×4 baseline JPEG (776 bytes).
final jpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAABKADAAQAAAABAAAABAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgABAAEAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMABgYGBgYGCgYGCg4KCgoOEg4ODg4SFxISEhISFxwXFxcXFxccHBwcHBwcHCIiIiIiIicnJycnLCwsLCwsLCwsLP/bAEMBBwcHCwoLEwoKEy4fGh8uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLv/dAAQAAf/aAAwDAQACEQMRAD8A86ooor44/pE//9k=',
);

/// The repo root (this test runs from `mobile/`).
final repoRoot = Directory.current.parent.path;

bool uploadExists(String url) => File('$repoRoot/public$url').existsSync();

Future<Json> helper(String cmd, String arg) async {
  final r = await Process.run('node', [
    'scripts/e2e-helper.mjs',
    cmd,
    arg,
  ], workingDirectory: repoRoot);
  if (r.exitCode != 0) throw StateError('helper $cmd failed: ${r.stderr}');
  return (jsonDecode((r.stdout as String).trim().split('\n').last) as Map)
      .cast<String, dynamic>();
}

/// One simulated phone: its own in-memory database + the real data layer.
class Device {
  Device(String baseUrl, this.name) {
    api = ApiClient(baseUrl: baseUrl, tokens: tokens);
    syncApi = DioSyncApi(api);
    auth = AuthRepositoryImpl(api: AuthApi(api), tokens: tokens, db: db);
    engine = SyncEngine(
      db: db,
      outbox: outbox,
      api: syncApi,
      photos: photos,
      clock: clock,
    );
  }

  final String name;
  final tokens = MemoryTokenStore();
  late final ApiClient api;
  late final DioSyncApi syncApi;
  late final AuthRepositoryImpl auth;
  late final SyncEngine engine;
  final db = AppDatabase.memory();
  late final outbox = Outbox(db);
  final clock = OffsetClock();
  final photos = InMemoryPhotoStore();
  late final store = LocalStore(db, outbox, clock);
  late final wallets = DriftWalletRepository(store);
  late final categories = DriftCategoryRepository(store);
  late final txs = DriftTransactionRepository(store, photos);
  late final prayers = DriftPrayerRepository(store);
  late final areas = DriftTaskAreaRepository(store);
  late final tasks = DriftTaskRepository(store);
  late final uow = DriftUnitOfWork(store);

  late final createWallet = CreateWallet(wallets, clock);
  late final createTx = CreateTransaction(txs, wallets, categories, clock);
  late final createArea = CreateTaskArea(areas, clock);
  late final updateArea = UpdateTaskArea(areas, clock);
  late final createTask = CreateTask(tasks, areas, wallets, categories, clock);
  late final updateTask = UpdateTask(tasks, areas, wallets, categories, clock);
  late final completeTask = CompleteTask(tasks, createTx, uow, clock);

  Future<void> sync() async {
    await engine.syncNow();
    expect((await db.getMeta()).lastError, isNull, reason: '$name sync error');
  }

  /// Syncs until the outbox is empty (re-queued work, e.g. area remaps).
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await sync();
      if ((await outbox.all()).isEmpty) return;
    }
    fail('$name outbox never drained: ${await outbox.all()}');
  }

  /// The server's full state for this account.
  Future<PullResponse> server() => syncApi.pull(0);

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

Map<String, Json> byId(List<Json> rows) => {
  for (final r in rows) r['id'] as String: r,
};

void main() {
  final base = Platform.environment['GHINA_E2E_BASE_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final skip = base == null ? 'set GHINA_E2E_BASE_URL to run' : false;
  final devices = <Device>[];
  var n = 0;

  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
  });
  tearDownAll(() async {
    if (base != null) await helper('cleanup', emailPrefix);
  });

  /// A fresh account with two signed-in devices (both synced once).
  Future<(Device, Device, String)> pair() async {
    final email =
        '$emailPrefix${DateTime.now().millisecondsSinceEpoch}-${n++}@example.test';
    final a = Device(base!, 'A');
    final b = Device(base, 'B');
    devices.addAll([a, b]);
    await a.auth.register(name: 'E2E', email: email, password: _password);
    await b.auth.signIn(email: email, password: _password);
    await a.sync();
    await b.sync();
    return (a, b, email);
  }

  Future<String> userId(Device d) async => (await d.db.getMeta()).userId!;

  Future<Map<String, double>> balances(Device d) async => {
    for (final w in await d.wallets.getAll()) w.id: w.balance,
  };

  Future<Map<String, double>> serverBalances(Device d) async => {
    for (final w in (await d.server()).changes[SyncEntity.wallets]!)
      w['id'] as String: (w['balance'] as num).toDouble(),
  };

  Future<Set<String>> localTaskIds(Device d) async => {
    for (final t in await d.tasks.getAll()) t.id,
  };

  test(
    'default areas: seeded once by the server, never duplicated by devices',
    () async {
      final (a, b, _) = await pair();
      final uid = await userId(a);
      final ids = {'area-kerjaan-$uid', 'area-life-$uid'};
      expect({for (final x in await a.areas.getAll()) x.id}, ids);
      expect({for (final x in await b.areas.getAll()) x.id}, ids);

      // A third device that seeds locally (offline, "Buat area default" / its own
      // seeding) before it ever pulls: same ids → upsert, not duplicates.
      final c = Device(base!, 'C');
      devices.add(c);
      c.tokens.token = a.tokens.token;
      await c.db.updateMeta(SyncMetaCompanion(userId: Value(uid)));
      final seeded = await SeedDefaultTaskAreas(c.areas, c.uow, c.clock)(uid);
      expect(seeded.valueOrThrow, 2);
      await c.settle();
      await a.sync();
      final server = await a.server();
      expect(server.changes[SyncEntity.taskAreas], hasLength(2));
      expect({
        for (final r in server.changes[SyncEntity.taskAreas]!) r['id'],
      }, ids);
      expect(
        {for (final r in server.changes[SyncEntity.taskAreas]!) r['code']},
        {'KERJA', 'LIFE'},
      );
      expect(await c.areas.getAll(), hasLength(2));
      expect(await a.areas.getAll(), hasLength(2));
      expect((await a.db.getMeta()).tasksSeeded, isTrue);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'offline areas/tasks on A → B pulls; concurrent edits resolve LWW',
    () async {
      final (a, b, _) = await pair();
      final area = (await a.createArea(
        const TaskAreaInput(
          name: 'Kuliah',
          code: 'kul',
          schedule: AreaSchedule(days: [6], start: '08:00', end: '12:00'),
        ),
      )).valueOrThrow;
      expect(area.code, 'KUL');
      final t1 = (await a.createTask(
        TaskInput(
          areaId: area.id,
          title: 'Tugas kalkulus',
          bucket: TaskBucket.fire,
          dueDate: DateTime.now(),
          dueTime: '21:00',
          remindBefore: 30,
        ),
      )).valueOrThrow;
      final t2 = (await a.createTask(
        TaskInput(areaId: area.id, title: 'Baca bab 3'),
      )).valueOrThrow;
      await a.settle();

      await b.sync();
      final bArea = (await b.areas.getById(area.id))!;
      expect(bArea.schedule, area.schedule);
      expect(bArea.code, 'KUL');
      final bt1 = (await b.tasks.getById(t1.id))!;
      expect(bt1.title, 'Tugas kalkulus');
      expect(bt1.dueTime, '21:00');
      expect(bt1.remindBefore, 30);
      expect(await b.tasks.getById(t2.id), isNotNull);

      // Both edit t1 offline; B's edit is later (clock ahead) → B wins even though
      // A pushes first.
      await a.updateTask(
        t1.id,
        TaskInput(areaId: area.id, title: 'Versi A', bucket: TaskBucket.fire),
      );
      b.clock.offset = const Duration(minutes: 10);
      await b.updateTask(
        t1.id,
        TaskInput(areaId: area.id, title: 'Versi B', bucket: TaskBucket.want),
      );
      await a.sync();
      await b.sync();
      await a.sync();
      expect((await a.tasks.getById(t1.id))!.title, 'Versi B');
      expect((await b.tasks.getById(t1.id))!.bucket, TaskBucket.want);

      // A stale edit (older than the server row) is skipped and reverted by the pull.
      a.clock.offset = const Duration(hours: -1);
      await a.updateArea(
        area.id,
        const TaskAreaInput(name: 'Lama', code: 'KUL'),
      );
      await a.sync();
      expect((await a.areas.getById(area.id))!.name, 'Kuliah');
      final srv = byId((await a.server()).changes[SyncEntity.tasks]!);
      expect(srv[t1.id]!['title'], 'Versi B');
      expect(await a.outbox.all(), isEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'recurring task completed on BOTH devices offline → one next occurrence',
    () async {
      final (a, b, _) = await pair();
      final uid = await userId(a);
      final today = DateTime.now();
      final t = (await a.createTask(
        TaskInput(
          areaId: 'area-life-$uid',
          title: 'Minum vitamin',
          bucket: TaskBucket.should,
          dueDate: today,
          dueTime: '07:00',
          recurrence: const Recurrence.daily(),
        ),
      )).valueOrThrow;
      await a.settle();
      await b.sync();
      expect(await b.tasks.getById(t.id), isNotNull);

      final nextId =
          '${t.id}_${dateKey(today.add(const Duration(days: 1))).replaceAll('-', '')}';
      final ca = (await a.completeTask(t.id)).valueOrThrow;
      b.clock.offset = const Duration(seconds: 5);
      final cb = (await b.completeTask(t.id)).valueOrThrow;
      expect(ca.next!.id, nextId);
      expect(cb.next!.id, nextId);

      await a.sync();
      await b.sync();
      await a.sync();

      final server = (await a.server()).changes[SyncEntity.tasks]!;
      final series = [
        for (final r in server)
          if (r['id'] == t.id || r['seriesId'] == t.id) r,
      ];
      expect(series.map((r) => r['id']).toSet(), {t.id, nextId});
      expect(series, hasLength(2));
      final s = byId(series);
      expect(s[t.id]!['done'], isTrue);
      expect(s[t.id]!['doneAt'], isNotNull);
      expect(s[nextId]!['done'], isFalse);
      expect(s[nextId]!['seriesId'], t.id);
      expect(s[nextId]!['dueTime'], '07:00');
      for (final d in [a, b]) {
        expect(await localTaskIds(d), {t.id, nextId}, reason: d.name);
        expect((await d.tasks.getById(t.id))!.done, isTrue);
        expect((await d.tasks.getById(nextId))!.done, isFalse);
        expect(await d.outbox.all(), isEmpty);
      }

      // Complete → un-complete → complete again on A: still exactly one next.
      await UncompleteTask(a.tasks, a.clock)(t.id);
      await a.completeTask(t.id);
      await a.settle();
      await b.sync();
      final again = (await a.server()).changes[SyncEntity.tasks]!;
      expect(again.where((r) => r['seriesId'] == t.id), hasLength(2));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'money link: completing records the expense; balances agree everywhere',
    () async {
      final (a, b, _) = await pair();
      final uid = await userId(a);
      final w = (await a.createWallet(
        const WalletInput(name: 'BCA', initialBalance: 1000000),
      )).valueOrThrow;
      final cat = (await a.categories.getAll()).firstWhere(
        (c) => c.type == CategoryType.expense,
      );
      final t = (await a.createTask(
        TaskInput(
          areaId: 'area-kerjaan-$uid',
          title: 'Bayar listrik',
          bucket: TaskBucket.fire,
          dueDate: DateTime.now(),
          recurrence: const Recurrence.monthly(),
          amount: 250000,
          walletId: w.id,
          categoryId: cat.id,
        ),
      )).valueOrThrow;
      await a.settle();
      await b.sync();

      // Offline completion with the expense, pushed in one go.
      final done = (await a.completeTask(
        t.id,
        expense: TaskExpense(
          amount: 250000,
          walletId: w.id,
          categoryId: cat.id,
        ),
      )).valueOrThrow;
      expect(done.transaction, isNotNull);
      expect((await a.wallets.getById(w.id))!.balance, 750000);
      await a.settle();
      await b.sync();

      final server = await a.server();
      final st = byId(server.changes[SyncEntity.tasks]!)[t.id]!;
      expect(st['transactionId'], done.transaction!.id);
      final stx = byId(
        server.changes[SyncEntity.transactions]!,
      )[done.transaction!.id]!;
      expect(stx['amount'], 250000);
      expect(stx['note'], 'Bayar listrik');
      expect(stx['categoryId'], cat.id);
      expect((await serverBalances(a))[w.id], 750000);
      expect(await balances(a), await serverBalances(a));
      expect(await balances(b), await serverBalances(a));
      expect(
        (await b.tasks.getById(t.id))!.transactionId,
        done.transaction!.id,
      );
      final next = done.next!;
      expect((await b.tasks.getById(next.id))!.transactionId, isNull);
      expect((await b.tasks.getById(next.id))!.amount, 250000);

      // Completing again never records a second expense.
      await a.completeTask(
        t.id,
        expense: TaskExpense(amount: 250000, walletId: w.id),
      );
      await a.settle();
      expect((await serverBalances(a))[w.id], 750000);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'area code clash across devices: one area, no task lost',
    () async {
      final (a, b, _) = await pair();
      final areaA = (await a.createArea(
        const TaskAreaInput(name: 'Bisnis A', code: 'BIZ'),
      )).valueOrThrow;
      final ta = (await a.createTask(
        TaskInput(areaId: areaA.id, title: 'Dari A'),
      )).valueOrThrow;
      final areaB = (await b.createArea(
        const TaskAreaInput(name: 'Bisnis B', code: 'BIZ'),
      )).valueOrThrow;
      final tb = (await b.createTask(
        TaskInput(areaId: areaB.id, title: 'Dari B'),
      )).valueOrThrow;

      await b.settle(); // B wins the code
      await a.settle(); // A: duplicate → its task moves to B's area
      await b.sync();

      final server = await a.server();
      final biz = [
        for (final r in server.changes[SyncEntity.taskAreas]!)
          if (r['code'] == 'BIZ') r,
      ];
      expect(biz, hasLength(1));
      expect(biz.single['id'], areaB.id);
      final st = byId(server.changes[SyncEntity.tasks]!);
      expect(st[ta.id]?['areaId'], areaB.id, reason: 'A task kept + moved');
      expect(st[tb.id]?['areaId'], areaB.id);
      for (final d in [a, b]) {
        expect(await d.areas.getById(areaA.id), isNull, reason: d.name);
        expect((await d.tasks.getById(ta.id))?.areaId, areaB.id);
        expect((await d.tasks.getById(tb.id))?.areaId, areaB.id);
        expect(
          (await d.areas.getAll()).where((x) => x.code == 'BIZ'),
          hasLength(1),
        );
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'deletes: area → tasks gone on the other device; wallet/category/tx → refs nulled',
    () async {
      final (a, b, _) = await pair();
      final uid = await userId(a);
      final area = (await a.createArea(
        const TaskAreaInput(name: 'Proyek', code: 'PRJ'),
      )).valueOrThrow;
      final inArea = (await a.createTask(
        TaskInput(areaId: area.id, title: 'Di area proyek'),
      )).valueOrThrow;
      final w = (await a.createWallet(
        const WalletInput(name: 'Dana', initialBalance: 500000),
      )).valueOrThrow;
      final w2 = (await a.createWallet(
        const WalletInput(name: 'OVO', initialBalance: 100000),
      )).valueOrThrow;
      final cat = (await CreateCategory(a.categories, a.clock)(
        const CategoryInput(name: 'Proyek', type: CategoryType.expense),
      )).valueOrThrow;
      final life = 'area-life-$uid';
      final tWallet = (await a.createTask(
        TaskInput(
          areaId: life,
          title: 'wallet ref',
          amount: 10,
          walletId: w.id,
        ),
      )).valueOrThrow;
      final tCat = (await a.createTask(
        TaskInput(
          areaId: life,
          title: 'cat ref',
          amount: 10,
          categoryId: cat.id,
        ),
      )).valueOrThrow;
      final tTx = (await a.createTask(
        TaskInput(
          areaId: life,
          title: 'tx ref',
          amount: 20000,
          walletId: w2.id,
        ),
      )).valueOrThrow;
      final tx = (await a.completeTask(
        tTx.id,
        expense: TaskExpense(amount: 20000, walletId: w2.id),
      )).valueOrThrow.transaction!;
      await a.settle();
      await b.sync();
      expect(await b.tasks.getById(inArea.id), isNotNull);
      expect((await b.tasks.getById(tTx.id))!.transactionId, tx.id);

      // Deletes on B.
      expect((await DeleteTaskArea(b.areas)(area.id)).isOk, isTrue);
      expect((await DeleteWallet(b.wallets)(w.id)).isOk, isTrue);
      expect((await DeleteCategory(b.categories)(cat.id)).isOk, isTrue);
      expect((await DeleteTransaction(b.txs)(tx.id)).isOk, isTrue);
      expect((await b.tasks.getById(tWallet.id))!.walletId, isNull);
      await b.settle();
      await a.sync();

      final server = await a.server();
      final st = byId(server.changes[SyncEntity.tasks]!);
      expect(st.containsKey(inArea.id), isFalse);
      expect(st[tWallet.id]!['walletId'], isNull);
      expect(st[tCat.id]!['categoryId'], isNull);
      expect(st[tTx.id]!['transactionId'], isNull);
      expect(st[tTx.id]!['walletId'], w2.id);
      for (final d in [a, b]) {
        expect(await d.areas.getById(area.id), isNull, reason: d.name);
        expect(await d.tasks.getById(inArea.id), isNull, reason: d.name);
        expect((await d.tasks.getById(tWallet.id))!.walletId, isNull);
        expect((await d.tasks.getById(tCat.id))!.categoryId, isNull);
        expect((await d.tasks.getById(tTx.id))!.transactionId, isNull);
        expect(await d.txs.getById(tx.id), isNull);
      }
      // Deleting the expense reversed it.
      expect((await serverBalances(a))[w2.id], 100000);
      expect(await balances(a), await serverBalances(a));
      expect(await balances(b), await serverBalances(a));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'transaction photos: offline attach → upload → other device; remove/delete clean files',
    () async {
      final (a, b, _) = await pair();
      final dir = await Directory.systemTemp.createTemp('ghina_e2e_photos');
      addTearDown(() => dir.delete(recursive: true));
      final f1 = File('${dir.path}/nota1.jpg')..writeAsBytesSync(jpegBytes);
      final f2 = File('${dir.path}/nota2.jpg')..writeAsBytesSync(jpegBytes);
      final f3 = File('${dir.path}/bukti.jpg')..writeAsBytesSync(jpegBytes);
      final w = (await a.wallets.getAll()).first;

      final t = (await a.createTx(
        TransactionInput(
          type: TxType.expense,
          amount: 42000,
          walletId: w.id,
          note: 'Belanja',
          date: DateTime.now(),
          photos: [
            TransactionPhoto.local(f1.path),
            TransactionPhoto.local(f2.path),
          ],
        ),
      )).valueOrThrow;
      expect(t.photos.every((p) => p.isPending), isTrue);
      await a.settle();

      final local = (await a.txs.getById(t.id))!.photos;
      expect(local, hasLength(2));
      expect(local.every((p) => !p.isPending), isTrue);
      final urls = [for (final p in local) p.url!];
      expect(
        urls.every((u) => RegExp(r'^/uploads/[A-Za-z0-9-]+\.jpg$').hasMatch(u)),
        isTrue,
        reason: '$urls',
      );
      expect(urls.every(uploadExists), isTrue);
      expect(
        File('$repoRoot/public${urls.first}').readAsBytesSync(),
        jpegBytes,
      );
      expect(a.photos.deleted, containsAll([f1.path, f2.path]));
      var srv = byId((await a.server()).changes[SyncEntity.transactions]!);
      expect(srv[t.id]!['photos'], urls);

      await b.sync();
      expect((await b.txs.getById(t.id))!.photos, [
        for (final u in urls) TransactionPhoto.remote(u),
      ]);

      // B adds one offline while A removes one → both converge after syncs.
      await AddTransactionPhotos(b.txs, b.clock)(t.id, [f3.path]);
      await b.settle();
      final three = (await b.txs.getById(t.id))!.photos;
      expect(three, hasLength(3));
      await a.sync();
      await RemoveTransactionPhoto(a.txs, a.clock)(
        t.id,
        TransactionPhoto.remote(urls.first),
      );
      await a.settle();
      await b.sync();
      expect(uploadExists(urls.first), isFalse, reason: 'removed file deleted');
      expect(uploadExists(urls[1]), isTrue);
      srv = byId((await a.server()).changes[SyncEntity.transactions]!);
      expect(srv[t.id]!['photos'], [urls[1], three[2].url]);
      expect((await b.txs.getById(t.id))!.photos, [
        TransactionPhoto.remote(urls[1]),
        three[2],
      ]);

      // Delete the transaction on B → remaining files deleted on the server.
      await DeleteTransaction(b.txs)(t.id);
      await b.settle();
      await a.sync();
      expect(uploadExists(urls[1]), isFalse);
      expect(uploadExists(three[2].url!), isFalse);
      expect(await a.txs.getById(t.id), isNull);
      expect(await balances(a), await serverBalances(a));

      // Invalid URLs are rejected by the server.
      for (final bad in [
        '/uploads/../../package.json',
        'https://evil.example/x.jpg',
        '/uploads/a b.jpg',
      ]) {
        final res = await a.syncApi.push([
          PushMutation(
            id: 'bad-${bad.hashCode}',
            entity: SyncEntity.transactions,
            op: MutationOp.upsert,
            entityId: 'badphoto${bad.length}',
            data: {
              'walletId': w.id,
              'toWalletId': null,
              'categoryId': null,
              'type': 'expense',
              'amount': 1,
              'note': null,
              'date': DateTime.now().toUtc().toIso8601String(),
              'photos': [bad],
            },
            clientUpdatedAt: DateTime.now(),
          ),
        ], epoch: (await a.db.getMeta()).epoch);
        expect(res.results.single.status, PushStatus.rejected, reason: bad);
      }
      expect(await balances(a), await serverBalances(a));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'regression: prayer statuses and balance adjustments sync between devices',
    () async {
      final (a, b, _) = await pair();
      final today = DateTime.now();
      final key = dateKey(today);
      (await SetPrayerStatus(a.prayers, a.clock)(
        today,
        Prayer.dzuhur,
        PrayerStatus.masjid,
      )).valueOrThrow;
      (await ToggleRawatib(a.prayers, a.clock)(
        today,
        Prayer.dzuhur,
        RawatibSlot.qobliyah,
      )).valueOrThrow;
      (await SetSunnah(a.prayers, a.clock)(
        today,
        Prayer.witir,
        done: true,
        rakaat: 3,
      )).valueOrThrow;
      final w = (await a.createWallet(
        const WalletInput(name: 'Kas', initialBalance: 100000),
      )).valueOrThrow;
      await a.settle();
      final adj = (await AdjustWalletBalance(a.wallets, a.txs, a.clock)(
        w.id,
        87500,
      )).valueOrThrow;
      expect(adj.amount, -12500);
      await a.settle();
      await b.sync();

      final bp = {
        for (final p in await b.prayers.watchRange(key, key).first) p.prayer: p,
      };
      expect(bp[Prayer.dzuhur]!.status, PrayerStatus.masjid);
      expect(bp[Prayer.dzuhur]!.qobliyah, isTrue);
      expect(bp[Prayer.witir]!.rakaat, 3);
      final btx = (await b.txs.getById(adj.id))!;
      expect(btx.type, TxType.adjustment);
      expect(btx.amount, -12500);
      expect((await b.wallets.getById(w.id))!.balance, 87500);
      expect((await serverBalances(a))[w.id], 87500);

      // B downgrades to missed (rawatib must be cleared) → A pulls it.
      b.clock.offset = const Duration(seconds: 2);
      (await SetPrayerStatus(b.prayers, b.clock)(
        today,
        Prayer.dzuhur,
        PrayerStatus.missed,
      )).valueOrThrow;
      await b.settle();
      await a.sync();
      final ap = (await a.prayers.watchRange(key, key).first).firstWhere(
        (p) => p.prayer == Prayer.dzuhur,
      );
      expect(ap.status, PrayerStatus.missed);
      expect(ap.qobliyah, isFalse);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'web reset → new epoch → devices wipe and re-pull; tasks/areas kept, links nulled',
    () async {
      final (a, b, email) = await pair();
      final uid = await userId(a);
      final w = (await a.createWallet(
        const WalletInput(name: 'Reset', initialBalance: 1000),
      )).valueOrThrow;
      final t = (await a.createTask(
        TaskInput(
          areaId: 'area-kerjaan-$uid',
          title: 'Tetap ada',
          amount: 100,
          walletId: w.id,
        ),
      )).valueOrThrow;
      final area = (await a.createArea(
        const TaskAreaInput(name: 'Kuliah', code: 'KUL'),
      )).valueOrThrow;
      await SetPrayerStatus(a.prayers, a.clock)(
        DateTime.now(),
        Prayer.subuh,
        PrayerStatus.jamaah,
      );
      await a.settle();
      await b.sync();
      final oldEpoch = (await a.db.getMeta()).epoch;

      final r = await helper('reset', email);
      expect(r['epoch'], isNot(oldEpoch));

      // A has a pending change from before it learned about the reset.
      await a.createTx(
        TransactionInput(
          type: TxType.expense,
          amount: 5,
          walletId: w.id,
          date: DateTime.now(),
        ),
      );
      await a.sync(); // push → 409 → wipe → full pull
      await b.sync(); // pull sees the new epoch → wipe → full pull
      for (final d in [a, b]) {
        final meta = await d.db.getMeta();
        expect(meta.epoch, r['epoch'], reason: d.name);
        expect(await d.outbox.all(), isEmpty);
        expect(await d.wallets.getAll(), isEmpty);
        expect(await d.txs.list(), isEmpty);
        expect(await d.categories.getAll(), isEmpty);
        final kept = (await d.tasks.getById(t.id))!;
        expect(kept.walletId, isNull);
        expect(kept.amount, 100);
        expect(await d.areas.getById(area.id), isNotNull);
        expect(await d.areas.getAll(), hasLength(3));
        expect(
          await d.prayers.watchRange('2000-01-01', '2100-01-01').first,
          hasLength(1),
        );
      }
      final server = await a.server();
      expect(server.changes[SyncEntity.wallets], isEmpty);
      expect(server.changes[SyncEntity.taskAreas], hasLength(3));

      // Life goes on after the reset.
      final w2 = (await b.createWallet(
        const WalletInput(name: 'Baru', initialBalance: 10),
      )).valueOrThrow;
      await b.settle();
      await a.sync();
      expect((await a.wallets.getById(w2.id))!.balance, 10);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
