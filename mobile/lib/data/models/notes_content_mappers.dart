/// Drift row ⇄ domain entity mappers of the notes and content tables (v4).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/usecases/notes_rules.dart' show noteSearchText;
import '../datasources/local/app_database.dart';
import 'mappers.dart' show decodePhotos, encodePhotos;

Object? _json(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

List<T> _list<T>(String? s, T? Function(Object?) parse) {
  final v = _json(s);
  if (v is! List) return const [];
  return List.unmodifiable([for (final x in v) ?parse(x)]);
}

List<String> _stringList(String? s) {
  final v = _json(s);
  if (v is! List) return const [];
  return List.unmodifiable([
    for (final x in v)
      if (x is String && x.isNotEmpty) x,
  ]);
}

List<ChecklistItem> decodeChecklist(String? s) =>
    _list(s, ChecklistItem.tryParse);

String encodeChecklist(List<ChecklistItem> items) =>
    jsonEncode([for (final c in items) c.toJson()]);

// ---------------------------------------------------------------- audio

/// Stored clip: `{url, durationSec, transcript}` or, pending upload,
/// `{local: <path>, durationSec, transcript}`.
NoteAudio? audioFromStored(Object? x) {
  if (x is! Map) return null;
  final d = x['durationSec'];
  final dur = d is num && d.isFinite ? d.round().clamp(0, 1 << 30) : 0;
  final t = x['transcript'];
  final transcript = t is String && t.isNotEmpty ? t : null;
  final local = x['local'];
  if (local is String && local.isNotEmpty) {
    return NoteAudio.local(local, durationSec: dur, transcript: transcript);
  }
  final url = x['url'];
  if (url is String && url.isNotEmpty) {
    return NoteAudio.remote(url, durationSec: dur, transcript: transcript);
  }
  return null;
}

Map<String, Object?> audioToStored(NoteAudio a) => {
  if (a.isPending) 'local': a.localPath else 'url': a.url,
  'durationSec': a.durationSec,
  'transcript': a.transcript,
};

List<NoteAudio> decodeAudio(String? s) => _list(s, audioFromStored);

String encodeAudio(List<NoteAudio> clips) =>
    jsonEncode([for (final a in clips) audioToStored(a)]);

// ---------------------------------------------------------------- notes

extension NoteRowX on NoteRow {
  Note toEntity() => Note(
    id: id,
    title: title,
    body: body,
    checklist: decodeChecklist(checklist),
    labelIds: _stringList(labels),
    color: color,
    pinned: pinned,
    archived: archived,
    photos: decodePhotos(photos),
    audio: decodeAudio(audio),
    links: _list(links, NoteLink.tryParse),
    source: NoteSource.tryFromWire(source),
    linkedTaskId: linkedTaskId,
    linkedContentId: linkedContentId,
    linkedTransactionId: linkedTransactionId,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension NoteX on Note {
  NotesCompanion toCompanion() => NotesCompanion.insert(
    id: id,
    title: Value(title),
    body: Value(body),
    checklist: Value(encodeChecklist(checklist)),
    labels: Value(jsonEncode(labelIds)),
    color: Value(color),
    pinned: Value(pinned),
    archived: Value(archived),
    photos: Value(encodePhotos(photos)),
    audio: Value(encodeAudio(audio)),
    links: Value(jsonEncode([for (final l in links) l.toJson()])),
    source: Value(source?.wire),
    linkedTaskId: Value(linkedTaskId),
    linkedContentId: Value(linkedContentId),
    linkedTransactionId: Value(linkedTransactionId),
    searchText: Value(noteSearchText(this)),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension NoteLabelRowX on NoteLabelRow {
  NoteLabel toEntity() => NoteLabel(
    id: id,
    name: name,
    color: color,
    pinnedTab: pinnedTab,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension NoteLabelX on NoteLabel {
  NoteLabelsCompanion toCompanion() => NoteLabelsCompanion.insert(
    id: id,
    name: name,
    color: Value(color),
    pinnedTab: Value(pinnedTab),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- content

extension SocialAccountRowX on SocialAccountRow {
  SocialAccount toEntity() {
    final p = SocialPlatform.fromWire(platform);
    return SocialAccount(
      id: id,
      platform: p,
      // An unknown platform (newer server) shows under its raw name.
      platformName: p == SocialPlatform.other && platform != 'other'
          ? (platformName ?? platform)
          : platformName,
      handle: handle,
      color: color,
      targetPerWeek: targetPerWeek,
      archived: archived,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension SocialAccountX on SocialAccount {
  SocialAccountsCompanion toCompanion() => SocialAccountsCompanion.insert(
    id: id,
    platform: platform.wire,
    platformName: Value(platformName),
    handle: handle,
    color: color,
    targetPerWeek: Value(targetPerWeek),
    archived: Value(archived),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

Map<ContentStage, DateTime> decodeStageLog(String? s) {
  final v = _json(s);
  if (v is! Map) return const {};
  return Map.unmodifiable({
    for (final e in v.entries)
      if (e.value is num)
        for (final st in ContentStage.values)
          if (st.wire == e.key)
            st: DateTime.fromMillisecondsSinceEpoch((e.value as num).toInt()),
  });
}

/// Key of [ContentItem.sponsorPaidAt] in the device-only `stage_log` JSON.
const _sponsorPaidKey = 'sponsorPaid';

DateTime? decodeSponsorPaidAt(String? s) {
  final v = _json(s);
  final t = v is Map ? v[_sponsorPaidKey] : null;
  return t is num ? DateTime.fromMillisecondsSinceEpoch(t.toInt()) : null;
}

String encodeStageLog(
  Map<ContentStage, DateTime> log, {
  DateTime? sponsorPaidAt,
}) => jsonEncode({
  for (final s in ContentStage.values)
    if (log[s] != null) s.wire: log[s]!.millisecondsSinceEpoch,
  if (sponsorPaidAt != null)
    _sponsorPaidKey: sponsorPaidAt.millisecondsSinceEpoch,
});

extension ContentItemRowX on ContentItemRow {
  ContentItem toEntity() => ContentItem(
    id: id,
    title: title,
    stage: ContentStage.fromWire(stage),
    format: ContentFormat.tryFromWire(format),
    pillar: pillar,
    idea: idea,
    noteId: noteId,
    checklist: decodeChecklist(checklist),
    photos: decodePhotos(photos),
    assetLinks: _list(assetLinks, AssetLink.tryParse),
    sponsor: Sponsor.tryParse(_json(sponsor)),
    stageReachedAt: decodeStageLog(stageLog),
    sponsorPaidAt: decodeSponsorPaidAt(stageLog),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension ContentItemX on ContentItem {
  ContentItemsCompanion toCompanion() => ContentItemsCompanion.insert(
    id: id,
    title: title,
    stage: Value(stage.wire),
    format: Value(format?.wire),
    pillar: Value(pillar),
    idea: Value(idea),
    noteId: Value(noteId),
    checklist: Value(encodeChecklist(checklist)),
    photos: Value(encodePhotos(photos)),
    assetLinks: Value(jsonEncode([for (final l in assetLinks) l.toJson()])),
    sponsor: Value(sponsor == null ? null : jsonEncode(sponsor!.toJson())),
    stageLog: Value(
      encodeStageLog(stageReachedAt, sponsorPaidAt: sponsorPaidAt),
    ),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension ContentPostRowX on ContentPostRow {
  ContentPost toEntity() => ContentPost(
    id: id,
    contentId: contentId,
    accountId: accountId,
    caption: caption,
    hashtags: hashtags,
    scheduledAt: scheduledAt,
    remindBefore: remindBefore,
    status: PostStatus.fromWire(status),
    postedAt: postedAt,
    url: url,
    metrics: PostMetrics.parse(_json(metrics)),
    metricsAt: metricsAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension ContentPostX on ContentPost {
  ContentPostsCompanion toCompanion() => ContentPostsCompanion.insert(
    id: id,
    contentId: contentId,
    accountId: accountId,
    caption: Value(caption),
    hashtags: Value(hashtags),
    scheduledAt: Value(scheduledAt),
    remindBefore: Value(remindBefore),
    status: Value(status.wire),
    postedAt: Value(postedAt),
    url: Value(url),
    metrics: Value(jsonEncode(metrics.toJson())),
    metricsAt: Value(metricsAt),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension ContentPillarRowX on ContentPillarRow {
  ContentPillar toEntity() => ContentPillar(
    id: id,
    name: name,
    color: color,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension ContentPillarX on ContentPillar {
  ContentPillarsCompanion toCompanion() => ContentPillarsCompanion.insert(
    id: id,
    name: name,
    color: Value(color),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
