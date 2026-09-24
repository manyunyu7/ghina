import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/ids.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/services/services.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/platform/platform_state.dart';
import '../markdown_edit.dart';
import '../note_actions.dart';
import '../note_draft.dart';
import '../widgets/audio_clip_tile.dart';
import '../widgets/checklist_editor.dart';
import '../widgets/color_palette.dart';
import '../widgets/dictation_bar.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/link_open.dart';
import '../widgets/mic_permission.dart';
import '../widgets/note_markdown.dart';
import '../widgets/note_visuals.dart';
import '../widgets/voice_recorder_sheet.dart';

enum _Save { idle, pending, saving, saved, error }

/// Note editor (docs/notes.md): title, Markdown body with a compact toolbar
/// and preview, checklist, labels, color, pin, archive, photos, voice clips
/// ("Rekam suara") and dictation ("Dikte"), links, autosave, convert menu.
///
/// New notes (`id == null`) are created on the first real change; a note left
/// blank is discarded on back (an existing one emptied out is deleted).
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, this.id, this.draft});

  /// Null when creating a new item.
  final String? id;

  /// Starting values for a new note (else read from the route's `extra`).
  final NoteDraft? draft;

  /// Autosave debounce.
  static const autosaveDelay = Duration(milliseconds: 800);

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _checkKey = GlobalKey<ChecklistEditorState>();

  String? _id;
  bool _loaded = false;
  List<ChecklistItem> _checklist = const [];
  List<String> _labelIds = const [];
  String? _color;
  bool _pinned = false;
  bool _archived = false;
  NoteSource _source = NoteSource.quick;

  bool _preview = false;
  bool _dirty = false;
  bool _deleted = false;
  bool _closing = false;
  _Save _save = _Save.idle;
  Timer? _debounce;
  Future<void> _chain = Future.value();
  int _dictInserted = 0;

  /// Bumped on every edit — tells whether a save's snapshot is still current.
  int _rev = 0;

  // Captured so a last save can run from dispose (no ref there).
  late final CreateNote _createNote;
  late final UpdateNote _updateNote;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _createNote = ref.read(createNoteProvider);
    _updateNote = ref.read(updateNoteProvider);
    _lifecycle = AppLifecycleListener(onPause: () => _flush());
    _id = widget.id;
    if (widget.id != null) {
      ref.listenManual(watchNoteProvider(widget.id!), (_, next) {
        final v = next.value;
        if (!_loaded && v != null) setState(() => _load(v.note));
      }, fireImmediately: true);
    } else {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyDraft());
    }
  }

  void _applyDraft() {
    if (!mounted) return;
    var draft = widget.draft;
    if (draft == null) {
      try {
        final extra = GoRouterState.of(context).extra;
        if (extra is NoteDraft) draft = extra;
      } catch (_) {}
    }
    setState(() {
      if (draft != null) {
        _labelIds = [...draft.labelIds];
        _source = draft.source;
        if (draft.checklist) {
          final id = newId();
          _checklist = checklistAdd(const [], '', id: id);
          _checkKey.currentState?.focusItem(id);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _checkKey.currentState?.focusItem(id),
          );
          return;
        }
      }
      _bodyFocus.requestFocus();
    });
  }

  void _load(Note n) {
    _title.text = n.title ?? '';
    _body.text = n.body;
    _checklist = n.checklist;
    _labelIds = n.labelIds;
    _color = n.color;
    _pinned = n.pinned;
    _archived = n.archived;
    _source = n.source ?? NoteSource.quick;
    _loaded = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lifecycle.dispose();
    if (_dirty && !_deleted) {
      // Left without the back handler (route replaced): best-effort save,
      // after any save still in flight — a create running now sets [_id], so
      // this updates that note instead of creating a second one.
      final input = _input();
      final create = _createNote, update = _updateNote;
      unawaited(
        _chain.then((_) async {
          if (_deleted) return;
          final id = _id;
          if (id != null) {
            await update(id, input);
          } else if (!_isBlankInput(input)) {
            await create(input);
          }
        }),
      );
    }
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ saving

  NoteInput _input({List<TransactionPhoto>? photos, List<NoteAudio>? audio}) =>
      NoteInput(
        title: _title.text,
        body: _body.text,
        checklist: _checklist,
        labelIds: _labelIds,
        color: _color,
        pinned: _pinned,
        archived: _archived,
        photos: photos,
        audio: audio,
        source: _source,
      );

  bool _isBlankInput(NoteInput i) =>
      (i.title ?? '').trim().isEmpty &&
      i.body.trim().isEmpty &&
      i.checklist.every((c) => c.text.trim().isEmpty) &&
      (i.photos ?? const []).isEmpty &&
      (i.audio ?? const []).isEmpty;

  void _setSave(_Save s) {
    if (mounted && _save != s) setState(() => _save = s);
  }

  /// Something changed → autosave after [NoteEditorPage.autosaveDelay].
  void _changed() {
    _dirty = true;
    _rev++;
    _setSave(_Save.pending);
    _debounce?.cancel();
    _debounce = Timer(NoteEditorPage.autosaveDelay, _flush);
  }

  /// Saves now (serialized with earlier saves).
  Future<void> _flush() {
    _debounce?.cancel();
    return _chain = _chain.then((_) => _saveNow()).catchError((_) {});
  }

  Future<void> _saveNow() async {
    if (!_dirty || _deleted) return;
    final input = _input();
    _dirty = false;
    if (_id == null) {
      if (_isBlankInput(input)) {
        _setSave(_Save.idle);
        return;
      }
      _setSave(_Save.saving);
      final r = await _createNote(input);
      switch (r) {
        case Ok(:final value):
          if (mounted) {
            setState(() {
              _id = value.id;
              _save = _dirty ? _Save.pending : _Save.saved;
            });
          } else {
            _id = value.id;
          }
        case Err(:final failure):
          if (failure is ValidationFailure && failure.field == 'empty') {
            _setSave(_Save.idle);
          } else {
            _dirty = true;
            _setSave(_Save.error);
            if (mounted) showFailureToast(context, failure);
          }
      }
      return;
    }
    _setSave(_Save.saving);
    final r = await _updateNote(_id!, input);
    switch (r) {
      case Ok():
        _setSave(_dirty ? _Save.pending : _Save.saved);
      case Err(:final failure):
        _dirty = true;
        _setSave(_Save.error);
        if (mounted) showFailureToast(context, failure);
    }
  }

  /// Makes sure the note exists (creating it with [photos]/[audio] when new).
  /// Returns its id, or null when it can't be created.
  ///
  /// Runs on the save chain, so an autosave firing while the create is in
  /// flight waits for it (and updates the new note) instead of creating a
  /// second one.
  Future<String?> _ensureNote({
    List<TransactionPhoto>? photos,
    List<NoteAudio>? audio,
  }) {
    _debounce?.cancel();
    final done = Completer<String?>();
    _chain = _chain
        .then((_) async => done.complete(await _ensureNow(photos, audio)))
        .catchError((Object _) {
          if (!done.isCompleted) done.complete(null);
        });
    return done.future;
  }

  Future<String?> _ensureNow(
    List<TransactionPhoto>? photos,
    List<NoteAudio>? audio,
  ) async {
    await _saveNow();
    if (_id != null || _deleted) return mounted ? _id : null;
    final input = _input(photos: photos, audio: audio);
    if (_isBlankInput(input)) return null;
    final rev = _rev;
    _setSave(_Save.saving);
    final r = await _createNote(input);
    switch (r) {
      case Ok(:final value):
        _id = value.id;
        // Edits made while creating aren't in the note yet: keep them dirty
        // so the pending autosave writes them.
        if (_rev == rev) _dirty = false;
        if (!mounted) return null;
        setState(() => _save = _dirty ? _Save.pending : _Save.saved);
        return value.id;
      case Err(:final failure):
        _setSave(_Save.error);
        if (mounted) showFailureToast(context, failure);
        return null;
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      if (ref.read(dictationControllerProvider).isActive) {
        await _stopDictation();
      }
      await _flush();
      final id = _id;
      if (id != null && !_deleted && _isBlankInput(_input())) {
        final (loaded, live) = await _liveNote(id);
        final blank =
            loaded &&
            (live == null ||
                (live.photos.isEmpty &&
                    live.audio.isEmpty &&
                    live.links.isEmpty));
        if (blank && mounted) {
          _deleted = true;
          await ref.read(deleteNoteProvider)(id);
          if (mounted) {
            showToastBadge(
              context,
              message: 'Catatan kosong dibuang',
              icon: Icons.delete_sweep_rounded,
              color: GhinaColors.gray,
            );
          }
        }
      }
    } finally {
      _closing = false;
    }
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/notes');
    }
  }

  /// The stored note (photos/audio/links live only there). `loaded` is false
  /// when it couldn't be read — then nothing may be discarded.
  Future<(bool loaded, Note? note)> _liveNote(String id) async {
    final cur = ref.read(watchNoteProvider(id));
    if (cur.hasValue) return (true, cur.value?.note);
    // Just created (e.g. by a photo/clip) and not watched yet: wait for it.
    final sub = ref.listenManual(watchNoteProvider(id).future, (_, _) {});
    try {
      final v = await sub.read().timeout(const Duration(seconds: 3));
      return (true, v?.note);
    } catch (_) {
      return (false, null);
    } finally {
      sub.close();
    }
  }

  // ------------------------------------------------------------------ edits

  void _format(MdAction a) {
    setState(() => _preview = false);
    _body.value = applyMarkdown(_body.value, a);
    _bodyFocus.requestFocus();
    _changed();
  }

  void _setChecklist(List<ChecklistItem> items) {
    setState(() => _checklist = items);
    _changed();
  }

  void _addChecklistItem() {
    if (_checklist.isEmpty) {
      final id = newId();
      _setChecklist(checklistAdd(const [], '', id: id));
      _checkKey.currentState?.focusItem(id);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkKey.currentState?.focusItem(id),
      );
    } else {
      _checkKey.currentState?.addItem();
    }
  }

  void _togglePin() {
    setState(() {
      _pinned = !_pinned;
      if (_pinned) _archived = false;
    });
    _changed();
    showToastBadge(
      context,
      message: _pinned ? 'Disematkan di atas 📌' : 'Sematan dilepas',
      icon: Icons.push_pin_rounded,
      color: GhinaColors.yellow,
    );
  }

  Future<void> _toggleArchive() async {
    final archive = !_archived;
    setState(() {
      _archived = archive;
      if (archive) _pinned = false;
    });
    _changed();
    await _flush();
    if (!mounted) return;
    showToastBadge(
      context,
      message: archive ? 'Diarsipkan 📦' : 'Dikeluarkan dari arsip',
      icon: Icons.archive_rounded,
      color: GhinaColors.blue,
    );
    if (archive && _id != null) await _close();
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus catatan ini?',
      message:
          'Catatan, foto, dan rekamannya hilang permanen. '
          'Mau disimpan aja? Pakai Arsipkan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _debounce?.cancel();
    _deleted = true;
    final deleteNote = ref.read(deleteNoteProvider);
    // A create still in flight sets [_id] — delete that note too.
    await _chain;
    final id = _id;
    if (id != null) {
      final r = await deleteNote(id);
      if (!mounted) return;
      if (r case Err(:final failure)) {
        _deleted = false;
        showFailureToast(context, failure);
        return;
      }
    }
    if (!mounted) return;
    showToastBadge(
      context,
      message: 'Catatan dihapus',
      icon: Icons.delete_rounded,
      color: GhinaColors.red,
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/notes');
    }
  }

  Future<void> _pickLabels() => showLabelPickerSheet(
    context,
    selected: _labelIds,
    onChanged: (ids) {
      setState(() => _labelIds = ids);
      _changed();
    },
  );

  Future<void> _pickColor() => showNoteColorSheet(
    context,
    selected: _color,
    onChanged: (c) {
      setState(() => _color = c);
      _changed();
    },
  );

  Future<void> _convert(Note? live) async {
    final id = await _ensureNote();
    if (!mounted) return;
    if (id == null) {
      showErrorToast(context, 'Tulis sesuatu dulu, ya');
      return;
    }
    final base = live ?? ref.read(watchNoteProvider(id)).value?.note;
    if (base == null) return;
    final note = base.copyWith(
      title: _title.text,
      body: _body.text,
      checklist: _checklist,
    );
    final target = await showConvertMenu(context, note);
    if (target == null || !mounted) return;
    await runConvert(context, ref, note, target);
  }

  // ------------------------------------------------------------------ media

  Future<void> _addPhotos(Note? live) async {
    final count = live?.photos.length ?? 0;
    final paths = await pickPhotos(
      context,
      ref,
      remaining: maxNotePhotos - count,
      max: maxNotePhotos,
    );
    if (paths.isEmpty || !mounted) return;
    if (_id == null) {
      await _ensureNote(
        photos: [for (final p in paths) TransactionPhoto.local(p)],
      );
      return;
    }
    await _flush();
    final r = await ref.read(addNotePhotosProvider)(_id!, paths);
    if (r case Err(:final failure) when mounted) {
      showFailureToast(context, failure);
    }
  }

  Future<void> _removePhoto(Note live, int i) async {
    if (i >= live.photos.length) return;
    final r = await ref.read(removeNotePhotoProvider)(live.id, live.photos[i]);
    if (r case Err(:final failure) when mounted) {
      showFailureToast(context, failure);
    }
  }

  Future<void> _record(Note? live) async {
    if ((live?.audio.length ?? 0) >= maxNoteAudio) {
      showErrorToast(context, 'Maksimal $maxNoteAudio rekaman per catatan');
      return;
    }
    if (ref.read(dictationControllerProvider).isActive) {
      await _stopDictation();
      if (!mounted) return;
    }
    final rec = await showVoiceRecorderSheet(context);
    if (rec == null || !mounted) return;
    await _attachClip(rec);
  }

  Future<void> _attachClip(VoiceRecording rec) async {
    final secs = math
        .max(1, (rec.duration.inMilliseconds / 1000).round())
        .clamp(1, audioDurationMax);
    if (_id == null) {
      final id = await _ensureNote(
        audio: [NoteAudio.local(rec.path, durationSec: secs)],
      );
      if (id != null) _dropRecorderFile(rec);
      if (id != null && mounted) {
        showOkToast(context, 'Rekaman tersimpan 🎙️', icon: Icons.mic_rounded);
      }
      return;
    }
    await _flush();
    final r = await ref.read(addNoteAudioProvider)(
      _id!,
      NoteAudioInput(path: rec.path, durationSec: secs),
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        _dropRecorderFile(rec);
        showOkToast(context, 'Rekaman tersimpan 🎙️', icon: Icons.mic_rounded);
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  /// The note keeps its own copy of the clip (app storage); the recorder's
  /// file is no longer needed.
  void _dropRecorderFile(VoiceRecording rec) =>
      unawaited(ref.read(voiceRecorderProvider).deleteFile(rec.path));

  Future<void> _removeClip(Note live, NoteAudio clip) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus rekaman ini?',
      message: 'Rekaman suaranya hilang permanen.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final p = ref.read(voicePlayerControllerProvider);
    if (p.key == clipKey(clip)) {
      await ref.read(voicePlayerControllerProvider.notifier).stop();
    }
    final r = await ref.read(removeNoteAudioProvider)(live.id, clip);
    if (r case Err(:final failure) when mounted) {
      showFailureToast(context, failure);
    }
  }

  // ------------------------------------------------------------------ dictation

  void _insertIntoBody(String text) {
    if (text.trim().isEmpty) return;
    final v = _body.value;
    final at = v.selection.isValid
        ? v
        : v.copyWith(selection: TextSelection.collapsed(offset: v.text.length));
    _body.value = insertAtCursor(at, text);
    if (_preview) setState(() => _preview = false);
    _changed();
  }

  void _onDictation(DictationState? prev, DictationState next) {
    final committed = next.committed;
    if (committed.length > _dictInserted) {
      final delta = committed.substring(_dictInserted);
      _dictInserted = committed.length;
      _insertIntoBody(delta);
    } else if (committed.length < _dictInserted) {
      _dictInserted = committed.length;
    }
    if (prev?.phase != DictationPhase.error &&
        next.phase == DictationPhase.error &&
        next.error?.kind != SpeechErrorKind.permission) {
      showErrorToast(context, _dictationError(next.error?.kind));
    }
  }

  String _dictationError(SpeechErrorKind? k) => switch (k) {
    SpeechErrorKind.network =>
      'Dikte butuh paket suara offline. Rekaman suara tetap bisa, ya',
    SpeechErrorKind.languageUnavailable =>
      'Bahasa Indonesia belum tersedia untuk dikte di HP ini',
    SpeechErrorKind.busy =>
      'Mikrofon lagi dipakai aplikasi lain. Coba lagi sebentar, ya',
    SpeechErrorKind.audio => 'Mikrofon bermasalah. Coba lagi, ya',
    _ => 'Dikte berhenti. Coba lagi, yuk',
  };

  Future<void> _toggleDictation() async {
    final c = ref.read(dictationControllerProvider.notifier);
    if (ref.read(dictationControllerProvider).isActive) {
      await _stopDictation();
      return;
    }
    // Availability first (no mic prompt on a device that can't dictate).
    final transcriber = ref.read(speechTranscriberProvider);
    final avail = await transcriber.availability(
      locale: ref.read(speechLocaleProvider),
    );
    if (!mounted) return;
    if (!avail.canDictate(
      allowNetwork: ref.read(dictationAllowsNetworkProvider),
    )) {
      await showDictationUnavailable(context, ref, avail);
      return;
    }
    if (!await ensureMicReady(context, ref, MicPurpose.dictate)) return;
    if (!mounted) return;
    c.clear();
    _dictInserted = 0;
    setState(() => _preview = false);
    final ok = await c.start();
    if (ok || !mounted) return;
    final s = ref.read(dictationControllerProvider);
    if (s.phase == DictationPhase.unavailable && s.availability != null) {
      await showDictationUnavailable(context, ref, s.availability!);
    } else if (s.error?.kind == SpeechErrorKind.permission) {
      if (s.permission == MicPermissionStatus.permanentlyDenied) {
        await showMicSettingsGuide(context, ref);
      } else {
        showErrorToast(context, 'Izin mikrofon dibutuhkan untuk dikte');
      }
    } else if (s.phase == DictationPhase.error) {
      showErrorToast(context, _dictationError(s.error?.kind));
    }
  }

  Future<void> _stopDictation() async {
    final c = ref.read(dictationControllerProvider.notifier);
    await c.stop();
    if (!mounted) return;
    c.clear();
    _dictInserted = 0;
  }

  Future<void> _cancelDictation() async {
    final c = ref.read(dictationControllerProvider.notifier);
    await c.cancel();
    if (!mounted) return;
    c.clear();
    _dictInserted = 0;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final liveAsync = _id == null ? null : ref.watch(watchNoteProvider(_id!));
    final dictation = ref.watch(dictationControllerProvider);
    ref.listen(dictationControllerProvider, _onDictation);

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => popOr(context, '/notes')),
        ),
        body: switch (liveAsync) {
          AsyncError() => ErrorRetry(
            onRetry: () => ref.invalidate(watchNoteProvider(widget.id!)),
          ),
          AsyncData(value: null) => EmptyState(
            title: 'Catatan nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
            mood: MascotMood.thinking,
            actionLabel: 'Ke daftar catatan',
            onAction: () => context.go('/notes'),
          ),
          _ => const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 3),
          ),
        },
      );
    }

    final view = liveAsync?.value;
    final live = view?.note;
    final allLabels =
        ref.watch(watchNoteLabelsProvider).value ?? const <NoteLabel>[];
    final byId = {for (final l in allLabels) l.id: l};
    final labels = [for (final id in _labelIds) ?byId[id]];
    final tone = NoteTone.of(context, _color);
    final bg = tone.isDefault ? g.background : tone.face;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          leading: BackButton(
            key: const ValueKey('note-back'),
            onPressed: _close,
          ),
          titleSpacing: 0,
          title: _SaveIndicator(state: _save, onRetry: _flush),
          actions: [
            IconButton(
              key: const ValueKey('note-pin'),
              tooltip: _pinned ? 'Lepas sematan' : 'Sematkan',
              icon: Icon(
                _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: _pinned ? GhinaColors.yellow.edge : null,
              ),
              onPressed: _togglePin,
            ),
            IconButton(
              key: const ValueKey('note-convert'),
              tooltip: 'Jadikan tugas / konten / transaksi',
              icon: const Icon(Icons.bolt_rounded),
              onPressed: () => _convert(live),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('note-more'),
              tooltip: 'Lainnya',
              onSelected: (v) => switch (v) {
                'color' => _pickColor(),
                'labels' => _pickLabels(),
                'archive' => _toggleArchive(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'color',
                  child: _MenuRow(Icons.palette_outlined, 'Warna'),
                ),
                const PopupMenuItem(
                  value: 'labels',
                  child: _MenuRow(Icons.label_outline_rounded, 'Label'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: _MenuRow(
                    _archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    _archived ? 'Keluarkan dari arsip' : 'Arsipkan',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: _MenuRow(Icons.delete_outline_rounded, 'Hapus'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('note-scroll'),
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  4,
                  GhinaSpace.page,
                  24,
                ),
                children: [
                  if (live != null) ..._linkedPills(live),
                  if (live != null && live.photos.isNotEmpty) ...[
                    PhotoStrip(
                      photos: noteViewerPhotos(live.photos),
                      max: maxNotePhotos,
                      size: 88,
                      heroScope: 'note-${live.id}',
                      onRemove: (i) => _removePhoto(live, i),
                      onAdd: () => _addPhotos(live),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const ValueKey('note-title'),
                    controller: _title,
                    focusNode: _titleFocus,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(noteTitleMax),
                      FilteringTextInputFormatter.deny(RegExp(r'[\n\t]')),
                    ],
                    style: GhinaType.h1.w(900).copyWith(color: tone.text),
                    decoration: _plain('Judul', GhinaType.h1.w(900), tone),
                    onChanged: (_) => _changed(),
                    onSubmitted: (_) => _bodyFocus.requestFocus(),
                  ),
                  const SizedBox(height: 4),
                  if (_preview)
                    GestureDetector(
                      key: const ValueKey('note-preview'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _preview = false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _body.text.trim().isEmpty
                            ? Text(
                                'Belum ada isi. Ketuk untuk menulis.',
                                style: GhinaType.bodyL.copyWith(
                                  color: tone.subtle,
                                ),
                              )
                            : NoteMarkdown(
                                data: _body.text,
                                textColor: tone.text,
                              ),
                      ),
                    )
                  else
                    TextField(
                      key: const ValueKey('note-body'),
                      controller: _body,
                      focusNode: _bodyFocus,
                      maxLines: null,
                      minLines: _checklist.isEmpty ? 4 : 1,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(noteBodyMax),
                      ],
                      style: GhinaType.bodyL.copyWith(
                        color: tone.text,
                        height: 1.45,
                      ),
                      decoration: _plain(
                        'Tulis catatan…',
                        GhinaType.bodyL,
                        tone,
                      ),
                      onChanged: (_) => _changed(),
                    ),
                  if (_checklist.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ChecklistEditor(
                      key: _checkKey,
                      items: _checklist,
                      tone: tone,
                      onChanged: _setChecklist,
                    ),
                  ],
                  if (live != null && live.audio.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionLabel(
                      icon: Icons.mic_rounded,
                      text: 'Rekaman suara',
                      tone: tone,
                    ),
                    for (var i = 0; i < live.audio.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AudioClipTile(
                          clip: live.audio[i],
                          index: i,
                          onDelete: () => _removeClip(live, live.audio[i]),
                          onInsertTranscript: () =>
                              _insertIntoBody(live.audio[i].transcript ?? ''),
                        ),
                      ),
                  ],
                  if (live != null && live.links.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionLabel(
                      icon: Icons.link_rounded,
                      text: 'Tautan',
                      tone: tone,
                    ),
                    for (var i = 0; i < live.links.length; i++)
                      _LinkRow(link: live.links[i], index: i, tone: tone),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final l in labels)
                        GestureDetector(
                          onTap: _pickLabels,
                          child: NoteLabelChip(
                            label: l,
                            onCard: !tone.isDefault,
                          ),
                        ),
                      ActionChip(
                        key: const ValueKey('note-labels'),
                        avatar: const Icon(
                          Icons.label_outline_rounded,
                          size: 18,
                        ),
                        label: Text(labels.isEmpty ? 'Tambah label' : 'Label'),
                        onPressed: _pickLabels,
                      ),
                    ],
                  ),
                  if (live != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _footer(live),
                      style: GhinaType.caption.copyWith(color: tone.subtle),
                    ),
                  ],
                ],
              ),
            ),
            if (dictation.isActive)
              DictationBar(onStop: _stopDictation, onCancel: _cancelDictation),
            _FormatBar(
              preview: _preview,
              onFormat: _format,
              onPreview: () {
                FocusScope.of(context).unfocus();
                setState(() => _preview = !_preview);
              },
              tone: tone,
            ),
            _ActionBar(
              tone: tone,
              dictating: dictation.isActive,
              onChecklist: _addChecklistItem,
              onPhoto: () => _addPhotos(live),
              onRecord: () => _record(live),
              onDictate: _toggleDictation,
              onColor: _pickColor,
            ),
          ],
        ),
      ),
    );
  }

  String _footer(Note n) {
    final now = ref.read(clockProvider).now();
    final day = Fmt.relativeDay(n.updatedAt, now: now);
    final src = switch (n.source) {
      NoteSource.share => ' · dari share',
      NoteSource.voice => ' · dari rekaman',
      _ => '',
    };
    return 'Diedit $day ${Fmt.time(n.updatedAt)}$src';
  }

  List<Widget> _linkedPills(Note n) {
    final pills = <Widget>[
      if (n.linkedTaskId != null)
        _LinkedPill(
          key: const ValueKey('linked-task'),
          icon: Icons.task_alt_rounded,
          text: 'Sudah jadi tugas',
          color: GhinaColors.red,
          onTap: () => context.push(taskRoute(n.linkedTaskId!)),
        ),
      if (n.linkedContentId != null)
        _LinkedPill(
          key: const ValueKey('linked-content'),
          icon: Icons.movie_creation_rounded,
          text: 'Sudah jadi konten',
          color: GhinaColors.purple,
          onTap: () => context.push(contentItemRoute(n.linkedContentId!)),
        ),
      if (n.linkedTransactionId != null)
        _LinkedPill(
          key: const ValueKey('linked-transaction'),
          icon: Icons.receipt_long_rounded,
          text: 'Sudah jadi transaksi',
          color: GhinaColors.green,
          onTap: () => context.push('/transactions/${n.linkedTransactionId}'),
        ),
    ];
    if (pills.isEmpty) return const [];
    return [
      Wrap(spacing: 8, runSpacing: 8, children: pills),
      const SizedBox(height: 12),
    ];
  }
}

