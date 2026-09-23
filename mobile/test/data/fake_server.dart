import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart';

typedef Tomb = ({String entity, String id, int deletedAt});

/// In-memory implementation of the server side of `docs/mobile-sync.md`:
/// LWW (wallets by `editedAt`), tombstones, ledger balances, cascades without balance
/// reversal, unique keys → duplicate, epochs, ownership → rejected.
class FakeServer implements SyncApi {
  FakeServer({DateTime? start})
    : now = (start ?? DateTime.utc(2026, 9, 23, 4)).millisecondsSinceEpoch;

  int now;
  String epoch = 'epoch-1';
  bool online = true;

  final rows = {for (final e in SyncEntity.all) e: <String, Json>{}};
  final walletEditedAt = <String, int>{};
  final tombstones = <Tomb>[];

  /// Ids that belong to another user.
  final foreignIds = <String>{};

  /// Mutations on these entity ids are rejected with "Nope" (test hook).
  final rejectIds = <String>{};
  final uploads = <String>[];
  final pushed = <PushMutation>[];
  int pullCount = 0;

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  int tick() => now += 1000;
  String iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
  int ms(Object? isoString) =>
      DateTime.parse(isoString as String).millisecondsSinceEpoch;

  void _checkOnline() {
    if (!online) throw const NetworkFailure();
  }

  // ---------------------------------------------------------------- SyncApi

  @override
  Future<PullResponse> pull(int since) async {
    _checkOnline();
    pullCount++;
    final start = tick();
    final changes = {
      for (final e in SyncEntity.all)
        e: [
          for (final r in rows[e]!.values)
            if (ms(r['updatedAt']) >= since) _public(e, r),
        ],
    };
    final deleted = since == 0
        ? <Tombstone>[]
        : [
            for (final t in tombstones)
              if (t.deletedAt >= since)
                Tombstone(
                  entity: t.entity,
                  id: t.id,
                  deletedAt: DateTime.fromMillisecondsSinceEpoch(
                    t.deletedAt,
                    isUtc: true,
                  ),
                ),
          ];
    return PullResponse(
      serverTime: start - 5000,
      epoch: epoch,
      changes: changes,
      deleted: deleted,
    );
  }

  Json _public(String entity, Json r) => Map<String, dynamic>.from(r);

  @override
  Future<PushResponse> push(
    List<PushMutation> mutations, {
    String? epoch,
  }) async {
    _checkOnline();
    if (epoch != null && epoch != this.epoch) {
      throw EpochChangedException(this.epoch);
    }
    if (mutations.length > 1000) {
      throw const ValidationFailure('Too many mutations');
    }
    pushed.addAll(mutations);
    final results = <PushResult>[];
    for (final m in mutations) {
      final (status, error) = _apply(m);
      results.add(PushResult(id: m.id, status: status, error: error));
    }
    return PushResponse(serverTime: tick(), results: results);
  }

  @override
  Future<String> upload(String filePath) async {
    _checkOnline();
    final url = '/uploads/${uploads.length}-${filePath.split('/').last}';
    uploads.add(filePath);
    return url;
  }

  // ---------------------------------------------------------------- push rules

  (PushStatus, String?) _apply(PushMutation m) {
    final e = m.entity;
    if (!rows.containsKey(e) || !_idRe.hasMatch(m.entityId)) {
      return (PushStatus.rejected, 'Malformed');
    }
    if (foreignIds.contains(m.entityId)) {
      return (PushStatus.rejected, 'Not found');
    }
    if (rejectIds.contains(m.entityId)) return (PushStatus.rejected, 'Nope');
    final client = m.clientUpdatedAt.millisecondsSinceEpoch;
    final existing = rows[e]![m.entityId];
    if (existing != null) {
      final serverTs = e == SyncEntity.wallets
          ? walletEditedAt[m.entityId]!
          : ms(existing['updatedAt']);
      if (serverTs > client) return (PushStatus.skipped, null);
    } else if (m.op == MutationOp.upsert) {
      final tomb = tombstones
          .where((t) => t.entity == e && t.id == m.entityId)
          .lastOrNull;
      if (tomb != null && tomb.deletedAt > client) {
        return (PushStatus.skipped, null);
      }
    }

    if (m.op == MutationOp.delete) {
      if (existing != null) delete(e, m.entityId);
      return (PushStatus.applied, null);
    }

    final data = m.data!;
    final err = _validate(e, data);
    if (err != null) return (PushStatus.rejected, err);
    if (_duplicate(e, m.entityId, data)) return (PushStatus.duplicate, null);
    _write(e, m.entityId, data);
    return (PushStatus.applied, null);
  }

  bool _owned(String entity, String? id) =>
      id != null && rows[entity]!.containsKey(id) && !foreignIds.contains(id);

