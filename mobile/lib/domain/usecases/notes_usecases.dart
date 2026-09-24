/// Notes use cases — `docs/notes.md`. Rules: `notes_rules.dart`.
library;

import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'content_usecases.dart' show ContentItemInput, CreateContentItem;
import 'notes_rules.dart';
import 'task_usecases.dart' show CreateTask, TaskInput;
import 'transaction_usecases.dart' show CreateTransaction, TransactionInput;

// ================================================================ input

/// Form data of a note.
final class NoteInput {
  const NoteInput({
    this.title,
    this.body = '',
    this.checklist = const [],
    this.labelIds = const [],
    this.color,
    this.pinned = false,
    this.archived = false,
    this.photos,
    this.audio,
    this.links,
    this.source,
  });

  /// ≤ 200, one line; blank = untitled.
  final String? title;

  /// Markdown subset, ≤ 50 000 chars. URLs are added to `links` automatically.
  final String body;

  /// ≤ 200 items; build/edit with `checklistAdd`, `checklistToggle`, … (ids =
  /// `newId()`).
  final List<ChecklistItem> checklist;

  /// ≤ 20 label ids.
  final List<String> labelIds;

  /// Palette id (`noteColors`), null = default.
  final String? color;
  final bool pinned;
  final bool archived;

  /// ≤ 10. `TransactionPhoto.local(pickedFile.path)` for new ones. Null = none
  /// on create, unchanged on update.
  final List<TransactionPhoto>? photos;

  /// ≤ 5. `NoteAudio.local(recording.path, durationSec:, transcript:)` for new
  /// ones. Null = none on create, unchanged on update.
  final List<NoteAudio>? audio;

  /// Shared links (not from the body). Null = keep the current ones (update);
  /// body URLs are always merged in.
  final List<NoteLink>? links;
  final NoteSource? source;
}

/// A recorded clip to attach.
final class NoteAudioInput {
  const NoteAudioInput({
    required this.path,
    required this.durationSec,
    this.transcript,
  });

  /// The recorded file (m4a/aac). Copied into app storage; uploads on sync.
  final String path;
  final int durationSec;

  /// On-device transcription (id-ID), if any.
  final String? transcript;
}

/// Content shared into the app (Android share target).
final class SharedNoteInput {
  const SharedNoteInput({this.text, this.subject, this.imagePaths = const []});

  /// Shared text / URL.
  final String? text;

  /// EXTRA_SUBJECT (page title), used as the note title.
  final String? subject;

  /// Shared images (≤ 10 kept).
  final List<String> imagePaths;
}

// ================================================================ validation

String? _title(String? v) {
  if (v == null) return null;
  final t = cleanLine(v);
  if (t.isEmpty) return null;
  if (t.length > noteTitleMax) {
    throw const ValidationFailure(
      'Judul terlalu panjang (maks $noteTitleMax)',
      field: 'title',
    );
  }
  return t;
}

String _body(String v) {
  final b = cleanText(v);
  if (b.length > noteBodyMax) {
    throw const ValidationFailure(
      'Isi catatan terlalu panjang (maks 50.000 karakter)',
      field: 'body',
    );
  }
  return b;
}

String? _color(String? v) {
  if (v == null || v.isEmpty) return null;
  if (noteColorById(v) == null) {
    throw const ValidationFailure('Warna catatan tidak valid', field: 'color');
  }
  return v;
}

/// ≤ [max] photos, duplicates dropped (first wins), order kept.
List<TransactionPhoto> validateMediaPhotos(
  List<TransactionPhoto> photos, {
  int max = maxNotePhotos,
}) {
  final out = <TransactionPhoto>[];
  for (final p in photos) {
    if (!out.contains(p)) out.add(p);
  }
  if (out.length > max) {
    throw ValidationFailure('Maksimal $max foto', field: 'photos');
  }
  return List.unmodifiable(out);
}

