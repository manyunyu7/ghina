/// Pure notes rules — a port of the server's `src/lib/notes.ts` (`docs/notes.md`):
/// text hygiene, checklist and label ops, URL extraction and link merging,
/// single-amount parsing, search, default label. Constants and algorithms must
/// match the server.
library;

import '../../core/failure.dart';
import '../entities/entities.dart';

// ---------------------------------------------------------------- text hygiene

final _controlRe = RegExp(r'[\u0000-\u0008\u000B-\u001F\u007F]');

/// Newlines normalized to `\n`, control characters dropped (tabs/newlines kept).
String cleanText(String v) =>
    v.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll(_controlRe, '');

/// One line: newlines/tabs → space, controls dropped, trimmed.
String cleanLine(String v) =>
    cleanText(v).replaceAll(RegExp(r'[\n\t]+'), ' ').trim();

/// Case-insensitive uniqueness key of a label / pillar name.
String nameKey(String name) => cleanLine(name).toLowerCase();

final _hexColorRe = RegExp(r'^#[0-9a-fA-F]{6}$');
bool isHexColor(String? v) => v != null && _hexColorRe.hasMatch(v);

/// Checklist item / label ids on the wire.
final itemIdRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

// ---------------------------------------------------------------- default label

const ideaLabelName = 'Ide Konten';
const ideaLabelColor = '#CE82FF';
const ideaLabelIdPrefix = 'label-ide-konten-';

/// Deterministic id of the default "Ide Konten" label (server `ideaLabelId`), so
/// seeding on the server and on two devices never duplicates it.
String defaultLabelId(String userId) => '$ideaLabelIdPrefix$userId';

