import 'package:drift/drift.dart' show Value;
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../harness.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.close());

  TransactionInput tx(
    String walletId,
    double amount, {
    TxType type = TxType.expense,
    String? to,
    String? categoryId,
  }) => TransactionInput(
    type: type,
    amount: amount,
    walletId: walletId,
    toWalletId: to,
    categoryId: categoryId,
    date: h.clock.now(),
  );

  group('offline first', () {
    test(
      'create offline → queued, balance updated locally → pushed when online',
      () async {
        h.server.online = false;
        final w = await h.newWallet('Dompet', 100000);
        h.tick();
        await h.createTx(tx(w, 25000));

        expect((await h.wallet(w)).balance, 75000);
        expect((await h.wallet(w)).syncedBalance, 100000);
        expect(await h.outboxCount(), 2);

        await expectLater(h.engine.syncNow(), throwsA(isA<NetworkFailure>()));
        final offline = await h.engine.watchStatus().first;
        expect(offline.phase, SyncPhase.offline);
        expect(offline.pendingCount, 2);

        h.server.online = true;
        await h.engine.syncNow();

        expect(h.server.rows[SyncEntity.wallets]!.containsKey(w), isTrue);
        expect(h.server.rows[SyncEntity.transactions]!.length, 1);
        expect(h.server.balanceOf(w), 75000);
        expect(await h.outboxCount(), 0);
        final after = await h.wallet(w);
        expect(after.balance, 75000);
        expect(after.syncedBalance, 75000);
        final status = await h.engine.watchStatus().first;
        expect(status.phase, SyncPhase.idle);
        expect(status.pendingCount, 0);
        expect(status.lastSyncAt, isNotNull);
      },
    );

    test(
      'wallet mutations are pushed before the transactions that reference them',
      () async {
        final w = await h.newWallet('A', 0);
        h.tick();
        await h.createTx(tx(w, 1000, type: TxType.income));
        h.tick();
        // Renaming the wallet moves its outbox entry after the transaction.
        await h.updateWallet(w, const WalletInput(name: 'A2'));
        await h.engine.syncNow();
        expect(h.server.pushed.first.entity, SyncEntity.wallets);
        expect(h.server.rows[SyncEntity.wallets]![w]!['name'], 'A2');
        expect(h.server.balanceOf(w), 1000);
      },
    );
  });

  group('balances', () {
    test('transfer edits and deletes with pending mutations', () async {
      final a = await h.newWallet('A', 100000);
      final b = await h.newWallet('B', 50000);
      final c = await h.newWallet('C', 0);
      h.tick();
      final t = (await h.createTx(
        tx(a, 30000, type: TxType.transfer, to: b),
      )).valueOrThrow;
      await h.engine.syncNow();
      expect(h.server.balanceOf(a), 70000);
      expect(h.server.balanceOf(b), 80000);
      expect((await h.wallet(a)).balance, 70000);
      expect((await h.wallet(b)).balance, 80000);

      // Offline: redirect the transfer to C with a smaller amount.
      h.server.online = false;
      h.tick();
      await h.updateTx(t.id, tx(a, 10000, type: TxType.transfer, to: c));
      expect((await h.wallet(a)).balance, 90000);
      expect((await h.wallet(b)).balance, 50000);
      expect((await h.wallet(c)).balance, 10000);

      // A pull while the edit is pending doesn't move displayed balances.
      h.server.online = true;
      await h.engine.pullOnly();
      expect((await h.wallet(a)).balance, 90000);
      expect((await h.wallet(b)).balance, 50000);
      expect((await h.wallet(c)).balance, 10000);
      expect((await h.wallet(a)).syncedBalance, 70000);

      // Edit again then delete: collapses into a single delete of the server row.
      h.tick();
      await h.updateTx(t.id, tx(a, 5000, type: TxType.transfer, to: c));
      expect((await h.wallet(a)).balance, 95000);
      h.tick();
      await h.deleteTx(t.id);
      expect(await h.outboxCount(), 1);
      expect((await h.wallet(a)).balance, 100000);
      expect((await h.wallet(b)).balance, 50000);
      expect((await h.wallet(c)).balance, 0);

      await h.engine.syncNow();
      expect(h.server.balanceOf(a), 100000);
      expect(h.server.balanceOf(b), 50000);
      expect(h.server.balanceOf(c), 0);
      for (final id in [a, b, c]) {
        final w = await h.wallet(id);
        expect(w.balance, w.syncedBalance);
        expect(w.balance, h.server.balanceOf(id));
      }
    });

    test(
      'an edit queued while the previous version is in flight chains correctly',
      () async {
        final a = await h.newWallet('A', 1000);
        await h.engine.syncNow();
        h.tick();
        final t = (await h.createTx(tx(a, 100))).valueOrThrow;
        // Simulate a push in progress.
        final batch = await h.outbox.takeBatch();
        expect(batch, hasLength(1));
        h.tick();
        await h.updateTx(t.id, tx(a, 300));
        expect(await h.outboxCount(), 2);
        expect((await h.wallet(a)).balance, 700);
        await h.outbox
            .recoverInFlight(); // "crash": follower supersedes the stale entry
        expect(await h.outboxCount(), 1);
        expect((await h.wallet(a)).balance, 700);
        await h.engine.syncNow();
        expect(h.server.balanceOf(a), 700);
        expect((await h.wallet(a)).syncedBalance, 700);
      },
    );

    test(
      'deleting a wallet deletes its transfers without reversing the other side',
      () async {
        final a = await h.newWallet('A', 100);
        final b = await h.newWallet('B', 0);
        h.tick();
        await h.createTx(tx(a, 40, type: TxType.transfer, to: b));
        await h.engine.syncNow();
        h.tick();
        await h.deleteWallet(b);
        expect(await h.transactions.list(), isEmpty);
        expect((await h.wallet(a)).balance, 60);
        await h.engine.syncNow();
        expect(h.server.balanceOf(a), 60);
        expect(h.server.rows[SyncEntity.transactions], isEmpty);
      },
    );
  });

  group('outbox collapsing', () {
    test(
      'upserts collapse; create+delete vanishes; update+delete becomes delete',
      () async {
        h.tick();
        final c = (await h.createCategory(
          const CategoryInput(name: 'Makan'),
        )).valueOrThrow;
        h.tick();
        await h.updateCategory(c.id, const CategoryInput(name: 'Makan 2'));
        h.tick();
        await h.updateCategory(c.id, const CategoryInput(name: 'Makan 3'));
        var all = await h.outbox.all();
        expect(all, hasLength(1));
        expect(all.single.op, 'upsert');
        expect(all.single.isCreate, isTrue);
        expect(all.single.data, contains('Makan 3'));

        h.tick();
        await h.deleteCategory(c.id);
        expect(await h.outboxCount(), 0);

        h.tick();
        final d = (await h.createCategory(
          const CategoryInput(name: 'Gaji'),
        )).valueOrThrow;
        await h.engine.syncNow();
        h.tick();
        await h.updateCategory(d.id, const CategoryInput(name: 'Gaji 2'));
        h.tick();
        await h.deleteCategory(d.id);
        all = await h.outbox.all();
        expect(all, hasLength(1));
        expect(all.single.op, 'delete');
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.categories], isEmpty);
      },
    );

    test('a delete after an in-flight create is still sent', () async {
      h.tick();
      final c = (await h.createCategory(
        const CategoryInput(name: 'X'),
      )).valueOrThrow;
      await h.outbox.takeBatch();
      h.tick();
      await h.deleteCategory(c.id);
      final all = await h.outbox.all();
      expect(all.map((e) => e.op), ['upsert', 'delete']);
    });
  });

  group('pull', () {
    void seedServer() {
      h.server.web(SyncEntity.wallets, 'w1', {
        'name': 'Bank',
        'type': 'bank',
        'balance': 500,
        'currency': 'IDR',
        'color': '#6366f1',
        'icon': 'bank',
        'archived': false,
      });
      h.server.web(SyncEntity.categories, 'c1', {
        'name': 'Food',
        'type': 'expense',
        'color': '#f97316',
        'icon': 'utensils',
      });
      h.server.web(SyncEntity.transactions, 't1', {
        'walletId': 'w1',
        'toWalletId': null,
        'categoryId': 'c1',
        'type': 'expense',
        'amount': 120,
        'note': 'Nasi',
        'date': '2026-09-20T05:00:00.000Z',
      });
      h.server.web(SyncEntity.prayers, 'p1', {
        'date': '2026-09-22',
        'prayer': 'subuh',
      });
    }

    Future<String> snapshot() async => [
      await h.wallets.getAll(),
      await h.categories.getAll(),
      await h.transactions.list(),
    ].toString();

    test('is idempotent (rows arriving twice / full re-pull)', () async {
      seedServer();
      await h.engine.syncNow();
      final first = await snapshot();
      expect((await h.wallet('w1')).balance, 380);
      await h.engine.syncNow(); // overlapping window re-sends nothing new
      expect(await snapshot(), first);
      await h.db.updateMeta(
        const SyncMetaCompanion(fullPullRequired: Value(true)),
      );
      await h.engine.syncNow();
      expect(await snapshot(), first);
      expect(await h.outboxCount(), 0);
    });

    test('does not clobber rows with pending mutations', () async {
      seedServer();
      await h.engine.syncNow();

      h.tick();
      await h.updateCategory(
        'c1',
        const CategoryInput(name: 'Makan', icon: 'utensils'),
      );
      h.tick();
      await h.updateWallet(
        'w1',
        const WalletInput(name: 'Bank Lokal', type: WalletType.bank),
      );

      h.server.web(SyncEntity.categories, 'c1', {
        'name': 'Food (web)',
        'type': 'expense',
        'color': '#f97316',
        'icon': 'utensils',
      });
      h.server.web(SyncEntity.transactions, 't2', {
        'walletId': 'w1',
        'toWalletId': null,
        'categoryId': null,
        'type': 'income',
        'amount': 1000,
        'note': null,
        'date': '2026-09-21T05:00:00.000Z',
      });
      await h.engine.pullOnly();

      expect((await h.categories.getById('c1'))!.name, 'Makan');
      final w = await h.wallet('w1');
      expect(w.name, 'Bank Lokal'); // local edit kept
      expect(w.syncedBalance, 1380); // server balance still applied
      expect(w.balance, 1380);
      expect(await h.transactions.getById('t2'), isNotNull);

      await h.engine.syncNow();
      expect(h.server.rows[SyncEntity.categories]!['c1']!['name'], 'Makan');
      expect(h.server.rows[SyncEntity.wallets]!['w1']!['name'], 'Bank Lokal');
      expect(h.server.balanceOf('w1'), 1380);
    });

    test('tombstones apply the delete cascades locally', () async {
      seedServer();
      h.server.web(SyncEntity.wallets, 'w2', {
        'name': 'Cash',
        'type': 'cash',
        'balance': 0,
        'currency': 'IDR',
        'color': '#6366f1',
        'icon': 'cash',
        'archived': false,
      });
      h.server.web(SyncEntity.transactions, 't9', {
        'walletId': 'w2',
        'toWalletId': 'w1',
        'categoryId': null,
        'type': 'transfer',
        'amount': 50,
        'note': null,
        'date': '2026-09-20T05:00:00.000Z',
      });
      h.server.web(SyncEntity.subscriptions, 's1', {
        'name': 'Netflix',
        'amount': 54000,
        'currency': 'IDR',
        'cycle': 'monthly',
        'nextBilling': '2026-10-01T00:00:00.000Z',
        'categoryId': 'c1',
        'walletId': 'w1',
        'color': '#E50914',
        'icon': 'tv',
        'note': null,
        'active': true,
      });
      h.server.web(SyncEntity.planned, 'pl1', {
        'type': 'expense',
        'amount': 10,
        'note': null,
        'categoryId': 'c1',
        'walletId': 'w1',
        'date': '2026-10-05T00:00:00.000Z',
        'done': false,
      });
      h.server.web(SyncEntity.budgets, 'b1', {
        'categoryId': 'c1',
        'amount': 1000,
        'month': 9,
        'year': 2026,
      });
      await h.engine.syncNow();
      expect((await h.wallet('w1')).balance, 430);

      h.server.webDelete(SyncEntity.wallets, 'w1');
      h.server.webDelete(SyncEntity.categories, 'c1');
      await h.engine.syncNow();

      expect(await h.wallets.getById('w1'), isNull);
      expect(await h.categories.getById('c1'), isNull);
      expect(
        await h.transactions.list(),
        isEmpty,
      ); // t1 and transfer t9 both gone
      expect((await h.wallet('w2')).balance, -50); // not reversed
      final s = (await h.subscriptions.getById('s1'))!;
      expect(s.walletId, isNull);
      expect(s.categoryId, isNull);
      final p = (await h.planned.getById('pl1'))!;
      expect(p.walletId, isNull);
      expect(p.categoryId, isNull);
      expect(await h.budgets.getById('b1'), isNull);
    });

    test(
      'a tombstone for a row with a pending local edit is not applied',
      () async {
        seedServer();
        await h.engine.syncNow();
        h.server.online = false;
        h.tick();
        await h.updateCategory(
          'c1',
          const CategoryInput(name: 'Masih ada', icon: 'utensils'),
        );
        h.server.online = true;
        h.server.webDelete(SyncEntity.categories, 'c1');
        await h.engine.pullOnly();
        expect((await h.categories.getById('c1'))!.name, 'Masih ada');
      },
    );
  });

  group('epochs', () {
    test(
      'push refused with a new epoch → wipe local data and outbox, full pull',
      () async {
        final w = await h.newWallet('A', 100);
        h.server.web(SyncEntity.subscriptions, 's1', {
          'name': 'Spotify',
          'amount': 55000,
          'currency': 'IDR',
          'cycle': 'monthly',
          'nextBilling': '2026-10-01T00:00:00.000Z',
          'categoryId': null,
          'walletId': null,
          'color': '#1DB954',
          'icon': 'music',
          'note': null,
          'active': true,
        });
        await h.engine.syncNow();
        h.server.webReset();
        h.tick();
        await h.createTx(tx(w, 10)); // pending, must not resurrect anything

        await h.engine.syncNow();
        expect(await h.wallets.getAll(), isEmpty);
        expect(await h.transactions.list(), isEmpty);
        expect(await h.outboxCount(), 0);
        expect(h.server.rows[SyncEntity.transactions], isEmpty);
        expect(await h.subscriptions.getAll(), hasLength(1));
        expect((await h.db.getMeta()).epoch, h.server.epoch);
      },
    );

    test('pull with a different epoch → wipe and full re-pull', () async {
      await h.newWallet('A', 100);
      await h.engine.syncNow();
      h.server.webReset();
      h.server.web(SyncEntity.categories, 'c-new', {
        'name': 'Baru',
        'type': 'expense',
        'color': '#f97316',
        'icon': 'circle',
      });
      await h.engine.pullOnly();
      expect(await h.wallets.getAll(), isEmpty);
      expect((await h.categories.getAll()).map((c) => c.id), ['c-new']);
    });
  });

  test('duplicate prayer: local row replaced by the server row', () async {
    await h.engine.syncNow();
    h.server.web(SyncEntity.prayers, 'server-p', {
      'date': '2026-09-23',
      'prayer': 'subuh',
    });
    final done = (await h.togglePrayer(
      DateTime(2026, 9, 23),
      Prayer.subuh,
    )).valueOrThrow;
    expect(done, isTrue);

    await h.engine.syncNow();
    final entries = await h.prayers
        .watchRange('2026-09-23', '2026-09-23')
        .first;
    expect(entries, hasLength(1));
    expect(entries.single.id, 'server-p');
    expect(await h.outboxCount(), 0);
    expect(h.server.rows[SyncEntity.prayers], hasLength(1));
  });

  group('rejected mutations', () {
    test(
      'rejected create is dropped locally and surfaced as an error',
      () async {
        final w = await h.newWallet('A', 100);
        await h.engine.syncNow();
        h.server.webDelete(
          SyncEntity.wallets,
          w,
        ); // deleted on the web meanwhile
        h.tick();
        await h.createTx(tx(w, 10));

        await h.engine.syncNow();
        expect(await h.transactions.list(), isEmpty);
        expect(await h.wallets.getById(w), isNull); // tombstone pulled
        expect(await h.outboxCount(), 0);
        final status = await h.engine.watchStatus().first;
        expect(status.lastError, contains('Wallet not found'));
      },
    );

    test(
      'rejected update is reverted to the server version on the next pull',
      () async {
        h.server.web(SyncEntity.categories, 'c1', {
          'name': 'Food',
          'type': 'expense',
          'color': '#f97316',
          'icon': 'utensils',
        });
        await h.engine.syncNow();
        h.server.rejectIds.add('c1');
        h.tick();
        await h.updateCategory(
          'c1',
          const CategoryInput(name: 'Lokal', icon: 'utensils'),
        );
        await h.engine.syncNow();
        expect((await h.categories.getById('c1'))!.name, 'Food');
        expect(
          (await h.engine.watchStatus().first).lastError,
          contains('Nope'),
        );

        h.server.rejectIds.clear();
        await h.engine.syncNow();
        expect((await h.engine.watchStatus().first).lastError, isNull);
      },
    );
  });

  test('food photo taken offline is uploaded before the upsert', () async {
    h.server.online = false;
    final log = (await h.createFood(
      FoodInput(
        date: h.clock.now(),
        name: 'Soto',
        meal: MealType.lunch,
        calories: 420.4,
      ),
      photoPath: '/tmp/soto.jpg',
    )).valueOrThrow;
    final local = (await h.food.getById(log.id))!;
    expect(local.localPhotoPath, '/tmp/soto.jpg');
    expect(local.photoUrl, isNull);
    expect(local.calories, 420);

    h.server.online = true;
    await h.engine.syncNow();
    expect(h.server.uploads, ['/tmp/soto.jpg']);
    final serverRow = h.server.rows[SyncEntity.food]![log.id]!;
    expect(serverRow['photoUrl'], startsWith('/uploads/'));
    final after = (await h.food.getById(log.id))!;
    expect(after.localPhotoPath, isNull);
    expect(after.photoUrl, serverRow['photoUrl']);
    expect(h.photos.deleted, contains('/tmp/soto.jpg'));
  });

  test('sync is single-flight', () async {
    await h.newWallet('A', 1);
    await Future.wait([
      h.engine.syncNow(),
      h.engine.syncNow(),
      h.engine.syncNow(),
    ]);
    // One running sync + at most one follow-up round.
    expect(h.server.pullCount, lessThanOrEqualTo(2));
    expect(h.server.rows[SyncEntity.wallets], hasLength(1));
  });

  test('budgets: server duplicate key replaces the local row', () async {
    h.server.web(SyncEntity.categories, 'c1', {
      'name': 'Food',
      'type': 'expense',
      'color': '#f97316',
      'icon': 'utensils',
    });
    await h.engine.syncNow();
    h.server.web(SyncEntity.budgets, 'sb', {
      'categoryId': 'c1',
      'amount': 700,
      'month': 9,
      'year': 2026,
    });
    h.tick();
    await SetBudget(h.budgets, h.categories, h.clock)(
      categoryId: 'c1',
      amount: 500,
      month: const YearMonth(2026, 9),
    );
    await h.engine.syncNow();
    final b = (await h.budgets.findByKey('c1', const YearMonth(2026, 9)))!;
    expect(b.id, 'sb');
    expect(b.amount, 700);
  });
}