List<NoteAudio> _audio(List<NoteAudio> clips) {
  final out = <NoteAudio>[];
  for (final a in clips) {
    if (out.any((x) => x.url == a.url && x.localPath == a.localPath)) continue;
    if (a.durationSec < 0 || a.durationSec > audioDurationMax) {
      throw const ValidationFailure(
        'Rekaman maksimal 10 menit',
        field: 'audio',
      );
    }
    final t = a.transcript == null ? null : cleanText(a.transcript!).trim();
    if (t != null && t.length > transcriptMax) {
      throw const ValidationFailure(
        'Transkrip terlalu panjang (maks $transcriptMax)',
        field: 'audio',
      );
    }
    out.add(a.withTranscript(t == null || t.isEmpty ? null : t));
  }
  if (out.length > maxNoteAudio) {
    throw const ValidationFailure(
      'Maksimal $maxNoteAudio rekaman suara',
      field: 'audio',
    );
  }
  return List.unmodifiable(out);
}

Note _build(
  String id,
  NoteInput i, {
  required Note? old,
  required DateTime now,
}) {
  final body = _body(i.body);
  final links = i.links != null
      ? mergeLinks(i.links!, body, stored: old?.links ?? const [])
      : old == null
      ? mergeLinks(const [], body)
      : syncBodyLinks(old.links, old.body, body);
  return Note(
    id: id,
    title: _title(i.title),
    body: body,
    checklist: normalizeChecklist(i.checklist),
    labelIds: normalizeLabelIds(i.labelIds),
    color: _color(i.color),
    pinned: i.pinned,
    archived: i.archived,
    photos: validateMediaPhotos(i.photos ?? old?.photos ?? const []),
    audio: _audio(i.audio ?? old?.audio ?? const []),
    links: links,
    source: old?.source ?? i.source,
    linkedTaskId: old?.linkedTaskId,
    linkedContentId: old?.linkedContentId,
    linkedTransactionId: old?.linkedTransactionId,
    createdAt: old?.createdAt ?? now,
    updatedAt: now,
  );
}

Future<Note> _require(NoteRepository notes, String id) async {
  final n = await notes.getById(id);
  if (n == null) throw const NotFoundFailure('Catatan tidak ditemukan');
  return n;
}

/// Saves and returns the stored version (pending files now in app storage).
Future<Note> _save(NoteRepository notes, Note n) async {
  await notes.save(n);
  return await notes.getById(n.id) ?? n;
}

// ================================================================ notes CRUD

/// Creates a note. A completely blank note (no title, body, checklist, photo,
/// clip or link) is refused with `ValidationFailure(field: 'empty')` — the
/// editor should just discard it.
final class CreateNote {
  const CreateNote(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(NoteInput input) => guard(() async {
    final n = _build(newId(), input, old: null, now: _clock.now());
    if (n.isBlank) {
      throw const ValidationFailure('Catatan masih kosong', field: 'empty');
    }
    return _save(_notes, n);
  });
}

/// Creates a note from shared text/URL/images (`source = share`): title =
/// subject, body = text (its URLs become links), images attached.
final class CreateNoteFromShare {
  const CreateNoteFromShare(this._create);
  final CreateNote _create;

  Future<Result<Note>> call(SharedNoteInput input) {
    final text = input.text?.trim() ?? '';
    final subject = input.subject?.trim();
    final paths = input.imagePaths.length > maxNotePhotos
        ? input.imagePaths.sublist(0, maxNotePhotos)
        : input.imagePaths;
    return _create(
      NoteInput(
        title: subject != null && subject.isNotEmpty && subject != text
            ? (subject.length > noteTitleMax
                  ? subject.substring(0, noteTitleMax)
                  : subject)
            : null,
        body: text.length > noteBodyMax ? text.substring(0, noteBodyMax) : text,
        photos: [for (final p in paths) TransactionPhoto.local(p)],
        source: NoteSource.share,
      ),
    );
  }
}

/// Full edit (the editor's save on back). Keeps links to task/content/
/// transaction and the capture source; `photos`/`audio` null = unchanged.
final class UpdateNote {
  const UpdateNote(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, NoteInput input) => guard(() async {
    final old = await _require(_notes, id);
    final n = _build(id, input, old: old, now: _clock.now());
    if (n == old.copyWith(updatedAt: n.updatedAt)) return old; // no change
    return _save(_notes, n);
  });
}

/// Deletes a note for good (confirm first; archive is the soft option). Its
/// pending files are deleted; content items made from it keep existing
/// (`noteId = null`).
final class DeleteNote {
  const DeleteNote(this._notes);
  final NoteRepository _notes;

