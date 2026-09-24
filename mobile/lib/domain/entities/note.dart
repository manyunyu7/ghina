/// Notes (Google-Keep-like) — `docs/notes.md`. Pure value types; the rules
/// (checklist/label ops, URL extraction, amount parsing, search) live in
/// `domain/usecases/notes_rules.dart`.
library;

import 'transaction_photo.dart';
import 'value_equality.dart';

const _unset = Object();

/// Limits of the model — same as the server (`src/lib/notes.ts`).
const noteTitleMax = 200;
const noteBodyMax = 50000;
const maxChecklistItems = 200;
const checklistTextMax = 1000;
const maxNoteLabels = 20;
const maxNotePhotos = 10;
const maxNoteAudio = 5;

/// Recording limit (10 minutes). The server accepts up to [audioDurationMax]
/// (encoder rounding tolerance).
const maxAudioSeconds = 600;
const audioDurationMax = 610;
const transcriptMax = 20000;
const maxNoteLinks = 20;
const linkUrlMax = 2000;
const linkTitleMax = 300;
const labelNameMax = 30;
const defaultLabelColor = '#58CC02';

/// A note card color. Notes store the palette [id]; each platform maps it to the
/// [light]/[dark] shade (`#rrggbb`).
final class NoteColor {
  const NoteColor(this.id, this.label, this.light, this.dark);
  final String id;
  final String label;
  final String light;
  final String dark;
}

/// The card palette (same ids/shades as the web). `Note.color == null` = default.
const noteColors = [
  NoteColor('red', 'Merah', '#FAAFA8', '#77172E'),
  NoteColor('orange', 'Oranye', '#F39F76', '#692B17'),
  NoteColor('yellow', 'Kuning', '#FFF8B8', '#7C4A03'),
  NoteColor('green', 'Hijau', '#E2F6D3', '#264D3B'),
  NoteColor('teal', 'Toska', '#B4DDD3', '#0C625D'),
  NoteColor('blue', 'Biru', '#D4E4ED', '#256377'),
  NoteColor('darkblue', 'Biru tua', '#AECCDC', '#284255'),
  NoteColor('purple', 'Ungu', '#D3BFDB', '#472E5B'),
  NoteColor('pink', 'Merah muda', '#F6E2DD', '#6C394F'),
  NoteColor('brown', 'Cokelat', '#E9E3D4', '#4B443A'),
  NoteColor('gray', 'Abu-abu', '#EFEFF1', '#232427'),
];

/// Palette entry of a stored color id (null for null/unknown ids).
NoteColor? noteColorById(String? id) {
  for (final c in noteColors) {
    if (c.id == id) return c;
  }
  return null;
}

/// Plain text of a markdown line: heading/quote/list/checkbox markers, link
/// syntax and emphasis removed (server `stripMarkdown`).
String stripMarkdown(String line) => line
    .replaceFirst(
      RegExp(r'^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)'),
      '',
    )
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'(\*\*|__|\*|_|`|~~)'), '')
    .trim();

String _clipText(String t, int max) =>
    t.length > max ? '${t.substring(0, max - 1).trimRight()}…' : t;

/// First non-empty body line as plain text, ≤ [max] chars (server `firstLine`).
String firstLine(String body, {int max = noteTitleMax}) {
  for (final l in body.split('\n')) {
    final t = stripMarkdown(l);
    if (t.isNotEmpty) return _clipText(t, max);
  }
  return '';
}

/// One checklist row (notes and content items share the shape `{id, text, done}`).
final class ChecklistItem with ValueEquality {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.done = false,
  });

  final String id;
  final String text;
  final bool done;

  ChecklistItem copyWith({String? text, bool? done}) =>
      ChecklistItem(id: id, text: text ?? this.text, done: done ?? this.done);

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'done': done};

  /// Null when [json] isn't `{id: string, text: string, done?: bool}`.
  static ChecklistItem? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], text = json['text'];
    if (id is! String || id.isEmpty || text is! String) return null;
    return ChecklistItem(id: id, text: text, done: json['done'] == true);
  }

  @override
  List<Object?> get props => [id, text, done];

  @override
  String toString() => 'ChecklistItem($id, $text, $done)';
}

