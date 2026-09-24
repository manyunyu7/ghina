import 'package:drift/drift.dart';

import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import 'outbox.dart';

/// The contract's delete relations, applied to the local database (for local deletes
/// and for pulled tombstones). Cascaded changes are **not** queued: the server applies
/// the same cascade itself. Queued mutations of affected rows are adjusted so they
/// don't reference the deleted row.
class LocalCascades {
  LocalCascades(this._db, this._outbox);

  final AppDatabase _db;
  final Outbox _outbox;

  /// Wallet deleted → its transactions (either side) deleted; subscriptions/planned
  /// and tasks get `walletId = null` (tasks also lose links to those transactions).
  Future<void> walletDeleted(String walletId) async {
    final txs =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.walletId.equals(walletId) | t.toWalletId.equals(walletId),
            ))
            .get();
    for (final t in txs) {
      await (_db.delete(
        _db.transactions,
      )..where((x) => x.id.equals(t.id))).go();
      await _outbox.dropQueued(SyncEntity.transactions, t.id);
    }
    final subs = await (_db.select(
      _db.subscriptions,
    )..where((s) => s.walletId.equals(walletId))).get();
    for (final s in subs) {
      await (_db.update(_db.subscriptions)..where((x) => x.id.equals(s.id)))
          .write(const SubscriptionsCompanion(walletId: Value(null)));
      await _outbox.patchQueued(SyncEntity.subscriptions, s.id, {
        'walletId': null,
      });
    }
    final planned = await (_db.select(
      _db.planned,
    )..where((p) => p.walletId.equals(walletId))).get();
    for (final p in planned) {
      await (_db.update(_db.planned)..where((x) => x.id.equals(p.id))).write(
        const PlannedCompanion(walletId: Value(null)),
      );
      await _outbox.patchQueued(SyncEntity.planned, p.id, {'walletId': null});
    }
    for (final t in txs) {
      await transactionDeleted(t.id);
    }
    await _nullTaskRef(_db.tasks.walletId, 'walletId', walletId);
  }

  /// Transaction deleted → tasks get `transactionId = null`.
  Future<void> transactionDeleted(String transactionId) =>
      _nullTaskRef(_db.tasks.transactionId, 'transactionId', transactionId);

  /// Task area deleted → its tasks are deleted (the server tombstones them).
  Future<void> taskAreaDeleted(String areaId) async {
    final tasks = await (_db.select(
      _db.tasks,
    )..where((t) => t.areaId.equals(areaId))).get();
    for (final t in tasks) {
      await (_db.delete(_db.tasks)..where((x) => x.id.equals(t.id))).go();
      await _outbox.dropQueued(SyncEntity.tasks, t.id);
    }
  }

  Future<void> _nullTaskRef(
    GeneratedColumn<String> column,
    String field,
    String id,
  ) async {
    final rows = await (_db.select(
      _db.tasks,
    )..where((_) => column.equals(id))).get();
    for (final t in rows) {
      await (_db.update(_db.tasks)..where((x) => x.id.equals(t.id))).write(
        TasksCompanion.custom(
          walletId: field == 'walletId' ? const Constant(null) : null,
          categoryId: field == 'categoryId' ? const Constant(null) : null,
          transactionId: field == 'transactionId' ? const Constant(null) : null,
        ),
      );
      await _outbox.patchQueued(SyncEntity.tasks, t.id, {field: null});
    }
  }

  /// Category deleted → transactions/subscriptions/planned/tasks get
  /// `categoryId = null`; its budgets are deleted.
  Future<void> categoryDeleted(String categoryId) async {
    final txs = await (_db.select(
      _db.transactions,
    )..where((t) => t.categoryId.equals(categoryId))).get();
    for (final t in txs) {
      await (_db.update(_db.transactions)..where((x) => x.id.equals(t.id)))
          .write(const TransactionsCompanion(categoryId: Value(null)));
      await _outbox.patchQueued(SyncEntity.transactions, t.id, {
        'categoryId': null,
      });
    }
    final subs = await (_db.select(
      _db.subscriptions,
    )..where((s) => s.categoryId.equals(categoryId))).get();
    for (final s in subs) {
      await (_db.update(_db.subscriptions)..where((x) => x.id.equals(s.id)))
          .write(const SubscriptionsCompanion(categoryId: Value(null)));
      await _outbox.patchQueued(SyncEntity.subscriptions, s.id, {
        'categoryId': null,
      });
    }
    final planned = await (_db.select(
      _db.planned,
    )..where((p) => p.categoryId.equals(categoryId))).get();
    for (final p in planned) {
      await (_db.update(_db.planned)..where((x) => x.id.equals(p.id))).write(
        const PlannedCompanion(categoryId: Value(null)),
      );
      await _outbox.patchQueued(SyncEntity.planned, p.id, {'categoryId': null});
    }
    final budgets = await (_db.select(
      _db.budgets,
    )..where((b) => b.categoryId.equals(categoryId))).get();
    for (final b in budgets) {
      await (_db.delete(_db.budgets)..where((x) => x.id.equals(b.id))).go();
      await _outbox.dropQueued(SyncEntity.budgets, b.id);
    }
    await _nullTaskRef(_db.tasks.categoryId, 'categoryId', categoryId);
  }
}