  Future<Result<void>> call(String id) => guard(() async {
    await _require(_notes, id);
    await _notes.delete(id);
  });
}

/// Applies [change] to note [id] and saves it (updatedAt = now).
Future<Result<Note>> _patch(
  NoteRepository notes,
  Clock clock,
  String id,
  Note Function(Note n) change,
) => guard(() async {
  final n = await _require(notes, id);
  final u = change(n);
  if (u == n) return n;
  return _save(notes, u.copyWith(updatedAt: clock.now()));
});

final class SetNotePinned {
  const SetNotePinned(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, bool pinned) =>
      _patch(_notes, _clock, id, (n) => n.copyWith(pinned: pinned));
}

/// Archiving also unpins (like Keep); unarchiving keeps it unpinned.
final class SetNoteArchived {
  const SetNoteArchived(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, bool archived) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(archived: archived, pinned: archived ? false : n.pinned),
  );
}

/// [color] = palette id (`noteColors`) or null (default card).
final class SetNoteColor {
  const SetNoteColor(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, String? color) =>
      _patch(_notes, _clock, id, (n) => n.copyWith(color: _color(color)));
}

/// Replaces the note's labels (≤ 20).
final class SetNoteLabels {
  const SetNoteLabels(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, List<String> labelIds) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(labelIds: normalizeLabelIds(labelIds)),
  );
}

/// Adds/removes one label (label chips).
final class ToggleNoteLabel {
  const ToggleNoteLabel(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, String labelId) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(
      labelIds: normalizeLabelIds(toggleLabelId(n.labelIds, labelId)),
    ),
  );
}

/// Replaces the checklist (after `checklistAdd`/`checklistMove`/… on the
/// current list).
final class SetNoteChecklist {
  const SetNoteChecklist(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, List<ChecklistItem> items) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(checklist: normalizeChecklist(items)),
  );
}

/// Ticks/unticks one checklist item (from the list card too).
final class ToggleNoteChecklistItem {
  const ToggleNoteChecklistItem(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, String itemId) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(checklist: checklistToggle(n.checklist, itemId)),
  );
}

// ---------------------------------------------------------------- photos & audio

/// Appends picked photos (file paths); they show at once and upload on sync.
/// Beyond 10 → `ValidationFailure(field: 'photos')`.
final class AddNotePhotos {
  const AddNotePhotos(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, List<String> filePaths) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(
      photos: validateMediaPhotos([
        ...n.photos,
        for (final p in filePaths) TransactionPhoto.local(p),
      ]),
    ),
  );
}

/// Removes one photo (uploaded or pending; a pending file is deleted at once,
/// the server deletes an uploaded one).
final class RemoveNotePhoto {
  const RemoveNotePhoto(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, TransactionPhoto photo) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(
      photos: [
        for (final p in n.photos)
          if (p != photo) p,
      ],
    ),
  );
}

/// Replaces the photo list (reorder).
final class SetNotePhotos {
  const SetNotePhotos(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, List<TransactionPhoto> photos) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(photos: validateMediaPhotos(photos)),
  );
}

/// Attaches a recorded clip (pending upload) with its transcript. Beyond 5
/// clips or 10 minutes → `ValidationFailure(field: 'audio')`.
final class AddNoteAudio {
  const AddNoteAudio(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, NoteAudioInput clip) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(
      audio: _audio([
        ...n.audio,
        NoteAudio.local(
          clip.path,
          durationSec: clip.durationSec,
          transcript: clip.transcript,
        ),
      ]),
    ),
  );
}

