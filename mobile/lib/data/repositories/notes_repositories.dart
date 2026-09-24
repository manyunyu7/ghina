import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/notes_rules.dart' show searchWords;
import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/notes_content_mappers.dart';
import '../models/notes_content_wire.dart';
import 'local_store.dart';
import 'photo_store.dart';

/// `%substring%` with LIKE wildcards in [substring] escaped (escape char `\`).
Expression<bool> likeSubstring(
  GeneratedColumn<String> column,
  String substring,
) {
  final esc = substring
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return column.like('%$esc%', escapeChar: r'\');
}

/// Local paths of pending photos and clips.
Set<String> pendingPhotoPaths(Iterable<TransactionPhoto> photos) => {
  for (final p in photos)
    if (p.isPending) p.localPath!,
};

Set<String> pendingAudioPaths(Iterable<NoteAudio> clips) => {
  for (final a in clips)
    if (a.isPending) a.localPath!,
};

/// Copies newly picked pending photos (not in [known]) into [folder].
Future<List<TransactionPhoto>> storePendingPhotos(
  PhotoStore store,
  List<TransactionPhoto> photos,
  Set<String> known,
  String id,
  String folder,
) async => [
  for (final p in photos)
    p.isPending && !known.contains(p.localPath)
        ? TransactionPhoto.local(
            await store.ensureStoredIn(p.localPath!, id, folder),
          )
        : p,
];

class DriftNoteRepository implements NoteRepository {
  DriftNoteRepository(this._s, [PhotoStore? media])
    : _media = media ?? InMemoryPhotoStore();
  final LocalStore _s;
  final PhotoStore _media;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$NotesTable, NoteRow> _q({
    bool? archived,
    String? labelId,
    String? search,
  }) {
    final q = _db.select(_db.notes)
      ..orderBy([
        (n) => OrderingTerm.desc(n.pinned),
        (n) => OrderingTerm.desc(n.updatedAt),
        (n) => OrderingTerm.asc(n.id),
      ]);
    if (archived != null) q.where((n) => n.archived.equals(archived));
    if (labelId != null) q.where((n) => likeSubstring(n.labels, '"$labelId"'));
    for (final w in searchWords(search)) {
      q.where((n) => likeSubstring(n.searchText, w));
    }
    return q;
  }

  @override
  Stream<List<Note>> watch({bool? archived, String? labelId, String? search}) =>
      _q(
        archived: archived,
        labelId: labelId,
        search: search,
      ).watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Stream<List<Note>> watchAll() =>
      _q().watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<Note>> getAll() async => [
    for (final x in await _q().get()) x.toEntity(),
  ];

  @override
  Stream<Note?> watchById(String id) =>
      (_db.select(_db.notes)..where((n) => n.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<Note?> getById(String id) async => (await (_db.select(
    _db.notes,
  )..where((n) => n.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(Note note) async {
    final before = await getById(note.id);
    final oldPhotos = pendingPhotoPaths(before?.photos ?? const []);
    final oldAudio = pendingAudioPaths(before?.audio ?? const []);
    // Copy newly picked/recorded files into app storage (outside the DB tx).
    final row = note.copyWith(
      photos: await storePendingPhotos(
        _media,
        note.photos,
        oldPhotos,
        note.id,
        MediaFolder.notePhotos,
      ),
      audio: [
        for (final a in note.audio)
          a.isPending && !oldAudio.contains(a.localPath)
              ? NoteAudio.local(
                  await _media.ensureStoredIn(
                    a.localPath!,
                    note.id,
                    MediaFolder.noteAudio,
                  ),
                  durationSec: a.durationSec,
                  transcript: a.transcript,
                )
              : a,
      ],
    );
    await _s.write(() async {
      final exists = await getById(row.id) != null;
      await _db.into(_db.notes).insertOnConflictUpdate(row.toCompanion());
      await _s.outbox.enqueueUpsert(
        entity: SyncEntity.notes,
        entityId: row.id,
        data: noteToWire(row),
        clientUpdatedAt: row.updatedAt,
        isCreate: !exists,
      );
    });
    final keep = {
      ...pendingPhotoPaths(row.photos),
      ...pendingAudioPaths(row.audio),
    };
    for (final path in {...oldPhotos, ...oldAudio}.difference(keep)) {
      await _media.delete(path);
    }
  }

  @override
  Future<void> delete(String id) async {
    final existing = await getById(id);
    if (existing == null) return;
    await _s.write(() async {
      final n = await (_db.delete(
        _db.notes,
      )..where((x) => x.id.equals(id))).go();
      if (n == 0) return;
      await _s.cascades.noteDeleted(id);
      await _s.outbox.enqueueDelete(
        entity: SyncEntity.notes,
        entityId: id,
        clientUpdatedAt: _s.clock.now(),
      );
    });
    for (final path in {
      ...pendingPhotoPaths(existing.photos),
      ...pendingAudioPaths(existing.audio),
    }) {
      await _media.delete(path);
    }
  }
}

class DriftNoteLabelRepository implements NoteLabelRepository {
  DriftNoteLabelRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$NoteLabelsTable, NoteLabelRow> get _all =>
      _db.select(_db.noteLabels)..orderBy([
        (l) => OrderingTerm.asc(l.sortOrder),
        (l) => OrderingTerm.asc(l.name.lower()),
      ]);

  @override
  Stream<List<NoteLabel>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<NoteLabel>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Future<NoteLabel?> getById(String id) async => (await (_db.select(
    _db.noteLabels,
  )..where((l) => l.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(NoteLabel label) => _s.write(() async {
    final exists = await getById(label.id) != null;
    await _db.into(_db.noteLabels).insertOnConflictUpdate(label.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.noteLabels,
      entityId: label.id,
      data: noteLabelToWire(label),
      clientUpdatedAt: label.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.noteLabels,
    )..where((l) => l.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.noteLabelDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.noteLabels,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

/// [DefaultsSeedState] from the sync meta flags (set after the first pull from
/// a notes/content-aware server).
class DriftDefaultsSeedState implements DefaultsSeedState {
  DriftDefaultsSeedState(this._db);
  final AppDatabase _db;

  @override
  Future<bool> notesServerSeeded() async => (await _db.getMeta()).notesSeeded;

  @override
  Future<bool> contentServerSeeded() async =>
      (await _db.getMeta()).contentSeeded;
}