InputDecoration _plain(String hint, TextStyle style, NoteTone tone) =>
    InputDecoration(
      hintText: hint,
      hintStyle: style.copyWith(color: tone.subtle.withValues(alpha: 0.6)),
      filled: false,
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
    );

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state, required this.onRetry});
  final _Save state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final (IconData? icon, String text, Color color) = switch (state) {
      _Save.idle => (null, '', g.textMuted),
      _Save.pending ||
      _Save.saving => (Icons.sync_rounded, 'Menyimpan…', g.textMuted),
      _Save.saved => (
        Icons.check_circle_rounded,
        'Tersimpan',
        GhinaColors.green.base,
      ),
      _Save.error => (
        Icons.error_rounded,
        'Gagal simpan · coba lagi',
        GhinaColors.red.base,
      ),
    };
    return AnimatedSwitcher(
      duration: GhinaMotion.fast,
      child: icon == null
          ? const SizedBox.shrink()
          : GestureDetector(
              key: ValueKey('save-${state.name}'),
              onTap: state == _Save.error ? onRetry : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyS.w(800).copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: context.ghina.textSecondary),
      const SizedBox(width: 12),
      Text(text, style: GhinaType.body.w(700)),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.text,
    required this.tone,
  });
  final IconData icon;
  final String text;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 16, color: tone.subtle),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: GhinaType.overline.w(900).copyWith(color: tone.subtle),
        ),
      ],
    ),
  );
}

