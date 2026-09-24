/// JSON wire format of the notes and content entities (`docs/mobile-sync.md`,
/// `docs/notes.md`, `docs/content.md`). JSON fields travel as JSON values.
///
/// `*ToWire` builds the push `data`; `*FromWire` parses a pulled row into an
/// entity, tolerating missing fields (older/newer servers): a missing value
/// falls back to the model default.
library;

import 'dart:convert';

import '../../domain/entities/entities.dart';
import 'mappers.dart' show localPhotoPrefix;
import 'wire.dart' show Json, isoUtc;

/// An uploaded image path (server `IMAGE_UPLOAD_RE`).
final uploadImageRe = RegExp(
  r'^/uploads/[A-Za-z0-9-]+\.(jpg|png|webp|gif|heic|heif)$',
);

/// An uploaded audio path (server `AUDIO_UPLOAD_RE`).
final uploadAudioRe = RegExp(
  r'^/uploads/[A-Za-z0-9-]+\.(m4a|aac|mp3|ogg|webm)$',
);

/// Uploaded photo paths in order, distinct, at most [max] — pending ones and
/// anything the server would reject are left out.
List<String> wireMediaPhotos(List<TransactionPhoto> photos, int max) {
  final out = <String>[];
  for (final p in photos) {
    final url = p.url;
    if (p.isPending || url == null || !uploadImageRe.hasMatch(url)) continue;
    if (!out.contains(url)) out.add(url);
  }
  return out.length > max ? out.sublist(0, max) : out;
}

/// Uploaded clips only (pending ones are uploaded first by the sync engine).
List<Json> wireAudio(List<NoteAudio> clips) {
  final out = <Json>[];
  for (final a in clips) {
    final url = a.url;
    if (a.isPending || url == null || !uploadAudioRe.hasMatch(url)) continue;
    if (out.any((x) => x['url'] == url)) continue;
    final t = a.transcript?.trim();
    out.add({
      'url': url,
      'durationSec': a.durationSec.clamp(0, audioDurationMax),
      'transcript': t == null || t.isEmpty
          ? null
          : (t.length > transcriptMax ? t.substring(0, transcriptMax) : t),
    });
  }
  return out.length > maxNoteAudio ? out.sublist(0, maxNoteAudio) : out;
}

// ---------------------------------------------------------------- to wire

Json noteToWire(Note n) => {
  'title': n.title,
  'body': n.body,
  'checklist': [for (final c in n.checklist) c.toJson()],
  'labels': n.labelIds,
  'color': n.color,
  'pinned': n.pinned,
  'archived': n.archived,
  'photos': wireMediaPhotos(n.photos, maxNotePhotos),
  'audio': wireAudio(n.audio),
  'links': [for (final l in n.links) l.toJson()],
  'source': n.source?.wire,
  'linkedTaskId': n.linkedTaskId,
  'linkedContentId': n.linkedContentId,
  'linkedTransactionId': n.linkedTransactionId,
};

Json noteLabelToWire(NoteLabel l) => {
  'name': l.name,
  'color': l.color,
  'pinnedTab': l.pinnedTab,
  'sortOrder': l.sortOrder,
};

Json socialAccountToWire(SocialAccount a) => {
  'platform': a.platform.wire,
  'platformName': a.platformName,
  'handle': a.handle,
  'color': a.color,
  'targetPerWeek': a.targetPerWeek,
  'archived': a.archived,
  'sortOrder': a.sortOrder,
};

/// `stageReachedAt` is device-only and never sent.
Json contentItemToWire(ContentItem i) => {
  'title': i.title,
  'stage': i.stage.wire,
  'format': i.format?.wire,
  'pillar': i.pillar,
  'idea': i.idea,
  'noteId': i.noteId,
  'checklist': [for (final c in i.checklist) c.toJson()],
  'photos': wireMediaPhotos(i.photos, maxContentPhotos),
  'assetLinks': [for (final l in i.assetLinks) l.toJson()],
  'sponsor': i.sponsor?.toJson(),
};

Json contentPostToWire(ContentPost p) => {
  'contentId': p.contentId,
  'accountId': p.accountId,
  'caption': p.caption,
  'hashtags': p.hashtags,
  'scheduledAt': p.scheduledAt == null ? null : isoUtc(p.scheduledAt!),
  'remindBefore': p.remindBefore,
  'status': p.status.wire,
  'postedAt': p.postedAt == null ? null : isoUtc(p.postedAt!),
  'url': p.url,
  'metrics': p.metrics.toJson(),
  'metricsAt': p.metricsAt == null ? null : isoUtc(p.metricsAt!),
};

Json contentPillarToWire(ContentPillar p) => {
  'name': p.name,
  'color': p.color,
  'sortOrder': p.sortOrder,
};

// ---------------------------------------------------------------- from wire

