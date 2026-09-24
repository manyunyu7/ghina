import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/mappers.dart';
import '../models/wire.dart';
import 'local_store.dart';
import 'photo_store.dart';

class DriftWalletRepository implements WalletRepository {
  DriftWalletRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  Future<List<Wallet>> _load({bool includeArchived = true, String? id}) async {
    final q = _db.select(_db.wallets)
      ..orderBy([
        (w) => OrderingTerm.asc(w.createdAt),
        (w) => OrderingTerm.asc(w.name),
      ]);
    if (!includeArchived) q.where((w) => w.archived.equals(false));
    if (id != null) q.where((w) => w.id.equals(id));
    final rows = await q.get();
    final fx = await _s.outbox.pendingBalanceEffects();
    return [for (final r in rows) r.toEntity(pendingDelta: fx[r.id] ?? 0)];
  }

  @override
  Stream<List<Wallet>> watchAll({bool includeArchived = true}) =>
      _db.watchTables([
        _db.wallets,
        _db.outbox,
      ], () => _load(includeArchived: includeArchived));

  @override
  Future<List<Wallet>> getAll({bool includeArchived = true}) =>
      _load(includeArchived: includeArchived);

  @override
  Stream<Wallet?> watchById(String id) => _db.watchTables([
    _db.wallets,
    _db.outbox,
  ], () async => (await _load(id: id)).firstOrNull);

  @override
  Future<Wallet?> getById(String id) async => (await _load(id: id)).firstOrNull;