class _LinkedPill extends StatelessWidget {
  const _LinkedPill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final ChunkySwatch color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkySurface(
      color: color.tint(g.brightness),
      edgeColor: color.tintBorder(g.brightness),
      borderColor: color.tintBorder(g.brightness),
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rMd,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onTap: onTap,
      semanticLabel: text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: g.isDark ? color.base : color.edge),
          const SizedBox(width: 6),
          Text(
            text,
            style: GhinaType.bodyS
                .w(800)
                .copyWith(color: g.isDark ? color.base : color.edge),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: g.isDark ? color.base : color.edge,
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link, required this.index, required this.tone});
  final NoteLink link;
  final int index;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChunkySurface(
        key: ValueKey('link-$index'),
        color: tone.isDefault
            ? g.surface
            : Colors.white.withValues(alpha: g.isDark ? 0.06 : 0.55),
        edgeColor: tone.edge,
        borderColor: tone.border,
        depth: GhinaDepth.sm,
        borderRadius: GhinaRadii.rMd,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () => openLink(context, link.url),
        onLongPress: () => copyLink(context, link.url),
        semanticLabel: link.title ?? link.url,
        child: Row(
          children: [
            CategoryAvatar(
              icon: Icons.public_rounded,
              color: GhinaColors.blue.base,
              size: 34,
              soft: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title ?? linkHost(link.url),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body.w(800).copyWith(color: tone.text),
                  ),
                  Text(
                    link.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: tone.subtle),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 18, color: tone.subtle),
          ],
        ),
      ),
    );
  }
}

