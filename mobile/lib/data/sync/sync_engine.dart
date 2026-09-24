import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart' show DioException;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/streams.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/content_rules.dart'
    show autoStage, recordSponsorPaid, recordStage;
import '../../domain/usecases/notes_rules.dart' show nameKey;
import '../../domain/usecases/task_rules.dart' show defaultTaskAreas;
import '../datasources/local/app_database.dart';
import '../datasources/remote/sync_api.dart';
import '../models/api_dto.dart';
import '../models/entity_names.dart';
import '../models/mappers.dart';
import '../models/notes_content_mappers.dart';
import '../models/notes_content_wire.dart';
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
      await _requeueForwardRefs(batch, res);
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
          if (entry.entity == SyncEntity.taskAreas) {
            // Same area code created elsewhere: keep this area's tasks and move
            // them to the server's area once the pull brings it.
            final area = await (_db.select(
              _db.taskAreas,
            )..where((a) => a.id.equals(entry.entityId))).getSingleOrNull();
            if (area != null) _areaRemaps[area.id] = area.code;
          }
          if (entry.entity == SyncEntity.noteLabels) {
            // Same label name created elsewhere: its notes move to the server's
            // label once the pull brings it (see _applyLabelRemaps).
            final label = await (_db.select(
              _db.noteLabels,
            )..where((l) => l.id.equals(entry.entityId))).getSingleOrNull();
            if (label != null) await _rememberLabelRemap(label.id, label.name);
          }
          await _deleteRow(entry.entity, entry.entityId);
        case PushStatus.rejected
            when entry.entity == SyncEntity.tasks &&
                await _inRemappedArea(entry.entityId):
          // Its area was a duplicate: re-queued after the pull (see above).
          await _outbox.complete(entry, applied: false);
          await _outbox.dropQueued(entry.entity, entry.entityId);
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

  /// Local area id → its code, for areas the server answered `duplicate` to.
  final _areaRemaps = <String, String>{};

  /// Local label id → its name and the notes carrying it, for labels that lost
  /// a name clash (`duplicate` push, or a pulled label with the same name).
  final _labelRemaps = <String, ({String name, Set<String> notes})>{};

  Future<void> _rememberLabelRemap(String labelId, String name) async {
    final rows = await (_db.select(
      _db.notes,
    )..where((n) => n.labels.like('%"$labelId"%'))).get();
    _labelRemaps[labelId] = (
      name: name,
      notes: {...?_labelRemaps[labelId]?.notes, for (final r in rows) r.id},
    );
  }

  /// Soft links the server resolves leniently (an unknown target is nulled
  /// instead of rejected): a note pushed before the content item it links
  /// (`linkedContentId`) created in the same batch — notes go first because
  /// items reference notes (`noteId`) — would lose the link. Such rows are
  /// queued once more after the batch (unless a newer change is queued anyway).
  Future<void> _requeueForwardRefs(
    List<OutboxRow> batch,
    PushResponse res,
  ) async {
    final applied = {
      for (final r in res.results)
        if (r.status == PushStatus.applied) r.id,
    };
    final pos = <String, int>{
      for (final (i, e) in batch.indexed)
        if (e.op == MutationOp.upsert.name) '${e.entity}/${e.entityId}': i,
    };
    var queued = false;
    for (final (i, e) in batch.indexed) {
      if (!applied.contains(e.mutationId) ||
          e.entity != SyncEntity.notes ||
          e.op != MutationOp.upsert.name) {
        continue;
      }
      final target = Outbox.decode(e.data)?['linkedContentId'];
      if (target is! String) continue;
      final at = pos['${SyncEntity.contentItems}/$target'];
      if (at == null || at < i) continue;
      await _db.transaction(() async {
        if (await _outbox.pendingEntry(e.entity, e.entityId) != null) return;
        final row = await (_db.select(
          _db.notes,
        )..where((n) => n.id.equals(e.entityId))).getSingleOrNull();
        if (row == null) return;
        await _outbox.enqueueUpsert(
          entity: SyncEntity.notes,
          entityId: e.entityId,
          data: noteToWire(row.toEntity()),
          clientUpdatedAt: _clock.now(),
          isCreate: false,
        );
        queued = true;
      });
    }
    if (queued) _outbox.notifyLocalWrite();
  }

  /// After a pull: notes that carried a label which lost a name clash get the
  /// label now holding that name (queued, since the server dropped the unknown
  /// id), or just lose it when there is none.
  Future<void> _applyLabelRemaps() async {
    if (_labelRemaps.isEmpty) return;
    final remaps = Map.of(_labelRemaps);
    _labelRemaps.clear();
    var moved = false;
    await _db.transaction(() async {
      final labels = [
        for (final l in await _db.select(_db.noteLabels).get()) l.toEntity(),
      ];
      for (final MapEntry(key: oldId, value: r) in remaps.entries) {
        final target = labels
            .where((l) => l.id != oldId && nameKey(l.name) == nameKey(r.name))
            .firstOrNull;
        for (final noteId in r.notes) {
          final row = await (_db.select(
            _db.notes,
          )..where((n) => n.id.equals(noteId))).getSingleOrNull();
          if (row == null) continue;
          final n = row.toEntity();
          final ids = [
            for (final x in n.labelIds)
              if (x != oldId) x,
            if (target != null && !n.labelIds.contains(target.id)) target.id,
          ];
          if (ids.length == n.labelIds.length &&
              ids.every(n.labelIds.contains)) {
            continue;
          }
          final updated = n.copyWith(labelIds: ids, updatedAt: _clock.now());
          await _db
              .into(_db.notes)
              .insertOnConflictUpdate(updated.toCompanion());
          if (target == null) {
            await _outbox.patchQueued(SyncEntity.notes, n.id, {'labels': ids});
            continue;
          }
          await _outbox.enqueueUpsert(
            entity: SyncEntity.notes,
            entityId: n.id,
            data: noteToWire(updated),
            clientUpdatedAt: updated.updatedAt,
            isCreate: false,
          );
          moved = true;
        }
      }
    });
    if (moved) _outbox.notifyLocalWrite();
  }

  /// Content items whose posts changed status in the pull being applied.
  final _stageChecks = <String>{};
  bool _fullPull = false;

  /// After a pull: the stage auto-advance rule (`autoStage`, forward only) on
  /// items whose posts changed status elsewhere. Each device applies it to the
  /// posts it changes, so two devices posting different accounts offline
  /// would otherwise both leave the item at `terjadwal` once everything is
  /// posted. A moved item is queued (both devices computing it is harmless).
  Future<void> _reconcileStages() async {
    if (_stageChecks.isEmpty) return;
    final ids = {..._stageChecks};
    _stageChecks.clear();
    var moved = false;
    await _db.transaction(() async {
      for (final id in ids) {
        final row = await (_db.select(
          _db.contentItems,
        )..where((i) => i.id.equals(id))).getSingleOrNull();
        if (row == null) continue;
        final item = row.toEntity();
        final posts = [
          for (final p in await (_db.select(
            _db.contentPosts,
          )..where((p) => p.contentId.equals(id))).get())
            p.toEntity(),
        ];
        final next = autoStage(item.stage, posts);
        if (next == item.stage) continue;
        final now = _clock.now();
        final updated = item.copyWith(
          stage: next,
          stageReachedAt: recordStage(item.stageReachedAt, next, now),
          updatedAt: now,
        );
        await _db
            .into(_db.contentItems)
            .insertOnConflictUpdate(updated.toCompanion());
        await _outbox.enqueueUpsert(
          entity: SyncEntity.contentItems,
          entityId: id,
          data: contentItemToWire(updated),
          clientUpdatedAt: now,
          isCreate: false,
        );
        moved = true;
      }
    });
    if (moved) _outbox.notifyLocalWrite();
  }

  Future<bool> _inRemappedArea(String taskId) async {
    if (_areaRemaps.isEmpty) return false;
    final t = await (_db.select(
      _db.tasks,
    )..where((x) => x.id.equals(taskId))).getSingleOrNull();
    return t != null && _areaRemaps.containsKey(t.areaId);
  }

  /// After a pull: tasks of an area that lost a code clash move to the area now
  /// holding that code, and are queued again.
  Future<void> _applyAreaRemaps() async {
    if (_areaRemaps.isEmpty) return;
    final remaps = Map.of(_areaRemaps);
    _areaRemaps.clear();
    var moved = false;
    await _db.transaction(() async {
      for (final MapEntry(key: oldId, value: code) in remaps.entries) {
        final target =
            await (_db.select(_db.taskAreas)
                  ..where((a) => a.code.equals(code) & a.id.equals(oldId).not())
                  ..limit(1))
                .getSingleOrNull();
        if (target == null) continue;
        final rows = await (_db.select(
          _db.tasks,
        )..where((t) => t.areaId.equals(oldId))).get();
        for (final r in rows) {
          final t = r.toEntity().copyWith(
            areaId: target.id,
            updatedAt: _clock.now(),
          );
          await _db.into(_db.tasks).insertOnConflictUpdate(t.toCompanion());
          await _outbox.enqueueUpsert(
            entity: SyncEntity.tasks,
            entityId: t.id,
            data: taskToWire(t),
            clientUpdatedAt: t.updatedAt,
            isCreate: false,
          );
          moved = true;
        }
      }
    });
    if (moved) _outbox.notifyLocalWrite();
  }

  /// A failed upload the server refused (bad/too large image): the photo is
  /// dropped. Anything else (offline, 5xx, expired session) is retried with backoff.
  static bool _isRejection(Failure f) => switch (f) {
    ValidationFailure() || NotFoundFailure() || ConflictFailure() => true,
    UnknownFailure(:final cause) =>
      cause is DioException &&
          (cause.response?.statusCode ?? 0) >= 400 &&
          (cause.response?.statusCode ?? 0) < 500,
    _ => false,
  };

  /// Uploads photos taken offline (food logs, transactions) before the push, then
  /// points the rows and their queued upserts at the returned URLs.
  Future<void> _uploadPendingPhotos(List<String> rejections) async {
    await _uploadFoodPhotos(rejections);
    await _uploadTransactionPhotos(rejections);
    await _uploadNoteMedia(rejections);
    await _uploadContentPhotos(rejections);
  }

  /// Uploads one pending file. Returns its URL, or null when it can never
  /// upload (the server refused it with a 4xx, or the file is gone) — the error
  /// is added to [rejections] and the caller drops it. Anything else (offline,
  /// 5xx, expired session) is rethrown and retried with backoff.
  ///
  /// [accept]: the returned path must match it (the server answers with the
  /// type it detected — e.g. an image sent as a voice clip comes back as
  /// `.jpg`); a mismatch is dropped too.
  Future<String?> _uploadOne(
    String path,
    String what,
    List<String> rejections, {
    RegExp? accept,
  }) async {
    if (!await _photos.exists(path)) {
      rejections.add('$what hilang dari perangkat, dilewati');
      return null;
    }
    try {
      final url = await _api.upload(path);
      if (accept != null && !accept.hasMatch(url)) {
        rejections.add('$what gagal diunggah: jenis file tidak didukung');
        return null;
      }
      return url;
    } on Failure catch (f) {
      if (!_isRejection(f)) rethrow;
      rejections.add('$what gagal diunggah: ${f.message}');
      return null;
    }
  }

  /// Notes with pending photos / voice clips: upload each file, swap it for its
  /// URL (a refused clip is dropped; its transcript is appended to the body so
  /// the words survive), then patch the queued upsert — or queue one. Uploaded
  /// files are deleted locally. On a retryable failure the files uploaded so far
  /// are kept and the error rethrown.
  Future<void> _uploadNoteMedia(List<String> rejections) async {
    final rows =
        await (_db.select(_db.notes)..where(
              (n) =>
                  n.photos.like('%"$localPhotoPrefix%') |
                  n.audio.like('%"local"%'),
            ))
            .get();
    for (final row in rows) {
      final note = row.toEntity();
      final pending = [
        for (final p in note.photos)
          if (p.isPending) (p.localPath!, 'Foto catatan', uploadImageRe),
        for (final a in note.audio)
          if (a.isPending) (a.localPath!, 'Rekaman suara', uploadAudioRe),
      ];
      if (pending.isEmpty) continue;
      final done = <String, String?>{};
      try {
        for (final (path, what, accept) in pending) {
          done[path] = await _uploadOne(path, what, rejections, accept: accept);
        }
      } finally {
        if (done.isNotEmpty) await _applyUploadedNoteMedia(row.id, done);
      }
    }
  }

  Future<void> _applyUploadedNoteMedia(
    String id,
    Map<String, String?> done,
  ) async {
    await _db.transaction(() async {
      final current = await (_db.select(
        _db.notes,
      )..where((n) => n.id.equals(id))).getSingleOrNull();
      if (current == null) return;
      final n = current.toEntity();
      final lost = <String>[];
      final photos = <TransactionPhoto>[
        for (final p in n.photos)
          if (!p.isPending || !done.containsKey(p.localPath))
            p
          else if (done[p.localPath] case final url?)
            TransactionPhoto.remote(url),
      ];
      final audio = <NoteAudio>[];
      for (final a in n.audio) {
        if (!a.isPending || !done.containsKey(a.localPath)) {
          audio.add(a);
        } else if (done[a.localPath] case final url?) {
          audio.add(
            NoteAudio.remote(
              url,
              durationSec: a.durationSec,
              transcript: a.transcript,
            ),
          );
        } else if (a.hasTranscript) {
          lost.add(a.transcript!.trim());
        }
      }
      final body = lost.isEmpty
          ? n.body
          : [
              if (n.body.trim().isNotEmpty) n.body.trimRight(),
              ...lost,
            ].join('\n\n');
      final updated = n.copyWith(photos: photos, audio: audio, body: body);
      await _db.into(_db.notes).insertOnConflictUpdate(updated.toCompanion());
      final wire = noteToWire(updated);
      if (await _outbox.pendingEntry(SyncEntity.notes, id) case final e?
          when e.op == MutationOp.upsert.name) {
        await _outbox.patchQueued(SyncEntity.notes, id, {
          'photos': wire['photos'],
          'audio': wire['audio'],
          if (lost.isNotEmpty) 'body': body,
        });
      } else {
        await _outbox.enqueueUpsert(
          entity: SyncEntity.notes,
          entityId: id,
          data: wire,
          clientUpdatedAt: _clock.now(),
          isCreate: false,
        );
      }
    });
    for (final path in done.keys) {
      await _photos.delete(path);
    }
  }

  /// Content items with pending photos: same flow as transactions.
  Future<void> _uploadContentPhotos(List<String> rejections) async {
    final rows = await (_db.select(
      _db.contentItems,
    )..where((i) => i.photos.like('%"$localPhotoPrefix%'))).get();
    for (final row in rows) {
      final pending = [
        for (final p in decodePhotos(row.photos))
          if (p.isPending) p.localPath!,
      ];
      if (pending.isEmpty) continue;
      final done = <String, String?>{};
      try {
        for (final path in pending) {
          done[path] = await _uploadOne(
            path,
            'Foto konten',
            rejections,
            accept: uploadImageRe,
          );
        }
      } finally {
        if (done.isNotEmpty) await _applyUploadedContentPhotos(row.id, done);
      }
    }
  }

  Future<void> _applyUploadedContentPhotos(
    String id,
    Map<String, String?> done,
  ) async {
    await _db.transaction(() async {
      final current = await (_db.select(
        _db.contentItems,
      )..where((i) => i.id.equals(id))).getSingleOrNull();
      if (current == null) return;
      final item = current.toEntity();
      final photos = <TransactionPhoto>[
        for (final p in item.photos)
          if (!p.isPending || !done.containsKey(p.localPath))
            p
          else if (done[p.localPath] case final url?)
            TransactionPhoto.remote(url),
      ];
      final updated = item.copyWith(photos: photos);
      await _db
          .into(_db.contentItems)
          .insertOnConflictUpdate(updated.toCompanion());
      final wire = contentItemToWire(updated);
      if (await _outbox.pendingEntry(SyncEntity.contentItems, id) case final e?
          when e.op == MutationOp.upsert.name) {
        await _outbox.patchQueued(SyncEntity.contentItems, id, {
          'photos': wire['photos'],
        });
      } else {
        await _outbox.enqueueUpsert(
          entity: SyncEntity.contentItems,
          entityId: id,
          data: wire,
          clientUpdatedAt: _clock.now(),
          isCreate: false,
        );
      }
    });
    for (final path in done.keys) {
      await _photos.delete(path);
    }
  }

  Future<void> _uploadFoodPhotos(List<String> rejections) async {
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
      } on Failure catch (f) {
        if (!_isRejection(f)) rethrow;
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

  /// Every transaction row with pending (`local:`) photos: upload each file, swap
  /// it for its URL (a refused one is dropped with an error), then patch the
  /// queued upsert — or queue one if the row has none (e.g. a photo added while
  /// the previous upsert was in flight). Uploaded files are deleted locally. On a
  /// retryable failure the photos uploaded so far are kept and the error rethrown.
  Future<void> _uploadTransactionPhotos(List<String> rejections) async {
    final rows = await (_db.select(
      _db.transactions,
    )..where((t) => t.photos.like('%"$localPhotoPrefix%'))).get();
    for (final row in rows) {
      final pending = [
        for (final p in decodePhotos(row.photos))
          if (p.isPending) p.localPath!,
      ];
      if (pending.isEmpty) continue;
      final done = <String, String?>{}; // local path → url (null = dropped)
      try {
        for (final path in pending) {
          done[path] = await _uploadOne(path, 'Foto transaksi', rejections);
        }
      } finally {
        if (done.isNotEmpty) await _applyUploadedTxPhotos(row.id, done);
      }
    }
  }

  Future<void> _applyUploadedTxPhotos(
    String id,
    Map<String, String?> done,
  ) async {
    await _db.transaction(() async {
      final current = await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final tx = current?.toEntityOrNull();
      if (current == null || tx == null) return;
      final photos = <TransactionPhoto>[
        for (final p in tx.photos)
          if (!p.isPending || !done.containsKey(p.localPath))
            p
          else if (done[p.localPath] case final url?)
            TransactionPhoto.remote(url),
      ];
      await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(photos: Value(encodePhotos(photos))),
      );
      final updated = tx.withPhotos(photos);
      if (await _outbox.pendingEntry(SyncEntity.transactions, id) case final e?
          when e.op == MutationOp.upsert.name) {
        await _outbox.patchQueued(SyncEntity.transactions, id, {
          'photos': wirePhotos(photos),
        });
      } else {
        final wire = transactionToWire(updated);
        await _outbox.enqueueUpsert(
          entity: SyncEntity.transactions,
          entityId: id,
          data: wire,
          clientUpdatedAt: _clock.now(),
          isCreate: false,
          base: wire, // same money fields: no pending balance effect
        );
      }
    });
    for (final path in done.keys) {
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
    if (res.changes.containsKey(SyncEntity.taskAreas)) {
      await _applyAreaRemaps();
      await _seedTaskAreas();
    }
    if (res.changes.containsKey(SyncEntity.noteLabels)) {
      await _applyLabelRemaps();
    }
    await _reconcileStages();
    // A notes/content-aware server seeds the default label and pillars itself
    // (once — never again after the user deleted them), so from now on the app
    // must not seed them locally (see SeedDefaultNoteLabel).
    final notesAware = res.changes.containsKey(SyncEntity.noteLabels);
    final contentAware = res.changes.containsKey(SyncEntity.contentPillars);
    if (notesAware || contentAware) {
      await _db.updateMeta(
        SyncMetaCompanion(
          notesSeeded: notesAware ? const Value(true) : const Value.absent(),
          contentSeeded: contentAware
              ? const Value(true)
              : const Value.absent(),
        ),
      );
    }
  }

  /// After the first pull from a server that knows tasks: when the user has no
  /// area at all, create the default ones (deterministic ids, so another device or
  /// the server seeding too can't duplicate them). Runs once per data owner.
  Future<void> _seedTaskAreas() async {
    final seeded = await _db.transaction(() async {
      final meta = await _db.getMeta();
      final userId = meta.userId;
      if (meta.tasksSeeded || userId == null) return false;
      await _db.updateMeta(const SyncMetaCompanion(tasksSeeded: Value(true)));
      if (await (_db.select(_db.taskAreas)..limit(1)).getSingleOrNull() !=
          null) {
        return false;
      }
      for (final a in defaultTaskAreas(userId, _clock.now())) {
        await _db.into(_db.taskAreas).insertOnConflictUpdate(a.toCompanion());
        await _outbox.enqueueUpsert(
          entity: SyncEntity.taskAreas,
          entityId: a.id,
          data: taskAreaToWire(a),
          // Oldest possible version: if the server already has these rows (same
          // deterministic ids, maybe edited on the web) LWW keeps the server's.
          clientUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          isCreate: true,
        );
      }
      return true;
    });
    if (seeded) _outbox.notifyLocalWrite();
  }

  /// Applies a pull. A [full] pull is the complete server state (and carries no
  /// tombstones), so local rows missing from it are deleted unless they have pending
  /// mutations.
  Future<void> _applyPull(PullResponse res, {required bool full}) async {
    _fullPull = full;
    final pending = <String, Set<String>>{
      for (final e in SyncEntity.all) e: await _outbox.idsWithEntries(e),
    };

    if (full) {
      // An entity missing from the response is unknown to that (older) server:
      // leave its local rows alone.
      for (final entity in SyncEntity.all.where(res.changes.containsKey)) {
        final keep = {
          for (final r in res.changes[entity] ?? const <Json>[])
            r['id'] as String,
          ...pending[entity]!,
          // Tasks waiting to move out of a duplicate area (see _areaRemaps).
          if (entity == SyncEntity.tasks && _areaRemaps.isNotEmpty)
            for (final t in await (_db.select(
              _db.tasks,
            )..where((t) => t.areaId.isIn(_areaRemaps.keys))).get())
              t.id,
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
      if (t.entity == SyncEntity.contentPosts) {
        final post = await (_db.select(
          _db.contentPosts,
        )..where((p) => p.id.equals(t.id))).getSingleOrNull();
        if (post != null) _stageChecks.add(post.contentId);
      }
      final pillarName = t.entity == SyncEntity.contentPillars
          ? (await (_db.select(
              _db.contentPillars,
            )..where((p) => p.id.equals(t.id))).getSingleOrNull())?.name
          : null;
      final n = await _deleteRow(t.entity, t.id);
      if (n == 0) continue;
      if (t.entity == SyncEntity.wallets) await _cascades.walletDeleted(t.id);
      if (t.entity == SyncEntity.categories) {
        await _cascades.categoryDeleted(t.id);
      }
      if (t.entity == SyncEntity.transactions) {
        await _cascades.transactionDeleted(t.id);
      }
      if (t.entity == SyncEntity.taskAreas) {
        await _cascades.taskAreaDeleted(t.id);
      }
      if (t.entity == SyncEntity.tasks) await _cascades.taskDeleted(t.id);
      if (t.entity == SyncEntity.notes) await _cascades.noteDeleted(t.id);
      if (t.entity == SyncEntity.noteLabels) {
        await _cascades.noteLabelDeleted(t.id);
      }
      if (t.entity == SyncEntity.contentItems) {
        await _cascades.contentItemDeleted(t.id);
      }
      if (t.entity == SyncEntity.socialAccounts) {
        await _cascades.socialAccountDeleted(t.id);
      }
      if (pillarName != null) await _cascades.pillarDeleted(pillarName);
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
        final local = await (_db.select(
          _db.transactions,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        await _db
            .into(_db.transactions)
            .insertOnConflictUpdate(
              transactionFromWire(
                j,
                keepPending: [
                  for (final p in decodePhotos(local?.photos))
                    if (p.isPending) p,
                ],
              ),
            );
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
      case SyncEntity.taskAreas:
        await _db
            .into(_db.taskAreas)
            .insertOnConflictUpdate(taskAreaFromWire(j));
      case SyncEntity.tasks:
        await _db.into(_db.tasks).insertOnConflictUpdate(taskFromWire(j));
      case SyncEntity.noteLabels:
        final label = noteLabelFromWire(j);
        // A local label with the same name but another id (created offline)
        // can't be kept: its notes move to the pulled one.
        for (final c in await _db.select(_db.noteLabels).get()) {
          if (c.id != id && nameKey(c.name) == nameKey(label.name)) {
            await _rememberLabelRemap(c.id, c.name);
            await _outbox.dropQueued(SyncEntity.noteLabels, c.id);
            await _deleteRow(SyncEntity.noteLabels, c.id);
          }
        }
        await _db
            .into(_db.noteLabels)
            .insertOnConflictUpdate(label.toCompanion());
      case SyncEntity.notes:
        final pulled = noteFromWire(j);
        final local = await (_db.select(
          _db.notes,
        )..where((n) => n.id.equals(id))).getSingleOrNull();
        final keep = local?.toEntity();
        // Never lose a photo/clip that hasn't been uploaded yet.
        final note = keep == null
            ? pulled
            : pulled.copyWith(
                photos: [
                  ...pulled.photos,
                  for (final p in keep.photos)
                    if (p.isPending) p,
                ],
                audio: [
                  ...pulled.audio,
                  for (final a in keep.audio)
                    if (a.isPending) a,
                ],
              );
        await _db.into(_db.notes).insertOnConflictUpdate(note.toCompanion());
      case SyncEntity.socialAccounts:
        await _db
            .into(_db.socialAccounts)
            .insertOnConflictUpdate(socialAccountFromWire(j).toCompanion());
      case SyncEntity.contentPillars:
        final pillar = contentPillarFromWire(j);
        for (final c in await _db.select(_db.contentPillars).get()) {
          if (c.id != id && nameKey(c.name) == nameKey(pillar.name)) {
            await _outbox.dropQueued(SyncEntity.contentPillars, c.id);
            await _deleteRow(SyncEntity.contentPillars, c.id);
          }
        }
        await _db
            .into(_db.contentPillars)
            .insertOnConflictUpdate(pillar.toCompanion());
      case SyncEntity.contentItems:
        final pulled = contentItemFromWire(j);
        final keep = (await (_db.select(
          _db.contentItems,
        )..where((i) => i.id.equals(id))).getSingleOrNull())?.toEntity();
        // Device-only stage log: stages first seen through a pull get the
        // row's updatedAt (the model has no per-stage timestamps).
        final item = pulled.copyWith(
          photos: [
            ...pulled.photos,
            for (final p in keep?.photos ?? const <TransactionPhoto>[])
              if (p.isPending) p,
          ],
          stageReachedAt: recordStage(
            keep?.stageReachedAt ?? const {},
            pulled.stage,
            pulled.updatedAt,
          ),
          sponsorPaidAt: recordSponsorPaid(keep, pulled, pulled.updatedAt),
        );
        await _db
            .into(_db.contentItems)
            .insertOnConflictUpdate(item.toCompanion());
      case SyncEntity.contentPosts:
        final post = contentPostFromWire(j);
        final before = await (_db.select(
          _db.contentPosts,
        )..where((p) => p.id.equals(id))).getSingleOrNull();
        // A post new to this device counts only on incremental pulls: a full
        // pull (sign-in, upgrade, reset) must not undo stages the user moved
        // back by hand.
        if (before == null
            ? !_fullPull
            : before.status != post.status.wire ||
                  before.contentId != post.contentId) {
          _stageChecks.add(post.contentId);
          if (before != null) _stageChecks.add(before.contentId);
        }
        await _db
            .into(_db.contentPosts)
            .insertOnConflictUpdate(post.toCompanion());
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
    SyncEntity.taskAreas => _db.taskAreas,
    SyncEntity.tasks => _db.tasks,
    SyncEntity.noteLabels => _db.noteLabels,
    SyncEntity.notes => _db.notes,
    SyncEntity.socialAccounts => _db.socialAccounts,
    SyncEntity.contentPillars => _db.contentPillars,
    SyncEntity.contentItems => _db.contentItems,
    SyncEntity.contentPosts => _db.contentPosts,
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
