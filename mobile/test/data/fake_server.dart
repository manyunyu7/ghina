import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/prayer_quality.dart';

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

  /// Upload of these file paths fails with the given failure (test hook).
  final uploadErrors = <String, Failure>{};

  /// Pretend to be an old server: no `taskAreas`/`tasks` keys, those entities
  /// unknown on push.
  bool legacy = false;

  /// When set, a pull seeds the default task areas for this user id if there are
  /// none (like the real server).
  String? seedAreasFor;
  final pushed = <PushMutation>[];

  /// Every rejected mutation with its error.
  final rejected = <(PushMutation, String?)>[];
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
    final seed = seedAreasFor;
    if (!legacy && seed != null && rows[SyncEntity.taskAreas]!.isEmpty) {
      _write(SyncEntity.taskAreas, 'area-kerjaan-$seed', {
        'name': 'Kerjaan',
        'code': 'KERJA',
        'color': '#1CB0F6',
        'icon': 'briefcase',
        'schedule': {
          'days': [1, 2, 3, 4, 5],
          'start': '09:00',
          'end': '17:00',
        },
        'sortOrder': 0,
        'archived': false,
      });
      _write(SyncEntity.taskAreas, 'area-life-$seed', {
        'name': 'Keseharian',
        'code': 'LIFE',
        'color': '#58CC02',
        'icon': 'home',
        'schedule': null,
        'sortOrder': 1,
        'archived': false,
      });
    }
    final changes = {
      for (final e in _entities)
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

  List<String> get _entities => [
    for (final e in SyncEntity.all)
      if (!legacy || (e != SyncEntity.taskAreas && e != SyncEntity.tasks)) e,
  ];

  Json _public(String entity, Json r) {
    final out = Map<String, dynamic>.from(r);
    if (legacy && entity == SyncEntity.transactions) out.remove('photos');
    return out;
  }

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
      if (status == PushStatus.rejected) rejected.add((m, error));
      results.add(PushResult(id: m.id, status: status, error: error));
    }
    return PushResponse(serverTime: tick(), results: results);
  }

  @override
  Future<String> upload(String filePath) async {
    _checkOnline();
    final err = uploadErrors[filePath];
    if (err != null) throw err;
    final url = '/uploads/${uploads.length}-${filePath.split('/').last}';
    uploads.add(filePath);
    return url;
  }

  // ---------------------------------------------------------------- push rules

  (PushStatus, String?) _apply(PushMutation m) {
    final e = m.entity;
    if (!_entities.contains(e) || !_idRe.hasMatch(m.entityId)) {
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

    final data = _normalize(e, m.entityId, existing, m.data!);
    final err = _validate(e, data);
    if (err != null) return (PushStatus.rejected, err);
    if (_duplicate(e, m.entityId, data)) return (PushStatus.duplicate, null);
    _write(e, m.entityId, data);
    return (PushStatus.applied, null);
  }

  static final _photoRe = RegExp(r'^/uploads/[A-Za-z0-9-]+\.[a-z]+$');
  static final _codeRe = RegExp(r'^[A-Z0-9]{1,8}$');

  /// Server-side defaults (docs/mobile-sync.md → Tasks, transactions.photos).
  Json _normalize(String e, String id, Json? existing, Json d) {
    final out = Map<String, dynamic>.from(d);
    if (e == SyncEntity.transactions && !legacy) {
      if (!out.containsKey('photos')) {
        out['photos'] = existing?['photos'] ?? <String>[];
      } else if (out['photos'] == null) {
        out['photos'] = <String>[];
      }
    }
    if (e == SyncEntity.taskAreas && out['code'] is String) {
      out['code'] = (out['code'] as String).trim().toUpperCase();
    }
    if (e == SyncEntity.tasks) {
      if (out['recurrence'] != null && out['seriesId'] == null) {
        out['seriesId'] = id;
      }
      if (out['done'] != true) {
        out['doneAt'] = null;
      } else {
        out['doneAt'] ??= iso(now);
      }
    }
    return out;
  }

  bool _owned(String entity, String? id) =>
      id != null && rows[entity]!.containsKey(id) && !foreignIds.contains(id);

  String? _validate(String e, Json d) {
    switch (e) {
      case SyncEntity.transactions:
        final type = d['type'];
        if (!const [
          'expense',
          'income',
          'transfer',
          'adjustment',
        ].contains(type)) {
          return 'Invalid type';
        }
        if (type == 'adjustment') {
          final a = (d['amount'] as num).toDouble();
          if (!a.isFinite || a == 0) return 'Amount must not be 0';
          if (d['categoryId'] != null || d['toWalletId'] != null) {
            return 'Adjustment takes no category or destination wallet';
          }
          if (!_owned(SyncEntity.wallets, d['walletId'] as String?)) {
            return 'Wallet not found';
          }
          return null;
        }
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
      case SyncEntity.prayers:
        // The real server runs `prayerEntryError` (src/lib/prayer-quality.ts);
        // the app's mirror of it is the same function.
        final p = Prayer.fromWire(d['prayer'] as String?);
        if (p == null) return 'Shalat tidak dikenal';
        final status = PrayerStatus.fromWire(d['status'] as String?);
        if (status == null) return 'Status tidak valid';
        return prayerEntryError(
          PrayerEntry(
            id: 'x',
            date: d['date'] as String,
            prayer: p,
            status: status,
            qobliyah: d['qobliyah'] as bool? ?? false,
            badiyah: d['badiyah'] as bool? ?? false,
            rakaat: d['rakaat'] as int?,
            note: d['note'] as String?,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
      case SyncEntity.budgets:
        final c = rows[SyncEntity.categories]![d['categoryId']];
        if (c == null || c['type'] != 'expense') return 'Invalid category';
      case SyncEntity.food:
        final p = d['photoUrl'] as String?;
        if (p != null && !p.startsWith('/uploads/')) return 'Invalid photoUrl';
      case SyncEntity.taskAreas:
        final name = (d['name'] as String? ?? '').trim();
        if (name.isEmpty || name.length > 40) return 'Invalid name';
        if (!_codeRe.hasMatch(d['code'] as String? ?? '')) {
          return 'Invalid code';
        }
        if (d['schedule'] != null && d['schedule'] is! Map) {
          return 'Invalid schedule';
        }
      case SyncEntity.tasks:
        if (!_owned(SyncEntity.taskAreas, d['areaId'] as String?)) {
          return 'Area not found';
        }
        final title = (d['title'] as String? ?? '').trim();
        if (title.isEmpty || title.length > 200) return 'Invalid title';
        if (d['recurrence'] != null && d['recurrence'] is! Map) {
          return 'Invalid recurrence';
        }
        if (d['recurrence'] != null && d['dueDate'] == null) {
          return 'A recurring task needs a due date';
        }
        if (d['dueTime'] != null && d['dueDate'] == null) {
          return 'A due time needs a due date';
        }
        for (final (field, entity) in [
          ('walletId', SyncEntity.wallets),
          ('categoryId', SyncEntity.categories),
          ('transactionId', SyncEntity.transactions),
        ]) {
          final ref = d[field] as String?;
          if (ref != null && !_owned(entity, ref)) return '$field not found';
        }
    }
    if (e == SyncEntity.transactions && d.containsKey('photos')) {
      final photos = d['photos'];
      if (photos is! List ||
          photos.length > 5 ||
          photos.any((p) => p is! String || !_photoRe.hasMatch(p))) {
        return 'Invalid photos';
      }
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
      SyncEntity.taskAreas => clash((r) => r['code'] == d['code']),
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
    if (e == SyncEntity.transactions) {
      _ledger(row, -1);
      _nullRef(SyncEntity.tasks, 'transactionId', id);
    }
    _tomb(e, id);
    if (e == SyncEntity.taskAreas) {
      final tasks = rows[SyncEntity.tasks]!.values
          .where((t) => t['areaId'] == id)
          .map((t) => t['id'] as String)
          .toList();
      for (final t in tasks) {
        rows[SyncEntity.tasks]!.remove(t);
        _tomb(SyncEntity.tasks, t);
      }
    }
    if (e == SyncEntity.wallets) {
      final txs = rows[SyncEntity.transactions]!.values
          .where((t) => t['walletId'] == id || t['toWalletId'] == id)
          .map((t) => t['id'] as String)
          .toList();
      for (final t in txs) {
        rows[SyncEntity.transactions]!.remove(t); // no balance reversal
        _tomb(SyncEntity.transactions, t);
        _nullRef(SyncEntity.tasks, 'transactionId', t);
      }
      _nullRef(SyncEntity.subscriptions, 'walletId', id);
      _nullRef(SyncEntity.planned, 'walletId', id);
      _nullRef(SyncEntity.tasks, 'walletId', id);
    }
    if (e == SyncEntity.categories) {
      _nullRef(SyncEntity.transactions, 'categoryId', id);
      _nullRef(SyncEntity.subscriptions, 'categoryId', id);
      _nullRef(SyncEntity.planned, 'categoryId', id);
      _nullRef(SyncEntity.tasks, 'categoryId', id);
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