class _FormatBar extends StatelessWidget {
  const _FormatBar({
    required this.preview,
    required this.onFormat,
    required this.onPreview,
    required this.tone,
  });

  final bool preview;
  final ValueChanged<MdAction> onFormat;
  final VoidCallback onPreview;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget b(MdAction a, IconData icon, String tip) => IconButton(
      key: ValueKey('fmt-${a.name}'),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: preview ? g.textMuted : tone.text),
      onPressed: () => onFormat(a),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tone.border, width: 1.5)),
      ),
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                b(MdAction.bold, Icons.format_bold_rounded, 'Tebal'),
                b(MdAction.italic, Icons.format_italic_rounded, 'Miring'),
                b(MdAction.heading, Icons.title_rounded, 'Judul bagian'),
                b(
                  MdAction.bullet,
                  Icons.format_list_bulleted_rounded,
                  'Daftar',
                ),
                b(
                  MdAction.numbered,
                  Icons.format_list_numbered_rounded,
                  'Daftar bernomor',
                ),
                b(MdAction.quote, Icons.format_quote_rounded, 'Kutipan'),
                b(MdAction.link, Icons.link_rounded, 'Tautan'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: const ValueKey('fmt-preview'),
              onPressed: onPreview,
              icon: Icon(
                preview ? Icons.edit_rounded : Icons.visibility_rounded,
                size: 18,
              ),
              label: Text(preview ? 'Edit' : 'Pratinjau'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.tone,
    required this.dictating,
    required this.onChecklist,
    required this.onPhoto,
    required this.onRecord,
    required this.onDictate,
    required this.onColor,
  });

  final NoteTone tone;
  final bool dictating;
  final VoidCallback onChecklist;
  final VoidCallback onPhoto;
  final VoidCallback onRecord;
  final VoidCallback onDictate;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget a(
      String key,
      IconData icon,
      String label, {
      Color? color,
      required VoidCallback onTap,
      bool active = false,
    }) => Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          borderRadius: GhinaRadii.rMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: GhinaMotion.fast,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: active
                        ? (color ?? tone.text).withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: GhinaRadii.rMd,
                  ),
                  child: Icon(icon, size: 24, color: color ?? tone.text),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: tone.subtle, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: tone.isDefault
              ? g.surfaceAlt
              : tone.edge.withValues(alpha: 0.35),
        ),
        child: Row(
          children: [
            a(
              'act-checklist',
              Icons.check_box_outlined,
              'Checklist',
              onTap: onChecklist,
            ),
            a('act-photo', Icons.add_a_photo_outlined, 'Foto', onTap: onPhoto),
            a(
              'act-record',
              Icons.mic_rounded,
              'Rekam',
              color: GhinaColors.red.base,
              onTap: onRecord,
            ),
            a(
              'act-dictate',
              dictating ? Icons.stop_circle_rounded : Icons.record_voice_over,
              'Dikte',
              color: GhinaColors.blue.base,
              active: dictating,
              onTap: onDictate,
            ),
            a('act-color', Icons.palette_outlined, 'Warna', onTap: onColor),
          ],
        ),
      ),
    );
  }
}
