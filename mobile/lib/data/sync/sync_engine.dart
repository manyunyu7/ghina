import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/streams.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../datasources/remote/sync_api.dart';
import '../models/api_dto.dart';
import '../models/entity_names.dart';
import '../models/wire.dart';
import '../repositories/photo_store.dart';
import 'local_cascades.dart';
import 'outbox.dart';

/// Something that calls [SyncEngine.requestSync] on app events (lifecycle, network,
/// timers). See `FlutterSyncTriggers`.
abstract interface class SyncTriggerSource {
  void attach(SyncEngine engine);
  void detach();
}

/// Offline-first sync engine (contract "Client sync loop"): push the outbox, then pull
/// changes since the cursor. One sync at a time; requests during a sync schedule one
/// more round.
class SyncEngine implements SyncService {
  SyncEngine({
    required AppDatabase db,
    required Outbox outbox,
    required this._api,
    required this._photos,
    this._clock = const SystemClock(),
    this._triggers,
    this.debounce = const Duration(seconds: 2),
    this.batchSize = 500,
  }) : _db = db,
       _outbox = outbox,
       _cascades = LocalCascades(db, outbox);

  final AppDatabase _db;
  final Outbox _outbox;
  final SyncApi _api;
  final PhotoStore _photos;
  final Clock _clock;
  final SyncTriggerSource? _triggers;
  final LocalCascades _cascades;

  /// Delay between a local write and the sync it triggers.
  final Duration debounce;

  /// Mutations per push request (server max is 1000).
  final int batchSize;

  static const _minBackoff = Duration(seconds: 2);
  static const _maxBackoff = Duration(minutes: 5);

  bool _started = false;
  bool _recovered = false;
  Future<void>? _running;
  bool _again = false;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  Duration _backoff = _minBackoff;
  StreamSubscription<void>? _writesSub;

  SyncPhase _phase = SyncPhase.idle;
  String? _transientError;
  final _phaseCtrl = StreamController<SyncPhase>.broadcast();

  bool get isStarted => _started;
  SyncPhase get phase => _phase;

  // ---------------------------------------------------------------- lifecycle

  @override
  void start() {
    if (_started) return;
    _started = true;
    _writesSub = _outbox.localWrites.listen((_) => _scheduleDebounced());
    _triggers?.attach(this);
    requestSync();
  }

  @override
  void stop() {
    if (!_started) return;
    _started = false;
    _writesSub?.cancel();
    _writesSub = null;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _triggers?.detach();
  }

  Future<void> dispose() async {
    stop();
    await _phaseCtrl.close();
  }

