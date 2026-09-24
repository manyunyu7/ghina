import 'dart:convert';

import 'package:drift/drift.dart';

import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/notes_content_mappers.dart';
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

  /// Transaction deleted → tasks get `transactionId = null`, notes
  /// `linkedTransactionId = null`, sponsors `transactionId = null`.
  Future<void> transactionDeleted(String transactionId) async {
    await _nullTaskRef(_db.tasks.transactionId, 'transactionId', transactionId);
    await _nullNoteRef(
      _db.notes.linkedTransactionId,
      'linkedTransactionId',
      transactionId,
    );
    final items = await (_db.select(
      _db.contentItems,
    )..where((i) => i.sponsor.isNotNull())).get();
    for (final r in items) {
      final i = r.toEntity();
      final s = i.sponsor;
      if (s == null || s.transactionId != transactionId) continue;
      final fixed = s.copyWith(transactionId: null);
      await (_db.update(
        _db.contentItems,
      )..where((x) => x.id.equals(i.id))).write(
        ContentItemsCompanion(sponsor: Value(jsonEncode(fixed.toJson()))),
      );
      await _outbox.patchQueued(SyncEntity.contentItems, i.id, {
        'sponsor': fixed.toJson(),
      });
    }
  }

  /// Task deleted → notes get `linkedTaskId = null`.
  Future<void> taskDeleted(String taskId) =>
      _nullNoteRef(_db.notes.linkedTaskId, 'linkedTaskId', taskId);

  /// Task area deleted → its tasks are deleted (the server tombstones them).
  Future<void> taskAreaDeleted(String areaId) async {
    final tasks = await (_db.select(
      _db.tasks,
    )..where((t) => t.areaId.equals(areaId))).get();
    for (final t in tasks) {
      await (_db.delete(_db.tasks)..where((x) => x.id.equals(t.id))).go();
      await _outbox.dropQueued(SyncEntity.tasks, t.id);
      await taskDeleted(t.id);
    }
  }

  // ---------------------------------------------------------------- notes & content

  /// Note deleted → content items get `noteId = null`.
  Future<void> noteDeleted(String noteId) async {
    final rows = await (_db.select(
      _db.contentItems,
    )..where((i) => i.noteId.equals(noteId))).get();
    for (final r in rows) {
      await (_db.update(_db.contentItems)..where((x) => x.id.equals(r.id)))
          .write(const ContentItemsCompanion(noteId: Value(null)));
      await _outbox.patchQueued(SyncEntity.contentItems, r.id, {
        'noteId': null,
      });
    }
  }

  /// Label deleted → its id is removed from every note (the server updates
  /// those notes too, so they sync).
  Future<void> noteLabelDeleted(String labelId) async {
    final rows = await (_db.select(
      _db.notes,
    )..where((n) => n.labels.like('%"$labelId"%'))).get();
    for (final r in rows) {
      final ids = [
        for (final x in r.toEntity().labelIds)
          if (x != labelId) x,
      ];
      await (_db.update(_db.notes)..where((x) => x.id.equals(r.id))).write(
        NotesCompanion(labels: Value(jsonEncode(ids))),
      );
      await _outbox.patchQueued(SyncEntity.notes, r.id, {'labels': ids});
    }
  }

  /// Content item deleted → its posts are deleted (tombstoned by the server);
  /// notes get `linkedContentId = null`.
  Future<void> contentItemDeleted(String itemId) async {
    await _deletePosts(_db.contentPosts.contentId, itemId);
    await _nullNoteRef(_db.notes.linkedContentId, 'linkedContentId', itemId);
  }

  /// Pillar [name] deleted → items with that pillar (case-insensitive) get
  /// `pillar = null`.
  Future<void> pillarDeleted(String name) => _setPillar(name, null);

  /// Pillar renamed [from] → [to]: items follow (the server does the same).
  Future<void> pillarRenamed(String from, String to) async {
    if (from == to) return;
    await _setPillar(from, to);
  }

  Future<void> _setPillar(String name, String? to) async {
    final key = name.trim().toLowerCase();
    final rows = await (_db.select(
      _db.contentItems,
    )..where((i) => i.pillar.isNotNull())).get();
    for (final r in rows) {
      if (r.pillar!.trim().toLowerCase() != key) continue;
      await (_db.update(_db.contentItems)..where((x) => x.id.equals(r.id)))
          .write(ContentItemsCompanion(pillar: Value(to)));
      await _outbox.patchQueued(SyncEntity.contentItems, r.id, {'pillar': to});
    }
  }

  /// Social account deleted → its posts are deleted.
  Future<void> socialAccountDeleted(String accountId) =>
      _deletePosts(_db.contentPosts.accountId, accountId);

  Future<void> _deletePosts(GeneratedColumn<String> column, String id) async {
    final rows = await (_db.select(
      _db.contentPosts,
    )..where((_) => column.equals(id))).get();
    for (final p in rows) {
      await (_db.delete(
        _db.contentPosts,
      )..where((x) => x.id.equals(p.id))).go();
      await _outbox.dropQueued(SyncEntity.contentPosts, p.id);
    }
  }

  Future<void> _nullNoteRef(
    GeneratedColumn<String> column,
    String field,
    String id,
  ) async {
    final rows = await (_db.select(
      _db.notes,
    )..where((_) => column.equals(id))).get();
    for (final n in rows) {
      await (_db.update(_db.notes)..where((x) => x.id.equals(n.id))).write(
        NotesCompanion.custom(
          linkedTaskId: field == 'linkedTaskId' ? const Constant(null) : null,
          linkedContentId: field == 'linkedContentId'
              ? const Constant(null)
              : null,
          linkedTransactionId: field == 'linkedTransactionId'
              ? const Constant(null)
              : null,
        ),
      );
      await _outbox.patchQueued(SyncEntity.notes, n.id, {field: null});
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