/// The default label: `Ide Konten`, pinned as a tab, first in order.
NoteLabel defaultNoteLabel(String userId, DateTime now) => NoteLabel(
  id: defaultLabelId(userId),
  name: ideaLabelName,
  color: ideaLabelColor,
  pinnedTab: true,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

/// The "Ide Konten" label: the default id (`label-ide-konten-…`), else a label
/// named `Ide Konten` (case-insensitive). Null when the user has none.
NoteLabel? findIdeaLabel(List<NoteLabel> labels) {
  for (final l in labels) {
    if (l.id.startsWith(ideaLabelIdPrefix)) return l;
  }
  for (final l in labels) {
    if (nameKey(l.name) == nameKey(ideaLabelName)) return l;
  }
  return null;
}

// ---------------------------------------------------------------- labels

/// Label order: sortOrder, then name.
int compareLabels(NoteLabel a, NoteLabel b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Whether [name] clashes (case-insensitive) with another label.
bool labelNameTaken(List<NoteLabel> labels, String name, {String? exceptId}) {
  final k = nameKey(name);
  return labels.any((l) => l.id != exceptId && nameKey(l.name) == k);
}

/// `cleanLine`d, 1–30 chars, not used by another label.
String validateLabelName(
  String name,
  List<NoteLabel> labels, {
  String? exceptId,
}) {
  final n = cleanLine(name);
  if (n.isEmpty) {
    throw const ValidationFailure('Nama label wajib diisi', field: 'name');
  }
  if (n.length > labelNameMax) {
    throw const ValidationFailure(
      'Nama label maksimal $labelNameMax karakter',
      field: 'name',
    );
  }
  if (labelNameTaken(labels, n, exceptId: exceptId)) {
    throw const ValidationFailure('Label ini sudah ada', field: 'name');
  }
  return n;
}

/// Distinct ids, first occurrence wins, empty ids dropped; more than
/// [maxNoteLabels] → [ValidationFailure] (`field: 'labels'`).
List<String> normalizeLabelIds(Iterable<String> ids) {
  final out = <String>[];
  for (final id in ids) {
    if (id.isNotEmpty && !out.contains(id)) out.add(id);
  }
  if (out.length > maxNoteLabels) {
    throw const ValidationFailure(
      'Maksimal $maxNoteLabels label per catatan',
      field: 'labels',
    );
  }
  return out;
}

/// Adds [labelId] when missing, removes it when present.
List<String> toggleLabelId(List<String> ids, String labelId) =>
    ids.contains(labelId) ? stripLabel(ids, labelId) : [...ids, labelId];

/// Deleting a label: its id is removed from a note's labels (order kept).
List<String> stripLabel(List<String> ids, String labelId) => [
  for (final x in ids)
    if (x != labelId) x,
];

// ---------------------------------------------------------------- checklist

String _itemText(String text) {
  final t = cleanLine(text);
  if (t.length > checklistTextMax) {
    throw const ValidationFailure(
      'Item checklist terlalu panjang (maks $checklistTextMax)',
      field: 'checklist',
    );
  }
  return t;
}

/// Server-valid checklist: ids distinct (first wins) and `^[A-Za-z0-9_-]{1,64}$`,
/// text `cleanLine`d (empty allowed — a fresh row). Too long / > 200 items →
/// [ValidationFailure] (`field: 'checklist'`).
List<ChecklistItem> normalizeChecklist(Iterable<ChecklistItem> items) {
  final seen = <String>{};
  final out = <ChecklistItem>[];
  for (final c in items) {
    if (!itemIdRe.hasMatch(c.id) || !seen.add(c.id)) continue;
    final t = _itemText(c.text);
    out.add(c.text == t ? c : c.copyWith(text: t));
  }
  if (out.length > maxChecklistItems) {
    throw const ValidationFailure(
      'Maksimal $maxChecklistItems item checklist',
      field: 'checklist',
    );
  }
  return List.unmodifiable(out);
}

/// Adds an item (at the end or at [index]). [id] = a new UUID from the caller.
/// [text] may be empty (a fresh row the user is about to type into).
List<ChecklistItem> checklistAdd(
  List<ChecklistItem> items,
  String text, {
  required String id,
  int? index,
}) {
  if (items.length >= maxChecklistItems) {
    throw const ValidationFailure(
      'Maksimal $maxChecklistItems item checklist',
      field: 'checklist',
    );
  }
  final out = [...items];
  out.insert(
    (index ?? out.length).clamp(0, out.length),
    ChecklistItem(id: id, text: _itemText(text)),
  );
  return out;
}

List<ChecklistItem> checklistToggle(List<ChecklistItem> items, String id) => [
  for (final c in items) c.id == id ? c.copyWith(done: !c.done) : c,
];

List<ChecklistItem> checklistSetDone(
  List<ChecklistItem> items,
  String id,
  bool done,
) => [for (final c in items) c.id == id ? c.copyWith(done: done) : c];

List<ChecklistItem> checklistSetText(
  List<ChecklistItem> items,
  String id,
  String text,
) {
  final t = _itemText(text);
  return [for (final c in items) c.id == id ? c.copyWith(text: t) : c];
}

List<ChecklistItem> checklistRemove(List<ChecklistItem> items, String id) => [
  for (final c in items)
    if (c.id != id) c,
];

/// Moves the item at [from] to [to] (indices in the current list).
List<ChecklistItem> checklistMove(List<ChecklistItem> items, int from, int to) {
  if (from < 0 || from >= items.length) return items;
  final out = [...items];
  final x = out.removeAt(from);
  out.insert(to.clamp(0, out.length), x);
  return out;
}

/// Reorders by [ids]; items not listed keep their relative order at the end.
List<ChecklistItem> checklistReorder(
  List<ChecklistItem> items,
  List<String> ids,
) {
  final byId = {for (final c in items) c.id: c};
  final out = [for (final id in ids) ?byId.remove(id)];
  return [
    ...out,
    for (final c in items)
      if (byId.containsKey(c.id)) c,
  ];
}

/// Drops checked items.
List<ChecklistItem> checklistClearDone(List<ChecklistItem> items) => [
  for (final c in items)
    if (!c.done) c,
];

List<ChecklistItem> checklistUncheckAll(List<ChecklistItem> items) => [
  for (final c in items) c.done ? c.copyWith(done: false) : c,
];

// ---------------------------------------------------------------- URLs / links

/// An http(s) URL without credentials or whitespace, ≤ 2000 chars.
bool isHttpUrl(String v) {
  if (v.length > linkUrlMax || RegExp(r'\s').hasMatch(v)) return false;
  final u = Uri.tryParse(v);
  if (u == null) return false;
  return (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty &&
      u.userInfo.isEmpty;
}

final _urlInTextRe = RegExp(
  r'''\bhttps?://[^\s<>"'`]+''',
  caseSensitive: false,
);

int _count(String s, String ch) => ch.allMatches(s).length;

/// URLs in a body, in order of first appearance, distinct. Trailing
/// punctuation (`.,;:!?'"*_~`) and unbalanced closing `)`/`]` are not part of
/// the URL (server `extractUrls`).
List<String> extractUrls(String body) {
  final out = <String>[];
  for (final m in _urlInTextRe.allMatches(body)) {
    var url = m.group(0)!;
    while (url.isNotEmpty) {
      final last = url[url.length - 1];
      if (".,;:!?'\"*_~".contains(last)) {
        url = url.substring(0, url.length - 1);
      } else if (last == ')' && _count(url, '(') < _count(url, ')')) {
        url = url.substring(0, url.length - 1);
      } else if (last == ']' && _count(url, '[') < _count(url, ']')) {
        url = url.substring(0, url.length - 1);
      } else {
        break;
      }
    }
    if (isHttpUrl(url) && !out.contains(url)) out.add(url);
  }
  return out;
}

/// The note's links (server `mergeLinks`): [sent] deduplicated, plus body URLs
/// not in it appended in order, capped at 20 (sent entries win the room). A link
/// without a title keeps the title [stored] for the same URL.
List<NoteLink> mergeLinks(
  List<NoteLink> sent,
  String body, {
  List<NoteLink> stored = const [],
}) {
  final storedTitle = {
    for (final l in stored)
      if (l.title != null) l.url: l.title,
  };
  final out = <NoteLink>[];
  for (final l in sent) {
    if (out.any((x) => x.url == l.url)) continue;
    out.add(NoteLink(url: l.url, title: l.title ?? storedTitle[l.url]));
  }
  for (final url in extractUrls(body)) {
    if (out.length >= maxNoteLinks) break;
    if (!out.any((l) => l.url == url)) {
      out.add(NoteLink(url: url, title: storedTitle[url]));
    }
  }
  return out.length > maxNoteLinks ? out.sublist(0, maxNoteLinks) : out;
}

/// Links after an edit of the body from [oldBody] to [newBody]: links that came
/// from the old body and are gone from the new one are dropped (shared links
/// stay), then [mergeLinks] adds the new body URLs.
List<NoteLink> syncBodyLinks(
  List<NoteLink> links,
  String oldBody,
  String newBody,
) {
  final before = extractUrls(oldBody).toSet();
  final now = extractUrls(newBody).toSet();
  return mergeLinks(
    [
      for (final l in links)
        if (!before.contains(l.url) || now.contains(l.url)) l,
    ],
    newBody,
    stored: links,
  );
}

/// Adds shared [urls] (http(s) only) to [links].
List<NoteLink> addLinks(List<NoteLink> links, Iterable<String> urls) =>
    mergeLinks([
      ...links,
      for (final u in urls)
        if (isHttpUrl(u.trim())) NoteLink(url: u.trim()),
    ], '');

// ---------------------------------------------------------------- amount

const _suffix = {'k': 1e3, 'rb': 1e3, 'ribu': 1e3, 'jt': 1e6, 'juta': 1e6};

/// `25.000` → 25000, `1.250.000,50` → 1250000.5, `25,5` → 25.5, `2.5` (+suffix)
/// → 2.5 (server `parseNumber`).
double? _parseNumber(String raw, bool hasSuffix) {
  var s = raw.replaceFirst(RegExp(r'[.,]$'), '');
  if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d+)?$').hasMatch(s)) {
    s = s.replaceAll('.', '').replaceFirst(',', '.');
  } else if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(s) && !hasSuffix) {
    s = s.replaceAll(',', '');
  } else if (RegExp(r'^\d+,\d+$').hasMatch(s)) {
    s = s.replaceFirst(',', '.');
  } else if (RegExp(r'^\d+\.\d{3}$').hasMatch(s) && !hasSuffix) {
    s = s.replaceFirst('.', '');
  }
  final n = double.tryParse(s);
  return n != null && n.isFinite && n > 0 ? n : null;
}

