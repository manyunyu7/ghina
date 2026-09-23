import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../datasources/local/app_database.dart';
import '../models/api_dto.dart';
import '../models/entity_names.dart';
import '../models/wire.dart';

/// The outbox of pending local mutations.
///
/// Collapsing rules (contract "Client sync loop"), applied only among entries that
/// are **not** in flight:
/// - a new upsert replaces an earlier pending upsert/delete of the same entity id
///   (moved to the end of the queue with a fresh mutation id);
/// - a delete after an unpushed create removes both;
/// - a delete after an upsert of an existing row replaces the upsert.
/// An entry already being pushed is never modified; a newer change is queued behind it.
///
/// For `transactions`, each entry carries `base` = the row as the server has it (or
/// will have it once earlier entries are applied), so the pending balance effect is
/// `effect(data) − effect(base)` and chains of entries telescope correctly.
class Outbox {
  Outbox(this._db);

  final AppDatabase _db;
  final _writes = StreamController<void>.broadcast();

  /// Fires after every local mutation (the engine debounces this into a sync).
  Stream<void> get localWrites => _writes.stream;

  void notifyLocalWrite() {
    if (!_writes.isClosed) _writes.add(null);
  }

  Future<void> dispose() => _writes.close();

  // ---------------------------------------------------------------- queries

  Future<List<OutboxRow>> _entries(String entity, String entityId) =>
      (_db.select(_db.outbox)
            ..where(
              (o) => o.entity.equals(entity) & o.entityId.equals(entityId),
            )
            ..orderBy([(o) => OrderingTerm.asc(o.seq)]))
          .get();

  /// Latest queued (not in-flight) entry for the entity id.
  Future<OutboxRow?> pendingEntry(String entity, String entityId) async {
    final all = await _entries(entity, entityId);
    final p = all.where((e) => !e.inFlight);
    return p.isEmpty ? null : p.last;
  }

  Future<bool> hasAny(String entity, String entityId) async =>
      (await _entries(entity, entityId)).isNotEmpty;

  /// Ids of [entity] with any outbox entry (queued or in flight).
  Future<Set<String>> idsWithEntries(String entity) async {
    final q = _db.selectOnly(_db.outbox, distinct: true)
      ..addColumns([_db.outbox.entityId])
      ..where(_db.outbox.entity.equals(entity));
    return (await q.map((r) => r.read(_db.outbox.entityId)!).get()).toSet();
  }