/// A JSON value; a JSON-encoded string is tolerated too.
Object? _jsonValue(Object? v) {
  if (v is String) {
    try {
      return jsonDecode(v);
    } catch (_) {
      return null;
    }
  }
  return v;
}

List<T> _listOf<T>(Object? v, T? Function(Object?) parse) {
  final x = _jsonValue(v);
  if (x is! List) return const [];
  return List.unmodifiable([for (final e in x) ?parse(e)]);
}

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _dateN(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
int? _intN(Object? v) => v is num && v.isFinite ? v.round() : null;
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

DateTime _created(Json j) => _date(j['createdAt']);
DateTime _updated(Json j) =>
    j['updatedAt'] == null ? _created(j) : _date(j['updatedAt']);

List<TransactionPhoto> _photos(Object? v) => _listOf(
  v,
  (x) => x is String && x.isNotEmpty && !x.startsWith(localPhotoPrefix)
      ? TransactionPhoto.remote(x)
      : null,
);

NoteAudio? _audio(Object? x) {
  if (x is! Map) return null;
  final url = x['url'];
  if (url is! String || url.isEmpty) return null;
  return NoteAudio.remote(
    url,
    durationSec: _intN(x['durationSec'])?.clamp(0, 1 << 30) ?? 0,
    transcript: _strN(x['transcript']),
  );
}

List<String> _ids(Object? v) =>
    _listOf(v, (x) => x is String && x.isNotEmpty ? x : null).toSet().toList();

Note noteFromWire(Json j) => Note(
  id: j['id'] as String,
  title: _strN(j['title']),
  body: _str(j['body']),
  checklist: _listOf(j['checklist'], ChecklistItem.tryParse),
  labelIds: _ids(j['labels']),
  color: _strN(j['color']),
  pinned: _bool(j['pinned']),
  archived: _bool(j['archived']),
  photos: _photos(j['photos']),
  audio: _listOf(j['audio'], _audio),
  links: _listOf(j['links'], NoteLink.tryParse),
  source: NoteSource.tryFromWire(j['source'] as String?),
  linkedTaskId: _strN(j['linkedTaskId']),
  linkedContentId: _strN(j['linkedContentId']),
  linkedTransactionId: _strN(j['linkedTransactionId']),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

NoteLabel noteLabelFromWire(Json j) => NoteLabel(
  id: j['id'] as String,
  name: _str(j['name']),
  color: _strN(j['color']) ?? defaultLabelColor,
  pinnedTab: _bool(j['pinnedTab']),
  sortOrder: _intN(j['sortOrder']) ?? 0,
  createdAt: _created(j),
  updatedAt: _updated(j),
);

SocialAccount socialAccountFromWire(Json j) {
  final raw = _str(j['platform'], 'other');
  final p = SocialPlatform.fromWire(raw);
  return SocialAccount(
    id: j['id'] as String,
    platform: p,
    platformName:
        _strN(j['platformName']) ??
        (p == SocialPlatform.other && raw != 'other' ? raw : null),
    handle: _str(j['handle']),
    color: _strN(j['color']) ?? p.color,
    targetPerWeek: _intN(j['targetPerWeek']),
    archived: _bool(j['archived']),
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: _created(j),
    updatedAt: _updated(j),
  );
}

/// `stageReachedAt` is left empty (merged by the sync engine).
ContentItem contentItemFromWire(Json j) => ContentItem(
  id: j['id'] as String,
  title: _str(j['title']),
  stage: ContentStage.fromWire(j['stage'] as String?),
  format: ContentFormat.tryFromWire(_strN(j['format'])),
  pillar: _strN(j['pillar']),
  idea: _str(j['idea']),
  noteId: _strN(j['noteId']),
  checklist: _listOf(j['checklist'], ChecklistItem.tryParse),
  photos: _photos(j['photos']),
  assetLinks: _listOf(j['assetLinks'], AssetLink.tryParse),
  sponsor: Sponsor.tryParse(_jsonValue(j['sponsor'])),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

ContentPost contentPostFromWire(Json j) => ContentPost(
  id: j['id'] as String,
  contentId: _str(j['contentId']),
  accountId: _str(j['accountId']),
  caption: _str(j['caption']),
  hashtags: _str(j['hashtags']),
  scheduledAt: _dateN(j['scheduledAt']),
  remindBefore: _intN(j['remindBefore']),
  status: PostStatus.fromWire(j['status'] as String?),
  postedAt: _dateN(j['postedAt']),
  url: _strN(j['url']),
  metrics: PostMetrics.parse(_jsonValue(j['metrics'])),
  metricsAt: _dateN(j['metricsAt']),
  createdAt: _created(j),
  updatedAt: _updated(j),
);

ContentPillar contentPillarFromWire(Json j) => ContentPillar(
  id: j['id'] as String,
  name: _str(j['name']),
  color: _strN(j['color']) ?? defaultLabelColor,
  sortOrder: _intN(j['sortOrder']) ?? 0,
  createdAt: _created(j),
  updatedAt: _updated(j),
);