/// Removes one clip (uploaded or pending).
final class RemoveNoteAudio {
  const RemoveNoteAudio(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, NoteAudio clip) => _patch(
    _notes,
    _clock,
    id,
    (n) => n.copyWith(
      audio: [
        for (final a in n.audio)
          if (a != clip) a,
      ],
    ),
  );
}

/// Edits (or clears with null) a clip's transcript.
final class SetNoteAudioTranscript {
  const SetNoteAudioTranscript(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, NoteAudio clip, String? transcript) =>
      _patch(
        _notes,
        _clock,
        id,
        (n) => n.copyWith(
          audio: _audio([
            for (final a in n.audio)
              a == clip ? a.withTranscript(transcript) : a,
          ]),
        ),
      );
}

/// "Masukkan ke catatan": appends the clip's transcript to the body.
final class InsertTranscriptIntoBody {
  const InsertTranscriptIntoBody(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String id, NoteAudio clip) =>
      _patch(_notes, _clock, id, (n) {
        final t = clip.transcript?.trim() ?? '';
        if (t.isEmpty) return n;
        final body = n.body.trim().isEmpty ? t : '${n.body.trimRight()}\n\n$t';
        return n.copyWith(
          body: _body(body),
          links: syncBodyLinks(n.links, n.body, body),
        );
      });
}

// ================================================================ labels

/// Form data of a label.
final class NoteLabelInput {
  const NoteLabelInput({
    required this.name,
    this.color = defaultLabelColor,
    this.pinnedTab = false,
  });

  /// 1–30, unique (case-insensitive).
  final String name;
  final String color;

  /// Show as a tab.
  final bool pinnedTab;
}

String _labelColor(String c) {
  if (!isHexColor(c)) {
    throw const ValidationFailure('Warna tidak valid', field: 'color');
  }
  return c;
}

/// Creates a label at the end of the order.
final class CreateNoteLabel {
  const CreateNoteLabel(this._labels, this._clock);
  final NoteLabelRepository _labels;
  final Clock _clock;

  Future<Result<NoteLabel>> call(NoteLabelInput input) => guard(() async {
    final all = await _labels.getAll();
    final now = _clock.now();
    final l = NoteLabel(
      id: newId(),
      name: validateLabelName(input.name, all),
      color: _labelColor(input.color),
      pinnedTab: input.pinnedTab,
      sortOrder: all.isEmpty
          ? 0
          : all.map((x) => x.sortOrder).reduce((a, b) => a > b ? a : b) + 1,
      createdAt: now,
      updatedAt: now,
    );
    await _labels.save(l);
    return l;
  });
}

/// Rename / recolor / tab toggle (keeps the order). Notes keep their label ids.
final class UpdateNoteLabel {
  const UpdateNoteLabel(this._labels, this._clock);
  final NoteLabelRepository _labels;
  final Clock _clock;

  Future<Result<NoteLabel>> call(String id, NoteLabelInput input) =>
      guard(() async {
        final all = await _labels.getAll();
        final old = all.where((l) => l.id == id).firstOrNull;
        if (old == null) throw const NotFoundFailure('Label tidak ditemukan');
        final l = old.copyWith(
          name: validateLabelName(input.name, all, exceptId: id),
          color: _labelColor(input.color),
          pinnedTab: input.pinnedTab,
          updatedAt: _clock.now(),
        );
        await _labels.save(l);
        return l;
      });
}

/// Shows/hides a label as a tab.
final class SetNoteLabelPinnedTab {
  const SetNoteLabelPinnedTab(this._labels, this._clock);
  final NoteLabelRepository _labels;
  final Clock _clock;

  Future<Result<NoteLabel>> call(String id, bool pinnedTab) => guard(() async {
    final l = await _labels.getById(id);
    if (l == null) throw const NotFoundFailure('Label tidak ditemukan');
    if (l.pinnedTab == pinnedTab) return l;
    final u = l.copyWith(pinnedTab: pinnedTab, updatedAt: _clock.now());
    await _labels.save(u);
    return u;
  });
}