final _rpRe = RegExp(
  r'\bRp\.?\s*(\d[\d.,]*)\s*(k|rb|ribu|jt|juta)?\b',
  caseSensitive: false,
);
final _numRe = RegExp(
  r'(?<![\w.,])(\d[\d.,]*)\s*(k|rb|ribu|jt|juta)?(?![\w])',
  caseSensitive: false,
);

double? _value(RegExpMatch m) {
  final suffix = m.group(2)?.toLowerCase();
  final n = _parseNumber(m.group(1)!, suffix != null);
  if (n == null) return null;
  return (n * (suffix == null ? 1 : _suffix[suffix]!) * 100).round() / 100;
}

/// Amount for "→ Transaksi" (server `parseAmount`): the single distinct `Rp …`
/// amount in [text]; if there is none, the single distinct plain number ≥ 1000
/// (or with a k/rb/jt suffix). Several candidates → null (the user types it).
/// Dates and times aren't amounts.
double? parseAmount(String text) {
  final rp = <double>{for (final m in _rpRe.allMatches(text)) ?_value(m)};
  if (rp.isNotEmpty) return rp.length == 1 ? rp.first : null;
  final cleaned = text
      .replaceAll(RegExp(r'\b\d{1,4}[/-]\d{1,2}[/-]\d{1,4}\b'), ' ')
      .replaceAll(
        RegExp(r'\b\d{1,2}[:.]\d{2}\s*(wib|wita|wit)\b', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), ' ');
  final plain = <double>{};
  for (final m in _numRe.allMatches(cleaned)) {
    final v = _value(m);
    if (v == null) continue;
    if (m.group(2) != null || v >= 1000) plain.add(v);
  }
  return plain.length == 1 ? plain.first : null;
}

