// Tasks + transaction photos over the real drift DB and the fake server
// (docs/tasks.md, docs/transaction-photos.md, docs/mobile-sync.md).
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/mappers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../harness.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.close());

  Future<String> newArea(String code, {AreaSchedule? schedule}) async {
    h.tick();
    return (await h.createArea(
      TaskAreaInput(name: code, code: code, schedule: schedule),
    )).valueOrThrow.id;
  }

  Future<Task> newTask(
    String areaId,
    String title, {
    TaskBucket bucket = TaskBucket.want,
    DateTime? due,
    String? time,
    Recurrence? recurrence,
    double? amount,
    String? walletId,
    String? categoryId,
    int? remindBefore,
  }) async {
    h.tick();
    return (await h.createTask(
      TaskInput(
        areaId: areaId,
        title: title,
        bucket: bucket,
        dueDate: due,
        dueTime: time,
        recurrence: recurrence,
        amount: amount,
        walletId: walletId,
        categoryId: categoryId,
        remindBefore: remindBefore,
      ),
    )).valueOrThrow;
  }

  Future<List<Task>> allTasks() => h.tasks.getAll();

  Future<void> setOwner(Harness x, String userId) =>
      x.db.updateMeta(SyncMetaCompanion(userId: Value(userId)));

  group('areas & tasks sync', () {
    test('create offline → pushed with JSON objects on the wire', () async {
      final a = await newArea('KERJA', schedule: AreaSchedule.workHours);
      final t = await newTask(
        a,
        'Bayar listrik',
        bucket: TaskBucket.fire,
        due: DateTime(2026, 9, 30),
        time: '09:00',
        recurrence: const Recurrence.monthly(),
        remindBefore: 30,
      );
      await h.engine.syncNow();
      final sa = h.server.rows[SyncEntity.taskAreas]![a]!;
      expect(sa['schedule'], {
        'days': [1, 2, 3, 4, 5],
        'start': '09:00',
        'end': '17:00',
      });
      final st = h.server.rows[SyncEntity.tasks]![t.id]!;
      expect(st['recurrence'], {
        'freq': 'monthly',
        'interval': 1,
        'monthDay': 30,
      });
      expect(st['seriesId'], t.id);
      expect(st['dueDate'], '2026-09-30');
      expect(st['dueTime'], '09:00');
      expect(st['doneAt'], isNull);
      expect(st['bucket'], 'fire');
      expect(await h.outboxCount(), 0);
      // Area upserts go before the tasks that reference them.
      final order = [for (final m in h.server.pushed) m.entity];
      expect(
        order.indexOf(SyncEntity.taskAreas),
        lessThan(order.indexOf(SyncEntity.tasks)),
      );
    });

    test('pulled rows (web) land locally, incl. JSON fields', () async {
      h.server.web(SyncEntity.taskAreas, 'srvA', {
        'name': 'Kuliah',
        'code': 'KUL',
        'color': '#123456',
        'icon': 'book',
        'schedule': {
          'days': [6],
          'start': '08:00',
          'end': '12:00',
        },
        'sortOrder': 2,
        'archived': false,
      });
      h.server.web(SyncEntity.tasks, 'srvT', {
        'areaId': 'srvA',
        'title': 'Tugas kalkulus',
        'note': null,
        'bucket': 'fire',
        'dueDate': '2026-09-26',
        'dueTime': '10:00',
        'remindBefore': 60,
        'recurrence': {
          'freq': 'weekly',
          'interval': 1,
          'weekdays': [6],
        },
        'seriesId': 'srvT',
        'done': true,
        'doneAt': '2026-09-23T03:00:00.000Z',
        'sortOrder': 1.5,
        'amount': 20000,
        'walletId': null,
        'categoryId': null,
        'transactionId': null,
      });
      await h.engine.syncNow();
      final a = (await h.taskAreas.getById('srvA'))!;
      expect(
        a.schedule,
        const AreaSchedule(days: [6], start: '08:00', end: '12:00'),
      );
      final t = (await h.tasks.getById('srvT'))!;
      expect(t.recurrence, const Recurrence.weekly(weekdays: [6]));
      expect(t.done, isTrue);
      expect(t.doneAt, DateTime.utc(2026, 9, 23, 3).toLocal());
      expect(t.sortOrder, 1.5);
      expect(t.amount, 20000);
      expect(t.bucket, TaskBucket.fire);
    });

    test(
      'complete recurring: done + next occurrence, idempotent on repeat',
      () async {
        final a = await newArea('LIFE');
        final t = await newTask(
          a,
          'Bayar kos',
          due: DateTime(2026, 1, 31),
          recurrence: const Recurrence.monthly(),
        );
        h.tick();
        final c = (await h.completeTask(t.id)).valueOrThrow;
        expect(c.task.done, isTrue);
        expect(c.task.doneAt, h.clock.now());
        expect(c.next!.id, '${t.id}_20260228');
        expect(c.next!.recurrence, const Recurrence.monthly(monthDay: 31));

        // Completing again is a no-op; un-complete + complete never duplicates.
        h.tick();
        final again = (await h.completeTask(t.id)).valueOrThrow;
        expect(again.next!.id, c.next!.id);
        h.tick();
        await h.uncompleteTask(t.id);
        expect((await h.tasks.getById(c.next!.id)), isNotNull);
        h.tick();
        await h.completeTask(t.id);
        expect(await allTasks(), hasLength(2));

        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.tasks]!.keys, {t.id, c.next!.id});
        expect(h.server.rows[SyncEntity.tasks]![t.id]!['done'], isTrue);
        expect(h.server.rows[SyncEntity.tasks]![t.id]!['doneAt'], isNotNull);
      },
    );

    test('two devices completing the same occurrence converge', () async {
      final a = await newArea('LIFE');
      final t = await newTask(
        a,
        'Siram tanaman',
        due: DateTime(2026, 9, 24),
        recurrence: const Recurrence.daily(),
      );
      await h.engine.syncNow();

      final other = Harness(server: h.server);
      addTearDown(other.close);
      await other.engine.syncNow();
      expect(await other.tasks.getById(t.id), isNotNull);

      h.tick();
      await h.completeTask(t.id);
      other.tick();
      other.tick();
      await other.completeTask(t.id);
      await h.engine.syncNow();
      await other.engine.syncNow();
      await h.engine.syncNow();

      expect(h.server.rows[SyncEntity.tasks]!.keys, {t.id, '${t.id}_20260925'});
      expect((await allTasks()).map((x) => x.id).toSet(), {
        t.id,
        '${t.id}_20260925',
      });
      expect(await other.tasks.getAll(), hasLength(2));
    });

    test('money link: completing records the expense and links it', () async {
      final w = await h.newWallet('Tunai', 500000);
      h.tick();
      final cat = (await h.createCategory(
        const CategoryInput(name: 'Listrik', type: CategoryType.expense),
      )).valueOrThrow;
      final a = await newArea('LIFE');
      final t = await newTask(
        a,
        'Bayar listrik',
        amount: 250000,
        walletId: w,
        categoryId: cat.id,
      );
      final draft = expenseDraftFor(t)!;
      expect(draft.amount, 250000);
      expect(draft.walletId, w);
      expect(draft.note, 'Bayar listrik');

      h.tick();
      final c = (await h.completeTask(t.id, expense: draft)).valueOrThrow;
      final tx = c.transaction!;
      expect(tx.type, TxType.expense);
      expect(tx.amount, 250000);
      expect(tx.categoryId, cat.id);
      expect(tx.note, 'Bayar listrik');
      expect(c.task.transactionId, tx.id);
      expect((await h.wallet(w)).balance, 250000);

      await h.engine.syncNow();
      expect(h.server.rejected, isEmpty);
      expect(h.server.rows[SyncEntity.tasks]![t.id]!['transactionId'], tx.id);
      expect(h.server.balanceOf(w), 250000);

      // Un-completing keeps the link.
      h.tick();
      await h.uncompleteTask(t.id);
      expect((await h.tasks.getById(t.id))!.transactionId, tx.id);
    });

    test('money link: a bad expense rolls everything back', () async {
      final a = await newArea('LIFE');
      final t = await newTask(a, 'Beli pulsa', amount: 50000);
      final before = await h.outboxCount();
      final r = await h.completeTask(
        t.id,
        expense: const TaskExpense(amount: 50000),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
      final r2 = await h.completeTask(
        t.id,
        expense: const TaskExpense(amount: 50000, walletId: 'nope'),
      );
      expect(r2.failureOrNull, isA<NotFoundFailure>());
      expect((await h.tasks.getById(t.id))!.done, isFalse);
      expect(await h.transactions.list(), isEmpty);
      expect(await h.outboxCount(), before);
      // Declining: just complete.
      expect((await h.completeTask(t.id)).valueOrThrow.transaction, isNull);
    });

    test('move / reorder', () async {
      final a = await newArea('A');
      final b = await newArea('B');
      final t1 = await newTask(a, '1', bucket: TaskBucket.want);
      final t2 = await newTask(a, '2', bucket: TaskBucket.fire);
      h.tick();
      final moved = (await h.moveTask(
        t1.id,
        bucket: TaskBucket.fire,
      )).valueOrThrow;
      expect(moved.bucket, TaskBucket.fire);
      expect(moved.sortOrder, greaterThan(t2.sortOrder));
      h.tick();
      await h.reorderTasks([t1.id, t2.id]);
      expect((await h.tasks.getById(t1.id))!.sortOrder, 0);
      expect((await h.tasks.getById(t2.id))!.sortOrder, 1);
      h.tick();
      expect((await h.moveTask(t2.id, areaId: b)).valueOrThrow.areaId, b);
      expect(
        (await h.moveTask(t2.id, areaId: 'zz')).failureOrNull,
        isA<NotFoundFailure>(),
      );
    });
  });

  group('cascades', () {
    test(
      'deleting an area deletes its tasks (locally and on the server)',
      () async {
        final a = await newArea('A');
        final keep = await newArea('B');
        await newTask(a, 'x');
        await newTask(a, 'y');
        final other = await newTask(keep, 'z');
        await h.engine.syncNow();
        h.tick();
        await h.deleteArea(a);
        expect((await allTasks()).map((t) => t.id), [other.id]);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.tasks]!.keys, [other.id]);
        expect(h.server.rejected, isEmpty);
      },
    );

    test('unpushed tasks of a deleted area never reach the server', () async {
      final a = await newArea('A');
      await newTask(a, 'x');
      h.tick();
      await h.deleteArea(a);
      expect(await h.outboxCount(), 0);
      await h.engine.syncNow();
      expect(h.server.pushed, isEmpty);
    });

    test('area tombstone from the web deletes local tasks', () async {
      final a = await newArea('A');
      await newTask(a, 'x');
      await h.engine.syncNow();
      h.server.webDelete(SyncEntity.taskAreas, a);
      await h.engine.syncNow();
      expect(await h.taskAreas.getAll(), isEmpty);
      expect(await allTasks(), isEmpty);
    });

    test('wallet / category / transaction delete nulls task refs', () async {
      final w = await h.newWallet('Tunai', 100000);
      h.tick();
      final cat = (await h.createCategory(
        const CategoryInput(name: 'Makan', type: CategoryType.expense),
      )).valueOrThrow;
      final a = await newArea('A');
      final t1 = await newTask(a, 'w', amount: 10, walletId: w);
      final t2 = await newTask(a, 'c', amount: 10, categoryId: cat.id);
      final w2 = await h.newWallet('BCA', 100000);
      final t3 = await newTask(a, 't', amount: 10, walletId: w2);
      h.tick();
      final c = (await h.completeTask(
        t3.id,
        expense: TaskExpense(amount: 10, walletId: w2),
      )).valueOrThrow;

      // Locally, before any push: the queued upserts are patched too.
      h.tick();
      await h.deleteWallet(w);
      h.tick();
      await h.deleteCategory(cat.id);
      h.tick();
      await h.deleteTx(c.transaction!.id);
      expect((await h.tasks.getById(t1.id))!.walletId, isNull);
      expect((await h.tasks.getById(t2.id))!.categoryId, isNull);
      expect((await h.tasks.getById(t3.id))!.transactionId, isNull);
      expect((await h.tasks.getById(t3.id))!.walletId, w2);
      await h.engine.syncNow();
      expect(h.server.rejected, isEmpty);
      expect(h.server.rows[SyncEntity.tasks]![t1.id]!['walletId'], isNull);
      expect(h.server.rows[SyncEntity.tasks]![t3.id]!['transactionId'], isNull);
    });

    test('tombstones from the web null task refs', () async {
      final w = await h.newWallet('Tunai', 100000);
      final a = await newArea('A');
      final t = await newTask(a, 'w', amount: 10, walletId: w);
      h.tick();
      final c = (await h.completeTask(
        t.id,
        expense: TaskExpense(amount: 10, walletId: w),
      )).valueOrThrow;
      await h.engine.syncNow();
      h.server.webDelete(SyncEntity.transactions, c.transaction!.id);
      await h.engine.syncNow();
      expect((await h.tasks.getById(t.id))!.transactionId, isNull);
      h.server.webDelete(SyncEntity.wallets, w);
      await h.engine.syncNow();
      expect((await h.tasks.getById(t.id))!.walletId, isNull);
    });
  });

  group('default areas', () {
    test('server seeds on pull → the app does not seed', () async {
      await setOwner(h, 'u1');
      h.server.seedAreasFor = 'u1';
      await h.engine.syncNow();
      expect((await h.taskAreas.getAll()).map((a) => a.id), [
        'area-kerjaan-u1',
        'area-life-u1',
      ]);
      expect(await h.outboxCount(), 0);
      expect((await h.db.getMeta()).tasksSeeded, isTrue);
    });

    test(
      'pull brought none → seeded locally once, pushed, never again',
      () async {
        await setOwner(h, 'u1');
        await h.engine.syncNow();
        final areas = await h.taskAreas.getAll();
        expect(areas.map((a) => a.code), ['KERJA', 'LIFE']);
        expect(areas.first.schedule, AreaSchedule.workHours);
        expect(await h.outboxCount(), 2);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.taskAreas]!.keys, {
          'area-kerjaan-u1',
          'area-life-u1',
        });
        // The user deletes both: they don't come back.
        h.tick();
        await h.deleteArea('area-kerjaan-u1');
        h.tick();
        await h.deleteArea('area-life-u1');
        await h.engine.syncNow();
        await h.engine.syncNow();
        expect(await h.taskAreas.getAll(), isEmpty);
      },
    );

    test(
      'an old server (no taskAreas key) → no seeding, local tasks kept',
      () async {
        await setOwner(h, 'u1');
        h.server.legacy = true;
        await h.engine.syncNow();
        expect(await h.taskAreas.getAll(), isEmpty);
        expect((await h.db.getMeta()).tasksSeeded, isFalse);

        // A full pull from an old server leaves unknown entities alone.
        await h.db
            .into(h.db.taskAreas)
            .insert(defaultTaskAreas('u1', h.clock.now()).first.toCompanion());
        await h.engine.resetLocalData();
        expect(
          await h.taskAreas.getAll(),
          isEmpty,
        ); // wiped by the reset itself
        await h.db
            .into(h.db.taskAreas)
            .insert(defaultTaskAreas('u1', h.clock.now()).first.toCompanion());
        await h.db.updateMeta(
          const SyncMetaCompanion(fullPullRequired: Value(true)),
        );
        await h.engine.syncNow();
        expect(await h.taskAreas.getAll(), hasLength(1));
      },
    );

    test(
      'a local seed never overwrites a server area the pull did not bring',
      () async {
        // Regression (upgrade from app v1.0.3): the device's cursor is past the
        // server's (web-edited) default area, so the pull brings nothing and
        // the device seeds its own copy with the same deterministic id.
        h.server.web(SyncEntity.taskAreas, 'area-kerjaan-u1', {
          'name': 'Kantor',
          'code': 'KANTOR',
          'color': '#123456',
          'icon': 'briefcase',
          'schedule': null,
          'sortOrder': 0,
          'archived': false,
        });
        await setOwner(h, 'u1');
        await h.db.updateMeta(
          SyncMetaCompanion(
            cursor: Value(
              h.clock.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
            ),
          ),
        );
        await h.engine.syncNow(); // pull: nothing → seeds locally
        expect(await h.outboxCount(), 2);
        await h.engine.syncNow(); // push: server's area wins, full pull
        await h.engine.syncNow();
        final server = h.server.rows[SyncEntity.taskAreas]!['area-kerjaan-u1']!;
        expect(server['name'], 'Kantor');
        expect(server['code'], 'KANTOR');
        expect((await h.taskAreas.getById('area-kerjaan-u1'))!.name, 'Kantor');
        expect(await h.outboxCount(), 0);
      },
    );

    test('SeedDefaultTaskAreas use case only when empty', () async {
      final seed = SeedDefaultTaskAreas(h.taskAreas, h.uow, h.clock);
      expect((await seed('u9')).valueOrThrow, 2);
      expect((await seed('u9')).valueOrThrow, 0);
    });
  });

  test('area code clash (duplicate): tasks move to the server area', () async {
    h.server.web(SyncEntity.taskAreas, 'srvKul', {
      'name': 'Kuliah',
      'code': 'KUL',
      'color': '#123456',
      'icon': 'book',
      'schedule': null,
      'sortOrder': 0,
      'archived': false,
    });
    // Offline device creates its own KUL area + a task in it.
    final local = await newArea('KUL');
    final t = await newTask(local, 'Tugas', bucket: TaskBucket.fire);
    await h.engine.syncNow(); // area → duplicate, task → rejected (area)
    await h.engine.syncNow(); // task re-pushed in the server's area
    expect(await h.taskAreas.getById(local), isNull);
    expect((await h.tasks.getById(t.id))!.areaId, 'srvKul');
    expect(h.server.rows[SyncEntity.tasks]![t.id]!['areaId'], 'srvKul');
    expect((await h.db.getMeta()).lastError, isNull);
  });

  group('transaction photos', () {
    Future<Transaction> expenseWithPhotos(List<String> paths) async {
      final w = await h.newWallet('Tunai', 100000);
      h.tick();
      return (await h.createTx(
        TransactionInput(
          type: TxType.expense,
          amount: 25000,
          walletId: w,
          date: h.clock.now(),
          photos: [for (final p in paths) TransactionPhoto.local(p)],
        ),
      )).valueOrThrow;
    }

    test(
      'offline photos upload before the push, list rewritten, files cleaned',
      () async {
        h.server.online = false;
        final t = await expenseWithPhotos(['/tmp/nota1.jpg', '/tmp/nota2.jpg']);
        expect(
          (await h.transactions.getById(
            t.id,
          ))!.photos.every((p) => p.isPending),
          isTrue,
        );
        await expectLater(h.engine.syncNow(), throwsA(isA<NetworkFailure>()));
        // Never pushed with local markers.
        expect(h.server.pushed, isEmpty);

        h.server.online = true;
        await h.engine.syncNow();
        final server = h.server.rows[SyncEntity.transactions]![t.id]!;
        expect(server['photos'], [
          '/uploads/0-nota1.jpg',
          '/uploads/1-nota2.jpg',
        ]);
        final local = (await h.transactions.getById(t.id))!;
        expect(local.photos, const [
          TransactionPhoto.remote('/uploads/0-nota1.jpg'),
          TransactionPhoto.remote('/uploads/1-nota2.jpg'),
        ]);
        expect(
          h.photos.deleted,
          containsAll(['/tmp/nota1.jpg', '/tmp/nota2.jpg']),
        );
        expect(await h.outboxCount(), 0);
      },
    );

    test(
      'a photo added to a synced transaction is uploaded and pushed',
      () async {
        final t = await expenseWithPhotos(const []);
        await h.engine.syncNow();
        h.tick();
        await h.addPhotos(t.id, ['/tmp/bukti.jpg']);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.transactions]![t.id]!['photos'], [
          '/uploads/0-bukti.jpg',
        ]);
        // Removing it pushes the shorter list.
        h.tick();
        await h.removePhoto(
          t.id,
          const TransactionPhoto.remote('/uploads/0-bukti.jpg'),
        );
        await h.engine.syncNow();
        expect(
          h.server.rows[SyncEntity.transactions]![t.id]!['photos'],
          isEmpty,
        );
        expect(h.server.rejected, isEmpty);
      },
    );

    test(
      'server rejects one file → that photo is dropped with an error',
      () async {
        h.server.uploadErrors['/tmp/huge.jpg'] = const ValidationFailure(
          'File too large',
        );
        final t = await expenseWithPhotos(['/tmp/ok.jpg', '/tmp/huge.jpg']);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.transactions]![t.id]!['photos'], [
          '/uploads/0-ok.jpg',
        ]);
        expect((await h.transactions.getById(t.id))!.photos, hasLength(1));
        expect((await h.db.getMeta()).lastError, contains('File too large'));
        expect(h.photos.deleted, contains('/tmp/huge.jpg'));
      },
    );

    test('a server error (5xx) keeps the photo pending and retries', () async {
      h.server.uploadErrors['/tmp/a.jpg'] = const UnknownFailure(
        'Server bermasalah (500)',
      );
      final t = await expenseWithPhotos(['/tmp/a.jpg']);
      await expectLater(h.engine.syncNow(), throwsA(isA<UnknownFailure>()));
      expect(
        (await h.transactions.getById(t.id))!.photos.single.isPending,
        isTrue,
      );
      expect(h.server.pushed, isEmpty);
      h.server.uploadErrors.clear();
      await h.engine.syncNow();
      expect(
        h.server.rows[SyncEntity.transactions]![t.id]!['photos'],
        hasLength(1),
      );
    });

    test('max 5 photos', () async {
      final t = await expenseWithPhotos([
        '/tmp/1.jpg',
        '/tmp/2.jpg',
        '/tmp/3.jpg',
      ]);
      final r = await h.addPhotos(t.id, [
        '/tmp/4.jpg',
        '/tmp/5.jpg',
        '/tmp/6.jpg',
      ]);
      expect(r.failureOrNull, isA<ValidationFailure>());
    });

    test(
      'pull: missing photos (old server) keeps the list; pending survive',
      () async {
        final t = await expenseWithPhotos(const []);
        await h.engine.syncNow();
        h.server.web(SyncEntity.transactions, t.id, {
          ...h.server.rows[SyncEntity.transactions]![t.id]!,
          'photos': ['/uploads/web.jpg'],
          'note': 'dari web',
        });
        await h.engine.syncNow();
        expect((await h.transactions.getById(t.id))!.photos, const [
          TransactionPhoto.remote('/uploads/web.jpg'),
        ]);

        // Old server: no `photos` key → stored list kept.
        h.server.legacy = true;
        h.server.web(SyncEntity.transactions, t.id, {
          ...h.server.rows[SyncEntity.transactions]![t.id]!,
          'note': 'lagi',
        });
        await h.engine.pullOnly();
        final local = (await h.transactions.getById(t.id))!;
        expect(local.note, 'lagi');
        expect(local.photos, const [
          TransactionPhoto.remote('/uploads/web.jpg'),
        ]);

        // A pending photo whose upsert is no longer queued survives a pull.
        await (h.db.update(
          h.db.transactions,
        )..where((x) => x.id.equals(t.id))).write(
          TransactionsCompanion(
            photos: Value(
              encodePhotos(const [
                TransactionPhoto.remote('/uploads/web.jpg'),
                TransactionPhoto.local('/tmp/late.jpg'),
              ]),
            ),
          ),
        );
        h.server.legacy = false;
        h.server.web(SyncEntity.transactions, t.id, {
          ...h.server.rows[SyncEntity.transactions]![t.id]!,
          'note': 'x',
        });
        await h.engine.pullOnly();
        expect(
          (await h.transactions.getById(t.id))!.photos.last,
          const TransactionPhoto.local('/tmp/late.jpg'),
        );
        // …and the next sync uploads it (queuing an upsert itself).
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.transactions]![t.id]!['photos'], [
          '/uploads/web.jpg',
          '/uploads/0-late.jpg',
        ]);
      },
    );

    test(
      'updating a transaction keeps its photos; deleting cleans local files',
      () async {
        h.server.online = false;
        final t = await expenseWithPhotos(['/tmp/keep.jpg']);
        h.tick();
        final u = (await h.updateTx(
          t.id,
          TransactionInput(
            type: TxType.expense,
            amount: 30000,
            walletId: t.walletId,
            date: t.date,
          ),
        )).valueOrThrow;
        expect(u.photos, const [TransactionPhoto.local('/tmp/keep.jpg')]);
        h.tick();
        await h.deleteTx(t.id);
        expect(h.photos.deleted, contains('/tmp/keep.jpg'));
      },
    );
  });

  group('watch streams (time-based)', () {
    test('board, focus and reminders follow the clock', () async {
      final kerja = await newArea('KERJA', schedule: AreaSchedule.workHours);
      final life = await newArea('LIFE');
      // Thu 2026-09-24 10:00 local.
      h.clock.current = DateTime(2026, 9, 24, 10);
      await newTask(
        kerja,
        'Revisi',
        bucket: TaskBucket.fire,
        due: DateTime(2026, 9, 24),
        time: '14:00',
        remindBefore: 30,
      );
      await newTask(life, 'Cuci baju', bucket: TaskBucket.should);
      await newTask(
        life,
        'Beli kado',
        bucket: TaskBucket.want,
        due: DateTime(2026, 9, 25),
      );

      Stream<DateTime> ticks() => Stream.value(h.clock.now());
      final focus = await WatchFocusAreas(h.taskAreas, ticks)().first;
      expect(focus.ids, [kerja]);
      expect(focus.bySchedule, isTrue);

      final board = await WatchTaskBoard(h.tasks, h.taskAreas, ticks)().first;
      expect(board.section(TaskBucket.fire).tasks.single.title, 'Revisi');
      expect(board.section(TaskBucket.should).isEmpty, isTrue);

      final all = await WatchTasks(h.tasks, h.taskAreas, ticks)(
        const TaskFilter(status: TaskStatusFilter.mepet),
      ).first;
      expect(all.single.title, 'Beli kado');
      expect(all.single.isMepet, isTrue);

      final reminders = await WatchReminders(
        h.tasks,
        h.taskAreas,
        ticks,
      )().first;
      expect(reminders.single.title, '[KERJA-FIRE] Revisi');
      expect(reminders.single.fireAt, DateTime(2026, 9, 24, 13, 30));

      // 18:00: work is over → unscheduled areas; the reminder is past; overdue.
      h.clock.current = DateTime(2026, 9, 24, 18);
      expect((await WatchFocusAreas(h.taskAreas, ticks)().first).ids, [life]);
      expect(
        await WatchReminders(h.tasks, h.taskAreas, ticks)().first,
        isEmpty,
      );
      final overdue = await WatchTasks(h.tasks, h.taskAreas, ticks)(
        const TaskFilter(status: TaskStatusFilter.overdue),
      ).first;
      expect(overdue.single.title, 'Revisi');

      // Sunday 09:00 → sapu bersih.
      h.clock.current = DateTime(2026, 9, 27, 9);
      final home = await WatchTaskHome(h.tasks, h.taskAreas, ticks)().first;
      expect(home.showSapuBersih, isTrue);
      expect(home.sapuBersih.single.title, 'Cuci baju');
      expect(home.fireTasks, isEmpty); // focus = LIFE, which has no FIRE task
      expect(home.overdueCount, 2);
    });

    test('streams re-emit on ticks only when something changed', () async {
      final a = await newArea('LIFE');
      h.clock.current = DateTime(2026, 9, 24, 10);
      await newTask(a, 'x', due: DateTime(2026, 9, 24), time: '10:30');
      final ticks = StreamController<DateTime>();
      addTearDown(ticks.close);
      final out = <List<TaskView>>[];
      final sub = WatchTasks(h.tasks, h.taskAreas, () => ticks.stream)(
        const TaskFilter(status: TaskStatusFilter.all),
      ).listen(out.add);
      addTearDown(sub.cancel);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 20));
      ticks.add(DateTime(2026, 9, 24, 10));
      await settle();
      ticks.add(DateTime(2026, 9, 24, 10, 1)); // nothing changes → no emission
      await settle();
      expect(out, hasLength(1));
      expect(out.first.single.isOverdue, isFalse);
      ticks.add(DateTime(2026, 9, 24, 10, 31)); // now overdue
      await settle();
      expect(out, hasLength(2));
      expect(out.last.single.isOverdue, isTrue);
    });

    test('dateKey sanity for due dates', () {
      expect(dateKey(DateTime(2026, 9, 24, 23, 59)), '2026-09-24');
    });
  });
}