  @override
  Future<void> save(Wallet wallet) => _s.write(() async {
    final existing = await (_db.select(
      _db.wallets,
    )..where((w) => w.id.equals(wallet.id))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.wallets).insert(wallet.toCompanion());
    } else {
      // Balance is server-authoritative: never overwritten by a local edit.
      await (_db.update(_db.wallets)..where((w) => w.id.equals(wallet.id)))
          .write(wallet.toCompanion().copyWith(balance: const Value.absent()));
    }
    final data = walletToWire(
      existing == null
          ? wallet
          : wallet.copyWith(syncedBalance: existing.balance),
    );
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.wallets,
      entityId: wallet.id,
      data: data,
      clientUpdatedAt: wallet.updatedAt,
      isCreate: existing == null,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.wallets,
    )..where((w) => w.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.walletDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.wallets,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$CategoriesTable, CategoryRow> _q({
    CategoryType? type,
  }) {
    final q = _db.select(_db.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.name.lower())]);
    if (type != null) q.where((c) => c.type.equals(type.wire));
    return q;
  }

  @override
  Stream<List<TxCategory>> watchAll({CategoryType? type}) =>
      _q(type: type).watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<TxCategory>> getAll({CategoryType? type}) async => [
    for (final x in await _q(type: type).get()) x.toEntity(),
  ];

  @override
  Stream<TxCategory?> watchById(String id) =>
      (_db.select(_db.categories)..where((c) => c.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<TxCategory?> getById(String id) async => (await (_db.select(
    _db.categories,
  )..where((c) => c.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(TxCategory category) => _s.write(() async {
    final exists = await getById(category.id) != null;
    await _db
        .into(_db.categories)
        .insertOnConflictUpdate(category.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.categories,
      entityId: category.id,
      data: categoryToWire(category),
      clientUpdatedAt: category.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.categories,
    )..where((c) => c.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.categoryDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.categories,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftTransactionRepository implements TransactionRepository {
  /// [photos] keeps pending photo files (default: files are used where they are).
  DriftTransactionRepository(this._s, [PhotoStore? photos])
    : _photos = photos ?? InMemoryPhotoStore();
  final LocalStore _s;
  final PhotoStore _photos;
  AppDatabase get _db => _s.db;

  static Set<String> _localPaths(Iterable<TransactionPhoto> photos) => {
    for (final p in photos)
      if (p.isPending) p.localPath!,
  };

  SimpleSelectStatement<$TransactionsTable, TransactionRow> _q({
    DateTime? from,
    DateTime? to,
    TxType? type,
    String? walletId,
    String? categoryId,
    int? limit,
  }) {
    final q = _db.select(_db.transactions)
      ..orderBy([
        (t) => OrderingTerm.desc(t.date),
        (t) => OrderingTerm.desc(t.createdAt),
      ])
      // Rows of a type this version doesn't know (newer server) are skipped.
      ..where((t) => t.type.isIn([for (final x in TxType.values) x.wire]));
    if (from != null) {
      q.where((t) => t.date.isBiggerOrEqualValue(from.millisecondsSinceEpoch));
    }
    if (to != null) {
      q.where((t) => t.date.isSmallerOrEqualValue(to.millisecondsSinceEpoch));
    }
    if (type != null) q.where((t) => t.type.equals(type.wire));
    if (walletId != null) {
      q.where(
        (t) => t.walletId.equals(walletId) | t.toWalletId.equals(walletId),
      );
    }
    if (categoryId != null) q.where((t) => t.categoryId.equals(categoryId));
    if (limit != null) q.limit(limit);
    return q;
  }

  @override
  Stream<List<Transaction>> watch({
    DateTime? from,
    DateTime? to,
    TxType? type,
    String? walletId,
    String? categoryId,
    int? limit,
  }) => _q(
    from: from,
    to: to,
    type: type,
    walletId: walletId,
    categoryId: categoryId,
    limit: limit,
  ).watch().map((r) => r.toEntities());

  @override
  Future<List<Transaction>> list({
    DateTime? from,
    DateTime? to,
    TxType? type,
  }) async => (await _q(from: from, to: to, type: type).get()).toEntities();

  @override
  Stream<Transaction?> watchById(String id) =>
      (_db.select(_db.transactions)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntityOrNull());

  @override
  Future<Transaction?> getById(String id) async => (await (_db.select(
    _db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<void> save(Transaction t) async {
    final before = await getById(t.id);
    final oldLocal = _localPaths(before?.photos ?? const []);
    // Copy newly picked files into app storage (file IO, outside the DB transaction).
    var row = t;
    if (t.photos.any((p) => p.isPending && !oldLocal.contains(p.localPath))) {
      row = t.withPhotos([
        for (final p in t.photos)
          p.isPending && !oldLocal.contains(p.localPath)
              ? TransactionPhoto.local(
                  await _photos.ensureStored(p.localPath!, t.id),
                )
              : p,
      ]);
    }
    await _s.write(() async {
      final existing = await getById(row.id);
      await _db
          .into(_db.transactions)
          .insertOnConflictUpdate(row.toCompanion());
      await _s.outbox.enqueueUpsert(
        entity: SyncEntity.transactions,
        entityId: row.id,
        data: transactionToWire(row),
        clientUpdatedAt: row.updatedAt,
        isCreate: existing == null,
        base: existing == null ? null : transactionToWire(existing),
      );
    });
    final keep = _localPaths(row.photos);
    for (final path in oldLocal.difference(keep)) {
      await _photos.delete(path);
    }
  }

  @override
  Future<void> delete(String id) async {
    final existing = await getById(id);
    if (existing == null) return;
    await _s.write(() async {
      final n = await (_db.delete(
        _db.transactions,
      )..where((t) => t.id.equals(id))).go();
      if (n == 0) return;
      await _s.cascades.transactionDeleted(id);
      await _s.outbox.enqueueDelete(
        entity: SyncEntity.transactions,
        entityId: id,
        clientUpdatedAt: _s.clock.now(),
        base: transactionToWire(existing),
      );
    });
    for (final path in _localPaths(existing.photos)) {
      await _photos.delete(path);
    }
  }
}

class DriftBudgetRepository implements BudgetRepository {
  DriftBudgetRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<Budget>> watchByMonth(YearMonth month) =>
      (_db.select(_db.budgets)..where(
            (b) => b.month.equals(month.month) & b.year.equals(month.year),
          ))
          .watch()
          .map((r) => [for (final x in r) x.toEntity()]);

  @override
  Stream<List<Budget>> watchAll() => _db
      .select(_db.budgets)
      .watch()
      .map((r) => [for (final x in r) x.toEntity()]);

  @override
  Stream<Budget?> watchById(String id) =>
      (_db.select(_db.budgets)..where((b) => b.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<Budget?> getById(String id) async => (await (_db.select(
    _db.budgets,
  )..where((b) => b.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<Budget?> findByKey(String categoryId, YearMonth month) async =>
      (await (_db.select(_db.budgets)..where(
                (b) =>
                    b.categoryId.equals(categoryId) &
                    b.month.equals(month.month) &
                    b.year.equals(month.year),
              ))
              .getSingleOrNull())
          ?.toEntity();

  @override
  Future<void> save(Budget budget) => _s.write(() async {
    final exists = await getById(budget.id) != null;
    await _db.into(_db.budgets).insertOnConflictUpdate(budget.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.budgets,
      entityId: budget.id,
      data: budgetToWire(budget),
      clientUpdatedAt: budget.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.budgets,
    )..where((b) => b.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.budgets,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftSubscriptionRepository implements SubscriptionRepository {
  DriftSubscriptionRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$SubscriptionsTable, SubscriptionRow> get _all =>
      _db.select(_db.subscriptions)
        ..orderBy([(s) => OrderingTerm.asc(s.nextBilling)]);

  @override
  Stream<List<Subscription>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<Subscription>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Stream<Subscription?> watchById(String id) =>
      (_db.select(_db.subscriptions)..where((s) => s.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<Subscription?> getById(String id) async => (await (_db.select(
    _db.subscriptions,
  )..where((s) => s.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(Subscription s) => _s.write(() async {
    final exists = await getById(s.id) != null;
    await _db.into(_db.subscriptions).insertOnConflictUpdate(s.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.subscriptions,
      entityId: s.id,
      data: subscriptionToWire(s),
      clientUpdatedAt: s.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.subscriptions,
    )..where((s) => s.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.subscriptions,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftPlannedRepository implements PlannedRepository {
  DriftPlannedRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  @override
  Stream<List<PlannedTransaction>> watchRange(DateTime from, DateTime to) =>
      (_db.select(_db.planned)
            ..where(
              (p) => p.date.isBetweenValues(
                from.millisecondsSinceEpoch,
                to.millisecondsSinceEpoch,
              ),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.date)]))
          .watch()
          .map((r) => [for (final x in r) x.toEntity()]);

  @override
  Stream<PlannedTransaction?> watchById(String id) =>
      (_db.select(_db.planned)..where((p) => p.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<PlannedTransaction?> getById(String id) async => (await (_db.select(
    _db.planned,
  )..where((p) => p.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(PlannedTransaction item) => _s.write(() async {
    final exists = await getById(item.id) != null;
    await _db.into(_db.planned).insertOnConflictUpdate(item.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.planned,
      entityId: item.id,
      data: plannedToWire(item),
      clientUpdatedAt: item.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.planned,
    )..where((p) => p.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.planned,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}