  Future<List<OutboxRow>> all() =>
      (_db.select(_db.outbox)..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();

  Stream<int> watchCount() {
    final c = _db.outbox.seq.count();
    return (_db.selectOnly(
      _db.outbox,
    )..addColumns([c])).map((r) => r.read(c) ?? 0).watchSingle();
  }

  // ---------------------------------------------------------------- enqueue

  /// Queue an upsert. [isCreate]: the row didn't exist locally before this write.
  /// [base]: transactions only — the current (server-known) row before this write.
  Future<void> enqueueUpsert({
    required String entity,
    required String entityId,
    required Json data,
    required DateTime clientUpdatedAt,
    required bool isCreate,
    Json? base,
  }) => _db.transaction(() async {
    final entries = await _entries(entity, entityId);
    final pending = entries.where((e) => !e.inFlight).lastOrNull;
    final inFlight = entries.where((e) => e.inFlight).lastOrNull;

    bool create;
    String? baseJson;
    if (pending != null) {
      create = pending.op == MutationOp.upsert.name && pending.isCreate;
      baseJson = pending.base;
      await (_db.delete(
        _db.outbox,
      )..where((o) => o.seq.equals(pending.seq))).go();
    } else if (inFlight != null) {
      create = false;
      baseJson = inFlight.op == MutationOp.upsert.name ? inFlight.data : null;
    } else {
      create = isCreate;
      baseJson = base == null ? null : jsonEncode(base);
    }
    await _insert(
      entity,
      entityId,
      MutationOp.upsert,
      jsonEncode(data),
      entity == SyncEntity.transactions ? baseJson : null,
      create,
      clientUpdatedAt,
    );
  });

  /// Queue a delete. [base]: transactions only — the row before deletion.
  Future<void> enqueueDelete({
    required String entity,
    required String entityId,
    required DateTime clientUpdatedAt,
    Json? base,
  }) => _db.transaction(() async {
    final entries = await _entries(entity, entityId);
    final pending = entries.where((e) => !e.inFlight).lastOrNull;
    final inFlight = entries.where((e) => e.inFlight).lastOrNull;

    String? baseJson;
    if (pending != null) {
      await (_db.delete(
        _db.outbox,
      )..where((o) => o.seq.equals(pending.seq))).go();
      if (pending.op == MutationOp.upsert.name &&
          pending.isCreate &&
          inFlight == null) {
        return; // never reached the server: nothing to delete
      }
      baseJson = pending.base;
    } else if (inFlight != null) {
      baseJson = inFlight.op == MutationOp.upsert.name ? inFlight.data : null;
    } else {
      baseJson = base == null ? null : jsonEncode(base);
    }
    await _insert(
      entity,
      entityId,
      MutationOp.delete,
      null,
      entity == SyncEntity.transactions ? baseJson : null,
      false,
      clientUpdatedAt,
    );
  });

  Future<void> _insert(
    String entity,
    String entityId,
    MutationOp op,
    String? data,
    String? base,
    bool isCreate,
    DateTime at,
  ) => _db
      .into(_db.outbox)
      .insert(
        OutboxCompanion.insert(
          mutationId: newId(),
          entity: entity,
          op: op.name,
          entityId: entityId,
          data: Value(data),
          base: Value(base),
          isCreate: Value(isCreate),
          clientUpdatedAt: at.millisecondsSinceEpoch,
        ),
      );

  /// Drops queued (not in-flight) entries for an entity id (e.g. rows removed by a
  /// cascade the server applies itself).
  Future<void> dropQueued(String entity, String entityId) =>
      (_db.delete(_db.outbox)..where(
            (o) =>
                o.entity.equals(entity) &
                o.entityId.equals(entityId) &
                o.inFlight.equals(false),
          ))
          .go();

  /// Patches the data of a queued upsert (e.g. `{walletId: null}` after a cascade).
  Future<void> patchQueued(String entity, String entityId, Json patch) async {
    final p = await pendingEntry(entity, entityId);
    if (p == null || p.data == null) return;
    final data = (jsonDecode(p.data!) as Map).cast<String, dynamic>()
      ..addAll(patch);
    await (_db.update(_db.outbox)..where((o) => o.seq.equals(p.seq))).write(
      OutboxCompanion(data: Value(jsonEncode(data))),
    );
  }

  // ---------------------------------------------------------------- balances

  /// Per-wallet balance delta of every transaction mutation still in the outbox.
  Future<Map<String, double>> pendingBalanceEffects() async {
    final rows = await (_db.select(
      _db.outbox,
    )..where((o) => o.entity.equals(SyncEntity.transactions))).get();
    final out = <String, double>{};
    for (final r in rows) {
      entryEffect(r).forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    out.removeWhere((_, v) => v == 0);
    return out;
  }

  /// `effect(data) − effect(base)` of one transactions entry.
  static Map<String, double> entryEffect(OutboxRow r) {
    final after = r.op == MutationOp.upsert.name ? decode(r.data) : null;
    final out = <String, double>{};
    wireTxEffects(after).forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    wireTxEffects(decode(r.base)).forEach((k, v) => out[k] = (out[k] ?? 0) - v);
    return out;
  }

  static Json? decode(String? s) =>
      s == null ? null : (jsonDecode(s) as Map).cast<String, dynamic>();

  // ---------------------------------------------------------------- push support

  /// After a crash mid-push: clear in-flight flags. If a newer queued entry exists
  /// for the same id, it supersedes the stale in-flight one (inheriting its base).
  Future<void> recoverInFlight() => _db.transaction(() async {
    final stale = await (_db.select(
      _db.outbox,
    )..where((o) => o.inFlight.equals(true))).get();
    for (final s in stale) {
      final follower = await pendingEntry(s.entity, s.entityId);
      if (follower != null) {
        await (_db.update(
          _db.outbox,
        )..where((o) => o.seq.equals(follower.seq))).write(
          OutboxCompanion(base: Value(s.base), isCreate: Value(s.isCreate)),
        );
        await (_db.delete(_db.outbox)..where((o) => o.seq.equals(s.seq))).go();
      } else {
        await (_db.update(_db.outbox)..where((o) => o.seq.equals(s.seq))).write(
          const OutboxCompanion(inFlight: Value(false)),
        );
      }
    }
  });

  /// Marks up to [limit] queued entries in flight and returns them in push order:
  /// wallet and category upserts first (they're referenced by everything else),
  /// then everything in queue order.
  Future<List<OutboxRow>> takeBatch({int limit = 500}) =>
      _db.transaction(() async {
        final rows =
            await (_db.select(_db.outbox)
                  ..where((o) => o.inFlight.equals(false))
                  ..orderBy([(o) => OrderingTerm.asc(o.seq)])
                  ..limit(limit))
                .get();
        if (rows.isEmpty) return rows;
        await (_db.update(_db.outbox)
              ..where((o) => o.seq.isIn(rows.map((r) => r.seq))))
            .write(const OutboxCompanion(inFlight: Value(true)));
        int rank(OutboxRow r) {
          if (r.op != MutationOp.upsert.name) return 2;
          if (r.entity == SyncEntity.wallets) return 0;
          if (r.entity == SyncEntity.categories) return 1;
          return 2;
        }

        final indexed = rows.indexed.toList()
          ..sort((a, b) {
            final c = rank(a.$2).compareTo(rank(b.$2));
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
        return [for (final e in indexed) e.$2.copyWith(inFlight: true)];
      });

  /// Removes an answered in-flight entry. When it wasn't applied, a queued follower
  /// for the same id inherits its base (the server still has the old row).
  Future<void> complete(OutboxRow entry, {required bool applied}) async {
    if (!applied) {
      final follower = await pendingEntry(entry.entity, entry.entityId);
      if (follower != null) {
        await (_db.update(
          _db.outbox,
        )..where((o) => o.seq.equals(follower.seq))).write(
          OutboxCompanion(
            base: Value(entry.base),
            isCreate: Value(entry.isCreate),
          ),
        );
      }
    }
    await (_db.delete(_db.outbox)..where((o) => o.seq.equals(entry.seq))).go();
  }

  /// Rewrites the data of an in-flight entry before it is sent (photo upload).
  Future<void> replaceData(int seq, Json data) =>
      (_db.update(_db.outbox)..where((o) => o.seq.equals(seq))).write(
        OutboxCompanion(data: Value(jsonEncode(data))),
      );
}