/// A URL found in the body or shared into the note. [title] is fetched by the
/// server (best effort) and arrives on a pull.
final class NoteLink with ValueEquality {
  const NoteLink({required this.url, this.title});

  final String url;
  final String? title;

  Map<String, Object?> toJson() => {'url': url, 'title': title};

  static NoteLink? tryParse(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    final t = json['title'];
    return NoteLink(url: url, title: t is String && t.isNotEmpty ? t : null);
  }

  @override
  List<Object?> get props => [url, title];
}

/// A voice clip: uploaded ([url], `/uploads/x.m4a` — play with
/// `AppConfig.resolveUrl`) or recorded offline and waiting for upload
/// ([localPath] — play the file). [transcript] = on-device transcription (id-ID),
/// stored with the clip.
final class NoteAudio with ValueEquality {
  const NoteAudio.remote(
    String this.url, {
    required this.durationSec,
    this.transcript,
  }) : localPath = null;

  const NoteAudio.local(
    String this.localPath, {
    required this.durationSec,
    this.transcript,
  }) : url = null;

  final String? url;
  final String? localPath;

  /// Whole seconds (0–[audioDurationMax] on the wire).
  final int durationSec;
  final String? transcript;

  bool get isPending => localPath != null;
  bool get hasTranscript => (transcript ?? '').trim().isNotEmpty;

  NoteAudio withTranscript(String? transcript) => isPending
      ? NoteAudio.local(
          localPath!,
          durationSec: durationSec,
          transcript: transcript,
        )
      : NoteAudio.remote(
          url!,
          durationSec: durationSec,
          transcript: transcript,
        );

  @override
  List<Object?> get props => [url, localPath, durationSec, transcript];

  @override
  String toString() =>
      'NoteAudio(${url ?? 'local:$localPath'}, ${durationSec}s)';
}

/// How a note was captured.
enum NoteSource {
  share('share'),
  quick('quick'),
  voice('voice');

  const NoteSource(this.wire);
  final String wire;