  String? _validate(String e, Json d) {
    switch (e) {
      case SyncEntity.transactions:
        if ((d['amount'] as num) <= 0) return 'Amount must be greater than 0';
        if (!_owned(SyncEntity.wallets, d['walletId'] as String?)) {
          return 'Wallet not found';
        }
        if (d['type'] == 'transfer') {
          final to = d['toWalletId'] as String?;
          if (to == null || to == d['walletId']) {
            return 'Choose a destination wallet';
          }
          if (!_owned(SyncEntity.wallets, to)) {
            return 'Destination wallet not found';
          }
        } else if (d['categoryId'] != null &&
            !_owned(SyncEntity.categories, d['categoryId'] as String?)) {
          return 'Category not found';
        }
      case SyncEntity.budgets:
        final c = rows[SyncEntity.categories]![d['categoryId']];
        if (c == null || c['type'] != 'expense') return 'Invalid category';
      case SyncEntity.food:
        final p = d['photoUrl'] as String?;
        if (p != null && !p.startsWith('/uploads/')) return 'Invalid photoUrl';
    }
    return null;
  }

  bool _duplicate(String e, String id, Json d) {
    bool clash(bool Function(Json r) same) =>
        rows[e]!.values.any((r) => r['id'] != id && same(r));
    return switch (e) {
      SyncEntity.prayers => clash(
        (r) => r['date'] == d['date'] && r['prayer'] == d['prayer'],
      ),
      SyncEntity.budgets => clash(
        (r) =>
            r['categoryId'] == d['categoryId'] &&
            r['month'] == d['month'] &&
            r['year'] == d['year'],
      ),
      _ => false,
    };
  }

  void _write(String e, String id, Json data) {
    final t = tick();
    final existing = rows[e]![id];
    final row = <String, dynamic>{
      ...data,
      'id': id,
      'createdAt': existing?['createdAt'] ?? iso(t),
      'updatedAt': iso(t),
    };
    if (e == SyncEntity.wallets) {
      row['balance'] = existing == null
          ? (data['balance'] ?? 0)
          : existing['balance'];
      row['archived'] = data['archived'] ?? false;
      walletEditedAt[id] = t;
    }
    if (e == SyncEntity.transactions) {
      _ledger(existing, -1);
      _ledger(row, 1);
    }
    rows[e]![id] = row;
    tombstones.removeWhere((x) => x.entity == e && x.id == id);
  }

  void _ledger(Json? tx, int sign) {
    if (tx == null) return;
    wireTxEffects(tx).forEach((walletId, delta) {
      final w = rows[SyncEntity.wallets]![walletId];
      if (w == null) return;
      w['balance'] = (w['balance'] as num).toDouble() + sign * delta;
      w['updatedAt'] = iso(tick());
    });
  }

  void _tomb(String e, String id) =>
      tombstones.add((entity: e, id: id, deletedAt: tick()));

  void _nullRef(String e, String field, String id) {
    for (final r in rows[e]!.values) {
      if (r[field] == id) {
        r[field] = null;
        r['updatedAt'] = iso(tick());
      }
    }
  }

  /// Central delete with the contract's cascades.
  void delete(String e, String id) {
    final row = rows[e]!.remove(id);
    if (row == null) return;
    if (e == SyncEntity.transactions) _ledger(row, -1);
    _tomb(e, id);
    if (e == SyncEntity.wallets) {
      final txs = rows[SyncEntity.transactions]!.values
          .where((t) => t['walletId'] == id || t['toWalletId'] == id)
          .map((t) => t['id'] as String)
          .toList();
      for (final t in txs) {
        rows[SyncEntity.transactions]!.remove(t); // no balance reversal
        _tomb(SyncEntity.transactions, t);
      }
      _nullRef(SyncEntity.subscriptions, 'walletId', id);
      _nullRef(SyncEntity.planned, 'walletId', id);
    }
    if (e == SyncEntity.categories) {
      _nullRef(SyncEntity.transactions, 'categoryId', id);
      _nullRef(SyncEntity.subscriptions, 'categoryId', id);
      _nullRef(SyncEntity.planned, 'categoryId', id);
      final budgets = rows[SyncEntity.budgets]!.values
          .where((b) => b['categoryId'] == id)
          .map((b) => b['id'] as String)
          .toList();
      for (final b in budgets) {
        rows[SyncEntity.budgets]!.remove(b);
        _tomb(SyncEntity.budgets, b);
      }
    }
  }

  // ---------------------------------------------------------------- "web" helpers

  /// Writes a row as the web would (full wire row minus id/timestamps).
  void web(String entity, String id, Json data) => _write(entity, id, data);

  void webDelete(String entity, String id) => delete(entity, id);

  /// Web "reset all data".
  void webReset() {
    for (final e in [
      SyncEntity.wallets,
      SyncEntity.categories,
      SyncEntity.transactions,
      SyncEntity.budgets,
    ]) {
      rows[e]!.clear();
    }
    for (final e in [SyncEntity.subscriptions, SyncEntity.planned]) {
      for (final r in rows[e]!.values) {
        r['walletId'] = null;
        r['categoryId'] = null;
        r['updatedAt'] = iso(tick());
      }
    }
    tombstones.clear();
    epoch = 'epoch-${tick()}';
  }

  double balanceOf(String walletId) =>
      (rows[SyncEntity.wallets]![walletId]!['balance'] as num).toDouble();
}