/// `[ids in new order]` → sortOrder = index.
final class ReorderNoteLabels {
  const ReorderNoteLabels(this._labels, this._uow, this._clock);
  final NoteLabelRepository _labels;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final l = await _labels.getById(id);
        if (l == null || l.sortOrder == i) continue;
        await _labels.save(l.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

/// Deletes a label; its id is removed from every note (confirm in the UI).
final class DeleteNoteLabel {
  const DeleteNoteLabel(this._labels);
  final NoteLabelRepository _labels;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _labels.getById(id) == null) {
      throw const NotFoundFailure('Label tidak ditemukan');
    }
    await _labels.delete(id);
  });
}

/// Offline fallback: creates the default "Ide Konten" label (deterministic id)
/// when there is none (by id or name) **and** no pull from a notes-aware server
/// has succeeded yet — after that the server owns it (seeded once, never
/// re-created after the user deleted it). Call it when the Notes screen opens.
/// Returns 1 when created. The row is pushed as the oldest possible version, so
/// a server copy (or its tombstone) always wins.
final class SeedDefaultNoteLabel {
  const SeedDefaultNoteLabel(this._labels, this._seedState, this._clock);
  final NoteLabelRepository _labels;
  final DefaultsSeedState _seedState;
  final Clock _clock;

  Future<Result<int>> call(String userId) => guard(() async {
    if (userId.isEmpty || await _seedState.notesServerSeeded()) return 0;
    if (findIdeaLabel(await _labels.getAll()) != null) return 0;
    await _labels.save(
      defaultNoteLabel(userId, _clock.now()).copyWith(updatedAt: seedVersion),
    );
    return 1;
  });
}

/// `updatedAt` of rows seeded locally as a fallback: the oldest possible
/// version, so last-write-wins always keeps the server's copy.
final seedVersion = DateTime.fromMillisecondsSinceEpoch(0);

// ================================================================ conversions

/// "→ Tugas" options. [title] null = the note's title or first line.
final class NoteTaskInput {
  const NoteTaskInput({
    required this.areaId,
    this.bucket = TaskBucket.want,
    this.title,
    this.dueDate,
    this.dueTime,
    this.remindBefore,
  });

  final String areaId;
  final TaskBucket bucket;
  final String? title;
  final DateTime? dueDate;
  final String? dueTime;
  final int? remindBefore;
}

/// Converts a note into a task (title = `noteActionTitle`, task note = the body
/// as plain text ≤ 2000 — `bodyExcerpt`) through [CreateTask] and links it
/// (`linkedTaskId`).
/// The note stays. All-or-nothing.
final class ConvertNoteToTask {
  const ConvertNoteToTask(
    this._notes,
    this._createTask,
    this._uow,
    this._clock,
  );
  final NoteRepository _notes;
  final CreateTask _createTask;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<({Note note, Task task})>> call(
    String noteId,
    NoteTaskInput input,
  ) => guard(
    () => _uow.run(() async {
      final n = await _require(_notes, noteId);
      final excerpt = bodyExcerpt(n.body, max: 2000);
      final task = (await _createTask(
        TaskInput(
          areaId: input.areaId,
          title: input.title?.trim().isNotEmpty == true
              ? input.title!
              : noteActionTitle(n),
          note: excerpt.isEmpty ? null : excerpt,
          bucket: input.bucket,
          dueDate: input.dueDate,
          dueTime: input.dueTime,
          remindBefore: input.remindBefore,
        ),
      )).valueOrThrow;
      final note = await _save(
        _notes,
        n.copyWith(linkedTaskId: task.id, updatedAt: _clock.now()),
      );
      return (note: note, task: task);
    }),
  );
}