// ---------------------------------------------------------------- search

/// Lowercased text the search matches (server `noteMatches` haystack): title,
/// body, checklist texts, transcripts and link titles + URLs. Stored in a
/// device-only column for a fast `LIKE`.
String noteSearchText(Note n) => [
  n.title ?? '',
  n.body,
  for (final c in n.checklist) c.text,
  for (final a in n.audio) a.transcript ?? '',
  for (final l in n.links) '${l.title ?? ''} ${l.url}',
].join('\n').toLowerCase();

/// The words of a query (lowercased, split on whitespace).
List<String> searchWords(String? query) => [
  for (final w in (query ?? '').trim().toLowerCase().split(RegExp(r'\s+')))
    if (w.isNotEmpty) w,
];

/// Every word of [query] appears in the note (blank query = everything).
bool noteMatches(Note n, String? query) {
  final words = searchWords(query);
  if (words.isEmpty) return true;
  final hay = noteSearchText(n);
  return words.every(hay.contains);
}

/// Pinned first, then most recently updated.
int compareNotes(Note a, Note b) {
  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
  final c = b.updatedAt.compareTo(a.updatedAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

// ---------------------------------------------------------------- conversions

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

/// Plain-text body excerpt (markdown stripped, lines joined), ≤ [max] chars.
String bodyExcerpt(String body, {int max = 2000}) => _clip(
  [
    for (final l in body.split('\n'))
      if (stripMarkdown(l).isNotEmpty) stripMarkdown(l),
  ].join('\n'),
  max,
);

/// Title used when converting a note (server `noteDisplayTitle`): its title,
/// else the body's first line, else the first checklist text, else `Catatan`.
String noteActionTitle(Note n, {int max = noteTitleMax}) {
  final t = n.title;
  if (t != null && t.isNotEmpty) {
    return t.length > max ? t.substring(0, max) : t;
  }
  final l = firstLine(n.body, max: max);
  if (l.isNotEmpty) return l;
  for (final c in n.checklist) {
    if (c.text.isNotEmpty) {
      return c.text.length > max ? c.text.substring(0, max) : c.text;
    }
  }
  return 'Catatan';
}

/// Task note of "→ Tugas": the body excerpt, plus the checklist as
/// `- [x] item` lines, ≤ [max] chars.
String noteExcerpt(Note n, {int max = 2000}) => _clip(
  [
    if (bodyExcerpt(n.body, max: max).isNotEmpty) bodyExcerpt(n.body, max: max),
    if (n.checklist.isNotEmpty)
      [
        for (final c in n.checklist) '- [${c.done ? 'x' : ' '}] ${c.text}',
      ].join('\n'),
  ].join('\n\n'),
  max,
);

/// Prefill of the transaction form for "→ Transaksi" (`docs/notes.md`).
final class NoteTransactionDraft {
  const NoteTransactionDraft({
    required this.amount,
    required this.note,
    required this.photos,
  });

  /// The single amount found (see [parseAmount]), or null (ask the user).
  final double? amount;

  /// The note's title (or first line).
  final String note;

  /// The note's photos (first [maxTransactionPhotos]).
  final List<TransactionPhoto> photos;
}

/// Amount from title + body + checklist texts, note = [noteActionTitle].
NoteTransactionDraft noteTransactionDraft(Note n) => NoteTransactionDraft(
  amount: parseAmount(
    [n.title ?? '', n.body, for (final c in n.checklist) c.text].join('\n'),
  ),
  note: noteActionTitle(n),
  photos: n.photos.length > maxTransactionPhotos
      ? n.photos.sublist(0, maxTransactionPhotos)
      : n.photos,
);

/// App route of a note.
String noteRoute(String noteId) => '/notes/$noteId';