  void _scheduleDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, requestSync);
  }

  /// Fire-and-forget sync (errors are reflected in the status, not thrown).
  void requestSync() {
    unawaited(syncNow().catchError((Object _) {}));
  }

  /// Network came back: retry right away.
  void onConnectivityRegained() {
    _backoff = _minBackoff;
    _retryTimer?.cancel();
    requestSync();
  }

  void _scheduleRetry() {
    if (!_started) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff, requestSync);
    _backoff = Duration(
      milliseconds: math.min(
        _backoff.inMilliseconds * 2,
        _maxBackoff.inMilliseconds,
      ),
    );
  }

  void _setPhase(SyncPhase p, {String? error}) {
    _phase = p;
    _transientError = error;
    if (!_phaseCtrl.isClosed) _phaseCtrl.add(p);
  }

  // ---------------------------------------------------------------- status

  Stream<SyncPhase> _phases() => Stream<SyncPhase>.multi((c) {
    c.add(_phase);
    final sub = _phaseCtrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  @override
  Stream<SyncStatus> watchStatus() => combineLatest3(
    _phases(),
    _outbox.watchCount(),
    _db.watchMeta(),
    (SyncPhase p, int count, SyncMetaRow? meta) => SyncStatus(
      phase: p,
      pendingCount: count,
      lastSyncAt: meta?.lastSyncAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(meta!.lastSyncAt!),
      lastError: _transientError ?? meta?.lastError,
    ),
  );

  // ---------------------------------------------------------------- sync

  @override
  Future<void> syncNow() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final f = _loop();
    _running = f;
    return f.whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again);
  }

  Future<void> _syncOnce() async {
    _setPhase(SyncPhase.syncing);
    try {
      if (!_recovered) {
        await _outbox.recoverInFlight();
        _recovered = true;
      }
      final rejections = <String>[];
      try {
        await _push(rejections);
      } on EpochChangedException catch (e) {
        await _resetForEpoch(e.epoch);
      }
      await _pull();
      await _db.updateMeta(
        SyncMetaCompanion(
          lastSyncAt: Value(_clock.now().millisecondsSinceEpoch),
          lastError: Value(rejections.isEmpty ? null : rejections.join('\n')),
        ),
      );
      _backoff = _minBackoff;
      _retryTimer?.cancel();
      _setPhase(SyncPhase.idle);
    } on NetworkFailure {
      _setPhase(SyncPhase.offline);
      _scheduleRetry();
      rethrow;
    } on UnauthorizedFailure catch (f) {
      _setPhase(SyncPhase.error, error: f.message);
      rethrow;
    } on Failure catch (f) {
      _setPhase(SyncPhase.error, error: f.message);
      _scheduleRetry();
      rethrow;
    } catch (e) {
      _setPhase(SyncPhase.error, error: 'Sinkronisasi gagal');
      _scheduleRetry();
      throw UnknownFailure('Sinkronisasi gagal', e);
    }
  }

  @override
  Future<void> resetLocalData() async {
    await _db.wipe();
    await _db.updateMeta(
      const SyncMetaCompanion(
        cursor: Value(0),
        fullPullRequired: Value(false),
        lastError: Value(null),
      ),
    );
    await syncNow();
  }

  Future<void> _resetForEpoch(String? epoch) async {
    await _db.wipe();
    await _db.updateMeta(
      SyncMetaCompanion(
        cursor: const Value(0),
        fullPullRequired: const Value(false),
        epoch: epoch == null ? const Value.absent() : Value(epoch),
      ),
    );
  }

  // ---------------------------------------------------------------- push

  Future<void> _push(List<String> rejections) async {
    while (true) {
      await _uploadPendingPhotos(rejections);
      final batch = await _outbox.takeBatch(limit: batchSize);
      if (batch.isEmpty) return;
      final meta = await _db.getMeta();
      final PushResponse res;
      try {
        res = await _api.push([
          for (final e in batch)
            PushMutation(
              id: e.mutationId,
              entity: e.entity,
              op: MutationOp.values.byName(e.op),
              entityId: e.entityId,
              data: Outbox.decode(e.data),
              clientUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
                e.clientUpdatedAt,
              ),
            ),
        ], epoch: meta.epoch);
      } catch (_) {
        await _outbox.recoverInFlight();
        rethrow;
      }
      await _db.transaction(() => _applyPushResults(batch, res, rejections));
      if (batch.length < batchSize) return;
    }
  }

  Future<void> _applyPushResults(
    List<OutboxRow> batch,
    PushResponse res,
    List<String> rejections,
  ) async {
    final byId = {for (final e in batch) e.mutationId: e};
    var needFullPull = false;
    for (final r in res.results) {
      final entry = byId.remove(r.id);
      if (entry == null) continue;
      switch (r.status) {
        case PushStatus.applied:
          if (entry.entity == SyncEntity.transactions) {
            // The server moved its balances; mirror that in the stored server balance
            // so the displayed balance doesn't jump before the pull.
            for (final fx in Outbox.entryEffect(entry).entries) {
              await _db.customUpdate(
                'UPDATE wallets SET balance = balance + ? WHERE id = ?',
                variables: [
                  Variable.withReal(fx.value),
                  Variable.withString(fx.key),
                ],
                updates: {_db.wallets},
                updateKind: UpdateKind.update,
              );
            }
          }
          await _outbox.complete(entry, applied: true);
        case PushStatus.skipped:
          // Server row is newer; make sure the next pull brings it even if it's older
          // than our cursor.
          await _outbox.complete(entry, applied: false);
          needFullPull = true;
        case PushStatus.duplicate:
          // Another row holds the unique key; the server row arrives on the pull.
          await _outbox.complete(entry, applied: false);
          await _outbox.dropQueued(entry.entity, entry.entityId);
          await _deleteRow(entry.entity, entry.entityId);
        case PushStatus.rejected:
          rejections.add(r.error ?? 'Perubahan ditolak server');
          await _outbox.complete(entry, applied: false);
          await _outbox.dropQueued(entry.entity, entry.entityId);
          await _deleteRow(entry.entity, entry.entityId);
          needFullPull =
              true; // restores the server's version of the row, if any
      }
    }
    // Entries the server didn't answer: send again next time.
    for (final e in byId.values) {
      await (_db.update(_db.outbox)..where((o) => o.seq.equals(e.seq))).write(
        const OutboxCompanion(inFlight: Value(false)),
      );
    }
    if (needFullPull) {
      await _db.updateMeta(
        const SyncMetaCompanion(fullPullRequired: Value(true)),
      );
    }
  }

  /// Uploads offline food photos, then points the queued upsert at the returned URL.
  Future<void> _uploadPendingPhotos(List<String> rejections) async {
    final queued =
        await (_db.select(_db.outbox)..where(
              (o) =>
                  o.entity.equals(SyncEntity.food) &
                  o.op.equals(MutationOp.upsert.name) &
                  o.inFlight.equals(false),
            ))
            .get();
    for (final e in queued) {
      final row = await (_db.select(
        _db.food,
      )..where((f) => f.id.equals(e.entityId))).getSingleOrNull();
      final path = row?.localPhotoPath;
      if (path == null) continue;
      String? url;
      try {
        url = await _api.upload(path);
      } on NetworkFailure {
        rethrow;
      } on Failure catch (f) {
        rejections.add('Foto "${row!.name}" gagal diunggah: ${f.message}');
      }
      await _db.transaction(() async {
        final current = await (_db.select(
          _db.food,
        )..where((f) => f.id.equals(e.entityId))).getSingleOrNull();
        if (current == null || current.localPhotoPath != path) {
          return; // changed meanwhile
        }
        await (_db.update(
          _db.food,
        )..where((f) => f.id.equals(e.entityId))).write(
          FoodCompanion(
            photoUrl: Value(url),
            localPhotoPath: const Value(null),
          ),
        );
        await _outbox.patchQueued(SyncEntity.food, e.entityId, {
          'photoUrl': url,
        });
      });
      await _photos.delete(path);
    }
  }

  // ---------------------------------------------------------------- pull

  /// Pull without pushing (tests only).
  @visibleForTesting
  Future<void> pullOnly() => _pull();

  Future<void> _pull() async {
    final meta = await _db.getMeta();
    var since = meta.fullPullRequired ? 0 : meta.cursor;
    var res = await _api.pull(since);
    if (meta.epoch != null && res.epoch != meta.epoch) {
      await _resetForEpoch(res.epoch);
      if (since != 0) {
        since = 0;
        res = await _api.pull(0);
      }
    }
    final full = since == 0;
    await _db.transaction(() async {
      await _applyPull(res, full: full);
      await _db.updateMeta(
        SyncMetaCompanion(
          cursor: Value(res.serverTime),
          epoch: Value(res.epoch),
          fullPullRequired: const Value(false),
        ),
      );
    });
  }

  /// Applies a pull. A [full] pull is the complete server state (and carries no
  /// tombstones), so local rows missing from it are deleted unless they have pending
  /// mutations.
  Future<void> _applyPull(PullResponse res, {required bool full}) async {
    final pending = <String, Set<String>>{
      for (final e in SyncEntity.all) e: await _outbox.idsWithEntries(e),
    };

    if (full) {
      for (final entity in SyncEntity.all) {
        final keep = {
          for (final r in res.changes[entity] ?? const <Json>[])
            r['id'] as String,
          ...pending[entity]!,
        };
        for (final id in await _localIds(entity)) {
          if (!keep.contains(id)) await _deleteRow(entity, id);
        }
      }
    }

    // Tombstones first: a row re-created after its deletion also shows up in changes.
    for (final t in res.deleted) {
      if (pending[t.entity]?.contains(t.id) ?? true) {
        continue; // pending local wins
      }
      final n = await _deleteRow(t.entity, t.id);
      if (n == 0) continue;
      if (t.entity == SyncEntity.wallets) await _cascades.walletDeleted(t.id);
      if (t.entity == SyncEntity.categories) {
        await _cascades.categoryDeleted(t.id);
      }
    }

    for (final entity in SyncEntity.all) {
      for (final row in res.changes[entity] ?? const <Json>[]) {
        final id = row['id'] as String;
        if (pending[entity]!.contains(id)) {
          if (entity == SyncEntity.wallets && row['balance'] != null) {
            // Balance is server-authoritative even while a local edit is pending.
            await (_db.update(
              _db.wallets,
            )..where((w) => w.id.equals(id))).write(
              WalletsCompanion(
                balance: Value((row['balance'] as num).toDouble()),
              ),
            );
          }
          continue;
        }
        await _upsertPulled(entity, row);
      }
    }
  }

  Future<void> _upsertPulled(String entity, Json j) async {
    final id = j['id'] as String;
    switch (entity) {
      case SyncEntity.wallets:
        await _db.into(_db.wallets).insertOnConflictUpdate(walletFromWire(j));
      case SyncEntity.categories:
        await _db
            .into(_db.categories)
            .insertOnConflictUpdate(categoryFromWire(j));
      case SyncEntity.transactions:
        await _db
            .into(_db.transactions)
            .insertOnConflictUpdate(transactionFromWire(j));
      case SyncEntity.budgets:
        final clash =
            await (_db.select(_db.budgets)..where(
                  (b) =>
                      b.categoryId.equals(j['categoryId'] as String) &
                      b.month.equals((j['month'] as num).toInt()) &
                      b.year.equals((j['year'] as num).toInt()) &
                      b.id.equals(id).not(),
                ))
                .get();
        for (final c in clash) {
          await _outbox.dropQueued(SyncEntity.budgets, c.id);
          await _deleteRow(SyncEntity.budgets, c.id);
        }
        await _db.into(_db.budgets).insertOnConflictUpdate(budgetFromWire(j));
      case SyncEntity.subscriptions:
        await _db
            .into(_db.subscriptions)
            .insertOnConflictUpdate(subscriptionFromWire(j));
      case SyncEntity.planned:
        await _db.into(_db.planned).insertOnConflictUpdate(plannedFromWire(j));
      case SyncEntity.prayers:
        final clash =
            await (_db.select(_db.prayers)..where(
                  (p) =>
                      p.date.equals(j['date'] as String) &
                      p.prayer.equals(j['prayer'] as String) &
                      p.id.equals(id).not(),
                ))
                .get();
        for (final c in clash) {
          await _outbox.dropQueued(SyncEntity.prayers, c.id);
          await _deleteRow(SyncEntity.prayers, c.id);
        }
        await _db.into(_db.prayers).insertOnConflictUpdate(prayerFromWire(j));
      case SyncEntity.health:
        await _db.into(_db.health).insertOnConflictUpdate(healthFromWire(j));
      case SyncEntity.food:
        await _db.into(_db.food).insertOnConflictUpdate(foodFromWire(j));
      default:
        break; // unknown entity from a newer server: ignore
    }
  }

  Future<List<String>> _localIds(String entity) async {
    final table = _table(entity);
    if (table == null) return const [];
    final rows = await _db
        .customSelect(
          'SELECT id FROM ${table.actualTableName}',
          readsFrom: {table},
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  TableInfo<Table, dynamic>? _table(String entity) => switch (entity) {
    SyncEntity.wallets => _db.wallets,
    SyncEntity.categories => _db.categories,
    SyncEntity.transactions => _db.transactions,
    SyncEntity.budgets => _db.budgets,
    SyncEntity.subscriptions => _db.subscriptions,
    SyncEntity.planned => _db.planned,
    SyncEntity.prayers => _db.prayers,
    SyncEntity.health => _db.health,
    SyncEntity.food => _db.food,
    _ => null,
  };

  /// Deletes one local row without queuing anything. Returns rows deleted.
  Future<int> _deleteRow(String entity, String id) {
    final table = _table(entity);
    if (table == null) return Future.value(0);
    return _db.customUpdate(
      'DELETE FROM ${table.actualTableName} WHERE id = ?',
      variables: [Variable.withString(id)],
      updates: {table},
      updateKind: UpdateKind.delete,
    );
  }
}