/// "Jadikan konten": creates a content item at `ide` (title =
/// `noteActionTitle`, idea = body, checklist and photos copied, `noteId` = the
/// note) and sets `note.linkedContentId`. Idempotent: a note
/// already linked to an existing item returns that item.
final class ConvertNoteToContent {
  const ConvertNoteToContent(
    this._notes,
    this._items,
    this._createItem,
    this._uow,
    this._clock,
  );
  final NoteRepository _notes;
  final ContentItemRepository _items;
  final CreateContentItem _createItem;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<({Note note, ContentItem item})>> call(
    String noteId, {
    ContentFormat? format,
    String? pillar,
    String? title,
  }) => guard(
    () => _uow.run(() async {
      final n = await _require(_notes, noteId);
      if (n.linkedContentId != null) {
        final existing = await _items.getById(n.linkedContentId!);
        if (existing != null) return (note: n, item: existing);
      }
      final item = (await _createItem(
        ContentItemInput(
          title: title?.trim().isNotEmpty == true
              ? title!
              : noteActionTitle(n, max: contentTitleMax),
          format: format,
          pillar: pillar,
          idea: n.body,
          noteId: n.id,
          checklist: n.checklist,
          photos: n.photos,
        ),
      )).valueOrThrow;
      final note = await _save(
        _notes,
        n.copyWith(linkedContentId: item.id, updatedAt: _clock.now()),
      );
      return (note: note, item: item);
    }),
  );
}

/// "→ Transaksi": after the user confirmed the form prefilled with
/// `noteTransactionDraft(note)`, records it through [CreateTransaction] and
/// links it (`linkedTransactionId`). All-or-nothing.
final class ConvertNoteToTransaction {
  const ConvertNoteToTransaction(
    this._notes,
    this._createTx,
    this._uow,
    this._clock,
  );
  final NoteRepository _notes;
  final CreateTransaction _createTx;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<({Note note, Transaction transaction})>> call(
    String noteId,
    TransactionInput input,
  ) => guard(
    () => _uow.run(() async {
      final n = await _require(_notes, noteId);
      final tx = (await _createTx(input)).valueOrThrow;
      final note = await _save(
        _notes,
        n.copyWith(linkedTransactionId: tx.id, updatedAt: _clock.now()),
      );
      return (note: note, transaction: tx);
    }),
  );
}

/// Links an already recorded transaction to a note (when the UI saved the
/// transaction form itself). Null unlinks.
final class LinkNoteTransaction {
  const LinkNoteTransaction(this._notes, this._clock);
  final NoteRepository _notes;
  final Clock _clock;

  Future<Result<Note>> call(String noteId, String? transactionId) => _patch(
    _notes,
    _clock,
    noteId,
    (n) => n.copyWith(linkedTransactionId: transactionId),
  );
}

// ================================================================ reading

List<NoteView> _views(List<Note> notes, List<NoteLabel> labels) {
  final byId = {for (final l in labels) l.id: l};
  return [
    for (final n in notes)
      NoteView(note: n, labels: [for (final id in n.labelIds) ?byId[id]]),
  ];
}

/// The notes list for [filter] (search in SQL: every word must match title,
/// body, checklist, transcripts or link titles/URLs), pinned first then newest.
final class WatchNotes {
  const WatchNotes(this._notes, this._labels);
  final NoteRepository _notes;
  final NoteLabelRepository _labels;

  Stream<List<NoteView>> call([NoteFilter filter = NoteFilter.all]) =>
      combineLatest2(
        _notes.watch(
          archived: filter.archived,
          labelId: filter.labelId,
          search: filter.search,
        ),
        _labels.watchAll(),
        _views,
      );
}

/// One note with its labels; null when deleted.
final class WatchNote {
  const WatchNote(this._notes, this._labels);
  final NoteRepository _notes;
  final NoteLabelRepository _labels;

  Stream<NoteView?> call(String id) => combineLatest2(
    _notes.watchById(id),
    _labels.watchAll(),
    (Note? n, List<NoteLabel> l) => n == null ? null : _views([n], l).single,
  );
}

/// Labels in order (`pinnedOnly` = the tabs).
final class WatchNoteLabels {
  const WatchNoteLabels(this._labels);
  final NoteLabelRepository _labels;

  Stream<List<NoteLabel>> call({bool pinnedOnly = false}) =>
      _labels.watchAll().map(
        (l) => [
          for (final x in [...l]..sort(compareLabels))
            if (!pinnedOnly || x.pinnedTab) x,
        ],
      );
}