  static NoteSource? tryFromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

/// A note. [photos] reuse [TransactionPhoto] (uploaded `url` or pending
/// `localPath`), ≤ [maxNotePhotos].
final class Note with ValueEquality {
  const Note({
    required this.id,
    this.title,
    this.body = '',
    this.checklist = const [],
    this.labelIds = const [],
    this.color,
    this.pinned = false,
    this.archived = false,
    this.photos = const [],
    this.audio = const [],
    this.links = const [],
    this.source,
    this.linkedTaskId,
    this.linkedContentId,
    this.linkedTransactionId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// ≤ 200, null = untitled.
  final String? title;

  /// Markdown subset, ≤ 50 000 chars.
  final String body;
  final List<ChecklistItem> checklist;

  /// Ids of [NoteLabel]s (order as stored).
  final List<String> labelIds;

  /// Palette id from [noteColors] (`red`, `blue`, …); null = default card.
  final String? color;
  final bool pinned;
  final bool archived;
  final List<TransactionPhoto> photos;
  final List<NoteAudio> audio;
  final List<NoteLink> links;
  final NoteSource? source;
  final String? linkedTaskId;
  final String? linkedContentId;
  final String? linkedTransactionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Title, else the first body line (plain text), else the first non-empty
  /// checklist item, else '' (show a placeholder).
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final l = firstLine(body);
    if (l.isNotEmpty) return l;
    for (final c in checklist) {
      if (c.text.trim().isNotEmpty) return c.text.trim();
    }
    return '';
  }

  /// Palette entry of [color] (null = default card).
  NoteColor? get palette => noteColorById(color);

  bool get hasChecklist => checklist.isNotEmpty;
  int get checklistDone => checklist.where((c) => c.done).length;
  bool get hasPhotos => photos.isNotEmpty;
  bool get hasAudio => audio.isNotEmpty;
  bool get hasLabels => labelIds.isNotEmpty;

  /// Photos or clips waiting for upload.
  bool get hasPendingUploads =>
      photos.any((p) => p.isPending) || audio.any((a) => a.isPending);

  /// Nothing typed or attached (the editor discards such a note on back).
  bool get isBlank =>
      (title ?? '').trim().isEmpty &&
      body.trim().isEmpty &&
      checklist.isEmpty &&
      photos.isEmpty &&
      audio.isEmpty &&
      links.isEmpty;

  bool hasLabel(String labelId) => labelIds.contains(labelId);

  Note copyWith({
    Object? title = _unset,
    String? body,
    List<ChecklistItem>? checklist,
    List<String>? labelIds,
    Object? color = _unset,
    bool? pinned,
    bool? archived,
    List<TransactionPhoto>? photos,
    List<NoteAudio>? audio,
    List<NoteLink>? links,
    Object? source = _unset,
    Object? linkedTaskId = _unset,
    Object? linkedContentId = _unset,
    Object? linkedTransactionId = _unset,
    DateTime? updatedAt,
  }) => Note(
    id: id,
    title: identical(title, _unset) ? this.title : title as String?,
    body: body ?? this.body,
    checklist: checklist ?? this.checklist,
    labelIds: labelIds ?? this.labelIds,
    color: identical(color, _unset) ? this.color : color as String?,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    photos: photos ?? this.photos,
    audio: audio ?? this.audio,
    links: links ?? this.links,
    source: identical(source, _unset) ? this.source : source as NoteSource?,
    linkedTaskId: identical(linkedTaskId, _unset)
        ? this.linkedTaskId
        : linkedTaskId as String?,
    linkedContentId: identical(linkedContentId, _unset)
        ? this.linkedContentId
        : linkedContentId as String?,
    linkedTransactionId: identical(linkedTransactionId, _unset)
        ? this.linkedTransactionId
        : linkedTransactionId as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    body,
    checklist,
    labelIds,
    color,
    pinned,
    archived,
    photos,
    audio,
    links,
    source,
    linkedTaskId,
    linkedContentId,
    linkedTransactionId,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'Note($id, $displayTitle)';
}

/// A label (no folders). [pinnedTab] labels are shown as tabs.
final class NoteLabel with ValueEquality {
  const NoteLabel({
    required this.id,
    required this.name,
    this.color = defaultLabelColor,
    this.pinnedTab = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 1–30, unique per user (case-insensitive).
  final String name;
  final String color;
  final bool pinnedTab;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteLabel copyWith({
    String? name,
    String? color,
    bool? pinnedTab,
    int? sortOrder,
    DateTime? updatedAt,
  }) => NoteLabel(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    pinnedTab: pinnedTab ?? this.pinnedTab,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    color,
    pinnedTab,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'NoteLabel($id, $name)';
}

/// A note with its label rows (list cards, editor).
final class NoteView with ValueEquality {
  const NoteView({required this.note, required this.labels});

  final Note note;

  /// The note's labels that exist locally, in the note's order.
  final List<NoteLabel> labels;

  String get id => note.id;

  @override
  List<Object?> get props => [note, labels];
}

/// What the notes list shows (`watchNotesProvider`). Value-equal (family key).
final class NoteFilter with ValueEquality {
  const NoteFilter({this.labelId, this.archived = false, this.search});

  /// Everything not archived (the "Semua" tab).
  static const all = NoteFilter();

  /// The archive.
  static const archive = NoteFilter(archived: true);

  /// One label tab.
  const NoteFilter.label(String this.labelId, {this.search}) : archived = false;

  /// Only notes with this label (null = any).
  final String? labelId;

  /// false = active notes, true = archived ones, null = both (search everywhere).
  final bool? archived;

  /// Matches title, body, checklist items and clip transcripts
  /// (case-insensitive substring).
  final String? search;

  @override
  List<Object?> get props => [labelId, archived, search];
}
