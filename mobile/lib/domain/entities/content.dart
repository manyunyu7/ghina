/// Content planner (own social accounts) — `docs/content.md`. Pure value types;
/// rules (stage auto-advance, weekly targets, reports, reminders) live in
/// `domain/usecases/content_rules.dart`.
library;

import 'note.dart' show ChecklistItem;
import 'transaction_photo.dart';
import 'value_equality.dart';

const _unset = Object();

/// Limits — same as the server (`src/lib/content.ts`).
const contentTitleMax = 200;
const captionMax = 5000;
const hashtagsMax = 1000;
const handleMax = 60;
const platformNameMax = 30;
const pillarNameMax = 30;
const maxContentPhotos = 10;
const maxAssetLinks = 20;
const assetLabelMax = 100;
const brandMax = 100;
const targetPerWeekMax = 50;

/// XP for an account meeting its weekly target (gamification rules).
const weeklyTargetXp = 20;

/// Built-in platforms (same registry as the web, `src/lib/content.ts`
/// `PLATFORMS`). [code] is the notification code (`[IG-TAYANG] …`), [color]
/// the default account color, [icon] a lucide icon name (lucide has no brand
/// logos — pair it with the code/color). URL templates take `{handle}` (without
/// `@`, URL-encoded): [profileUrl] the profile page, [createUrl] where to publish
/// (web), [appUrl] the app deep link (may fail when the app is missing → fall
/// back to [profileUrl]). All null for [other].
enum SocialPlatform {
  instagram(
    'instagram',
    'Instagram',
    'IG',
    '#E1306C',
    'camera',
    'https://www.instagram.com/{handle}/',
    'https://www.instagram.com/',
    'instagram://user?username={handle}',
  ),
  tiktok(
    'tiktok',
    'TikTok',
    'TT',
    '#FE2C55',
    'music-2',
    'https://www.tiktok.com/@{handle}',
    'https://www.tiktok.com/upload',
    'snssdk1233://user/profile/{handle}',
  ),
  youtube(
    'youtube',
    'YouTube',
    'YT',
    '#FF0000',
    'play',
    'https://www.youtube.com/@{handle}',
    'https://studio.youtube.com/',
    'vnd.youtube://www.youtube.com/@{handle}',
  ),
  x(
    'x',
    'X',
    'X',
    '#0F1419',
    'at-sign',
    'https://x.com/{handle}',
    'https://x.com/compose/post',
    'twitter://user?screen_name={handle}',
  ),
  threads(
    'threads',
    'Threads',
    'TH',
    '#101010',
    'at-sign',
    'https://www.threads.net/@{handle}',
    'https://www.threads.net/',
    'barcelona://user?username={handle}',
  ),
  linkedin(
    'linkedin',
    'LinkedIn',
    'IN',
    '#0A66C2',
    'briefcase',
    'https://www.linkedin.com/in/{handle}/',
    'https://www.linkedin.com/feed/?shareActive=true',
    'linkedin://in/{handle}',
  ),
  facebook(
    'facebook',
    'Facebook',
    'FB',
    '#1877F2',
    'users',
    'https://www.facebook.com/{handle}',
    'https://www.facebook.com/',
    'fb://facewebmodal/f?href=https://www.facebook.com/{handle}',
  ),
  other('other', 'Lainnya', 'LAIN', '#8E8E93', 'globe', null, null, null);

  const SocialPlatform(
    this.wire,
    this.label,
    this.code,
    this.color,
    this.icon,
    this.profileUrl,
    this.createUrl,
    this.appUrl,
  );

  final String wire;
  final String label;

  /// Notification code. `other` accounts derive theirs from `platformName`
  /// (see [SocialAccount.code]).
  final String code;

  /// Default account color `#rrggbb`.
  final String color;
  final String icon;
  final String? profileUrl;
  final String? createUrl;
  final String? appUrl;

  /// Unknown values (newer server) → [other].
  static SocialPlatform fromWire(String? v) =>
      values.firstWhere((p) => p.wire == v, orElse: () => SocialPlatform.other);
}

/// Fills a platform URL template with [handle] (leading `@` dropped,
/// URL-encoded). Null template → null (server `platformUrl`).
String? platformUrl(String? template, String handle) {
  if (template == null) return null;
  final h = Uri.encodeComponent(handle.trim().replaceFirst(RegExp(r'^@+'), ''));
  return template.replaceAll('{handle}', h);
}

/// Pipeline columns, in order.
enum ContentStage {
  ide('ide', 'Ide', '💡', '#AFAFAF', 0),
  naskah('naskah', 'Naskah', '✍️', '#1CB0F6', 3),
  produksi('produksi', 'Produksi', '🎬', '#CE82FF', 4),
  siap('siap', 'Siap', '✅', '#FF9600', 5),
  terjadwal('terjadwal', 'Terjadwal', '📅', '#FFC800', 6),
  tayang('tayang', 'Tayang', '🚀', '#58CC02', 10);

  const ContentStage(this.wire, this.label, this.emoji, this.color, this.xp);
  final String wire;
  final String label;
  final String emoji;

  /// `#rrggbb` (same as the web).
  final String color;

  /// XP for newly reaching this stage (server `STAGES[].xp`; see `stageXp`).
  final int xp;

  bool isAfter(ContentStage o) => index > o.index;
  bool isBefore(ContentStage o) => index < o.index;

  /// Unknown values → [ide] (the server default).
  static ContentStage fromWire(String? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => ContentStage.ide);
}

enum ContentFormat {
  post('post', 'Post'),
  carousel('carousel', 'Carousel'),
  reel('reel', 'Reel'),
  story('story', 'Story'),
  video('video', 'Video'),
  short('short', 'Short'),
  thread('thread', 'Thread'),
  live('live', 'Live'),
  other('other', 'Lainnya');

  const ContentFormat(this.wire, this.label);
  final String wire;
  final String label;

  static ContentFormat? tryFromWire(String? v) {
    if (v == null) return null;
    for (final f in values) {
      if (f.wire == v) return f;
    }
    return ContentFormat.other;
  }
}

/// Status of one post (per account).
enum PostStatus {
  draft('draft', 'Draf', '#AFAFAF'),
  scheduled('scheduled', 'Terjadwal', '#FFC800'),
  posted('posted', 'Tayang', '#58CC02'),
  skipped('skipped', 'Dilewati', '#777777');

  const PostStatus(this.wire, this.label, this.color);
  final String wire;
  final String label;
  final String color;

  static PostStatus fromWire(String? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => PostStatus.draft);
}

/// One of the user's own social accounts.
final class SocialAccount with ValueEquality {
  const SocialAccount({
    required this.id,
    required this.platform,
    this.platformName,
    required this.handle,
    required this.color,
    this.targetPerWeek,
    this.archived = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final SocialPlatform platform;

  /// Display name when [platform] is `other` (e.g. "Pinterest").
  final String? platformName;

  /// `@username` or channel name, ≤ 60 (stored as typed).
  final String handle;
  final String color;

  /// Posting goal per ISO week (Mon–Sun); null = none.
  final int? targetPerWeek;
  final bool archived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// `Instagram`, or the custom name for `other` (`Lainnya` when empty).
  String get platformLabel => platform == SocialPlatform.other
      ? ((platformName ?? '').trim().isEmpty
            ? platform.label
            : platformName!.trim())
      : platform.label;

  /// Notification code: `IG`, `TT`, `YT`, `X`, `TH`, `IN`, `FB` — for `other`,
  /// derived from the name (`Pinterest` → `PINT`, see `otherPlatformCode`).
  String get code => platform == SocialPlatform.other
      ? otherPlatformCode(platformName)
      : platform.code;

  /// Handle without a leading `@`.
  String get bareHandle => handle.trim().replaceFirst(RegExp(r'^@+'), '');

  /// `@handle` (for display).
  String get atHandle => '@$bareHandle';

  /// Profile page (web), or null for `other`.
  String? get profileUrl => platformUrl(platform.profileUrl, handle);

  /// App deep link ("Buka Instagram"); if it can't be launched use
  /// [profileUrl]. Null for `other`.
  String? get appUrl => platformUrl(platform.appUrl, handle);

  /// Where to publish on the web, or null.
  String? get createUrl => platform.createUrl;

  bool get hasTarget => (targetPerWeek ?? 0) > 0;

  SocialAccount copyWith({
    SocialPlatform? platform,
    Object? platformName = _unset,
    String? handle,
    String? color,
    Object? targetPerWeek = _unset,
    bool? archived,
    int? sortOrder,
    DateTime? updatedAt,
  }) => SocialAccount(
    id: id,
    platform: platform ?? this.platform,
    platformName: identical(platformName, _unset)
        ? this.platformName
        : platformName as String?,
    handle: handle ?? this.handle,
    color: color ?? this.color,
    targetPerWeek: identical(targetPerWeek, _unset)
        ? this.targetPerWeek
        : targetPerWeek as int?,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    platform,
    platformName,
    handle,
    color,
    targetPerWeek,
    archived,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'SocialAccount($id, $code $handle)';
}

const _diacritics = {
  'À': 'A',
  'Á': 'A',
  'Â': 'A',
  'Ã': 'A',
  'Ä': 'A',
  'Å': 'A',
  'Ç': 'C',
  'È': 'E',
  'É': 'E',
  'Ê': 'E',
  'Ë': 'E',
  'Ì': 'I',
  'Í': 'I',
  'Î': 'I',
  'Ï': 'I',
  'Ñ': 'N',
  'Ò': 'O',
  'Ó': 'O',
  'Ô': 'O',
  'Õ': 'O',
  'Ö': 'O',
  'Ù': 'U',
  'Ú': 'U',
  'Û': 'U',
  'Ü': 'U',
  'Ý': 'Y',
  'Ÿ': 'Y',
};

/// The notification code of an `other` platform: the first 4 letters/digits
/// of its name, uppercased, accents folded (`Pinterest` → `PINT`, `Snack
/// Video` → `SNAC`); `LAIN` when there are none (server `platformShort`).
String otherPlatformCode(String? platformName) {
  final up = (platformName ?? '').toUpperCase();
  final b = StringBuffer();
  for (final r in up.runes) {
    final ch = String.fromCharCode(r);
    final c = _diacritics[ch] ?? ch;
    if (RegExp(r'^[A-Z0-9]$').hasMatch(c)) b.write(c);
    if (b.length >= 4) break;
  }
  return b.isEmpty ? SocialPlatform.other.code : b.toString();
}

/// A link to an asset (Drive/Canva/CapCut…). [label] ≤ 100, null = none.
final class AssetLink with ValueEquality {
  const AssetLink({required this.url, this.label});

  final String url;
  final String? label;

  Map<String, Object?> toJson() => {'url': url, 'label': label};

  static AssetLink? tryParse(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    final l = json['label'];
    return AssetLink(url: url, label: l is String && l.isNotEmpty ? l : null);
  }

  @override
  List<Object?> get props => [url, label];
}

/// Sponsorship of a content item (endorse).
final class Sponsor with ValueEquality {
  const Sponsor({
    required this.brand,
    required this.amount,
    this.currency = 'IDR',
    this.due,
    this.paid = false,
    this.transactionId,
  });

  final String brand;

  /// ≥ 0 (0 = barter).
  final double amount;

  /// 3 letters, uppercase (`IDR`).
  final String currency;

  /// Payment due date `YYYY-MM-DD` (local day), or null.
  final String? due;
  final bool paid;

  /// The income transaction recorded when it was paid (nulled when that
  /// transaction is deleted).
  final String? transactionId;

  Sponsor copyWith({
    String? brand,
    double? amount,
    String? currency,
    Object? due = _unset,
    bool? paid,
    Object? transactionId = _unset,
  }) => Sponsor(
    brand: brand ?? this.brand,
    amount: amount ?? this.amount,
    currency: currency ?? this.currency,
    due: identical(due, _unset) ? this.due : due as String?,
    paid: paid ?? this.paid,
    transactionId: identical(transactionId, _unset)
        ? this.transactionId
        : transactionId as String?,
  );

  Map<String, Object?> toJson() => {
    'brand': brand,
    'amount': amount,
    'currency': currency,
    'due': due,
    'paid': paid,
    'transactionId': transactionId,
  };

  static Sponsor? tryParse(Object? json) {
    if (json is! Map) return null;
    final brand = json['brand'], amount = json['amount'];
    if (brand is! String || amount is! num) return null;
    final due = json['due'];
    final tx = json['transactionId'];
    final cur = json['currency'];
    return Sponsor(
      brand: brand,
      amount: amount.toDouble(),
      currency: cur is String && cur.isNotEmpty ? cur : 'IDR',
      // Accept a timestamp too: keep its date part.
      due: due is String && due.length >= 10 ? due.substring(0, 10) : null,
      paid: json['paid'] == true,
      transactionId: tx is String && tx.isNotEmpty ? tx : null,
    );
  }

  @override
  List<Object?> get props => [
    brand,
    amount,
    currency,
    due,
    paid,
    transactionId,
  ];
}

/// A piece of content moving through the pipeline.
final class ContentItem with ValueEquality {
  const ContentItem({
    required this.id,
    required this.title,
    this.stage = ContentStage.ide,
    this.format,
    this.pillar,
    this.idea = '',
    this.noteId,
    this.checklist = const [],
    this.photos = const [],
    this.assetLinks = const [],
    this.sponsor,
    this.stageReachedAt = const {},
    this.sponsorPaidAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ContentStage stage;
  final ContentFormat? format;

  /// Pillar **name** (see [ContentPillar]); null = none.
  final String? pillar;

  /// Markdown: idea / script / notes.
  final String idea;

  /// Source note (converted from), or null.
  final String? noteId;

  /// Production checklist.
  final List<ChecklistItem> checklist;
  final List<TransactionPhoto> photos;
  final List<AssetLink> assetLinks;
  final Sponsor? sponsor;

  /// Device-only: when this device first saw the item at each stage (see
  /// `lib/domain/game/README.md` → Content). Not synced; the model has no
  /// per-stage timestamps, so a stage first seen through a pull gets the row's
  /// `updatedAt`. Only stages up to [stage] count as reached.
  final Map<ContentStage, DateTime> stageReachedAt;

  /// Device-only (like [stageReachedAt]): when this device first saw the
  /// sponsor paid (a pull: the row's `updatedAt`); null while unpaid. A stable
  /// time for the "sponsor paid" XP when no income transaction is linked.
  final DateTime? sponsorPaidAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasSponsor => sponsor != null;
  int get checklistDone => checklist.where((c) => c.done).length;

  ContentItem copyWith({
    String? title,
    ContentStage? stage,
    Object? format = _unset,
    Object? pillar = _unset,
    String? idea,
    Object? noteId = _unset,
    List<ChecklistItem>? checklist,
    List<TransactionPhoto>? photos,
    List<AssetLink>? assetLinks,
    Object? sponsor = _unset,
    Map<ContentStage, DateTime>? stageReachedAt,
    Object? sponsorPaidAt = _unset,
    DateTime? updatedAt,
  }) => ContentItem(
    id: id,
    title: title ?? this.title,
    stage: stage ?? this.stage,
    format: identical(format, _unset) ? this.format : format as ContentFormat?,
    pillar: identical(pillar, _unset) ? this.pillar : pillar as String?,
    idea: idea ?? this.idea,
    noteId: identical(noteId, _unset) ? this.noteId : noteId as String?,
    checklist: checklist ?? this.checklist,
    photos: photos ?? this.photos,
    assetLinks: assetLinks ?? this.assetLinks,
    sponsor: identical(sponsor, _unset) ? this.sponsor : sponsor as Sponsor?,
    stageReachedAt: stageReachedAt ?? this.stageReachedAt,
    sponsorPaidAt: identical(sponsorPaidAt, _unset)
        ? this.sponsorPaidAt
        : sponsorPaidAt as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    stage,
    format,
    pillar,
    idea,
    noteId,
    checklist,
    photos,
    assetLinks,
    sponsor,
    stageReachedAt,
    sponsorPaidAt,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'ContentItem($id, $title, ${stage.wire})';
}

/// Manually entered performance of a post. Every field optional.
final class PostMetrics with ValueEquality {
  const PostMetrics({
    this.views,
    this.likes,
    this.comments,
    this.shares,
    this.saves,
    this.followers,
  });

  static const empty = PostMetrics();

  final int? views;
  final int? likes;
  final int? comments;
  final int? shares;
  final int? saves;

  /// Followers gained.
  final int? followers;

  bool get isEmpty =>
      views == null &&
      likes == null &&
      comments == null &&
      shares == null &&
      saves == null &&
      followers == null;

  /// likes + comments + shares + saves (missing = 0).
  int get engagement =>
      (likes ?? 0) + (comments ?? 0) + (shares ?? 0) + (saves ?? 0);

  Map<String, Object?> toJson() => {
    'views': ?views,
    'likes': ?likes,
    'comments': ?comments,
    'shares': ?shares,
    'saves': ?saves,
    'followers': ?followers,
  };

  static PostMetrics parse(Object? json) {
    if (json is! Map) return empty;
    int? n(String k) {
      final v = json[k];
      return v is num && v.isFinite && v >= 0 ? v.round() : null;
    }

    return PostMetrics(
      views: n('views'),
      likes: n('likes'),
      comments: n('comments'),
      shares: n('shares'),
      saves: n('saves'),
      followers: n('followers'),
    );
  }

  @override
  List<Object?> get props => [views, likes, comments, shares, saves, followers];
}

/// One post of a content item on one account (the "variant").
final class ContentPost with ValueEquality {
  const ContentPost({
    required this.id,
    required this.contentId,
    required this.accountId,
    this.caption = '',
    this.hashtags = '',
    this.scheduledAt,
    this.remindBefore,
    this.status = PostStatus.draft,
    this.postedAt,
    this.url,
    this.metrics = PostMetrics.empty,
    this.metricsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String contentId;
  final String accountId;
  final String caption;

  /// Free text (`#a #b`).
  final String hashtags;

  /// Planned publish time (local).
  final DateTime? scheduledAt;

  /// Minutes before [scheduledAt]; null = no reminder.
  final int? remindBefore;
  final PostStatus status;
  final DateTime? postedAt;

  /// Link to the live post.
  final String? url;
  final PostMetrics metrics;
  final DateTime? metricsAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPosted => status == PostStatus.posted;
  bool get isSkipped => status == PostStatus.skipped;
  bool get isScheduled => status == PostStatus.scheduled;

  /// When the reminder fires (scheduled posts with a reminder only).
  DateTime? get remindAt =>
      status == PostStatus.scheduled &&
          scheduledAt != null &&
          remindBefore != null
      ? scheduledAt!.subtract(Duration(minutes: remindBefore!))
      : null;

  /// Calendar date: `postedAt` for posted posts, else `scheduledAt`.
  DateTime? get calendarAt =>
      isPosted ? (postedAt ?? scheduledAt) : scheduledAt;

  /// What "Salin caption + hashtag" copies (server `captionWithHashtags`).
  String get copyText {
    final c = caption.trimRight(), h = hashtags.trim();
    if (c.isEmpty) return h;
    if (h.isEmpty) return c;
    return '$c\n\n$h';
  }

  ContentPost copyWith({
    String? accountId,
    String? caption,
    String? hashtags,
    Object? scheduledAt = _unset,
    Object? remindBefore = _unset,
    PostStatus? status,
    Object? postedAt = _unset,
    Object? url = _unset,
    PostMetrics? metrics,
    Object? metricsAt = _unset,
    DateTime? updatedAt,
  }) => ContentPost(
    id: id,
    contentId: contentId,
    accountId: accountId ?? this.accountId,
    caption: caption ?? this.caption,
    hashtags: hashtags ?? this.hashtags,
    scheduledAt: identical(scheduledAt, _unset)
        ? this.scheduledAt
        : scheduledAt as DateTime?,
    remindBefore: identical(remindBefore, _unset)
        ? this.remindBefore
        : remindBefore as int?,
    status: status ?? this.status,
    postedAt: identical(postedAt, _unset)
        ? this.postedAt
        : postedAt as DateTime?,
    url: identical(url, _unset) ? this.url : url as String?,
    metrics: metrics ?? this.metrics,
    metricsAt: identical(metricsAt, _unset)
        ? this.metricsAt
        : metricsAt as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    contentId,
    accountId,
    caption,
    hashtags,
    scheduledAt,
    remindBefore,
    status,
    postedAt,
    url,
    metrics,
    metricsAt,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'ContentPost($id, ${status.wire}, $scheduledAt)';
}

/// A user-defined content pillar (Edukasi, Hiburan, …). Items refer to it by
/// [name].
final class ContentPillar with ValueEquality {
  const ContentPillar({
    required this.id,
    required this.name,
    required this.color,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 1–30, unique per user (case-insensitive).
  final String name;
  final String color;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContentPillar copyWith({
    String? name,
    String? color,
    int? sortOrder,
    DateTime? updatedAt,
  }) => ContentPillar(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [id, name, color, sortOrder, createdAt, updatedAt];

  @override
  String toString() => 'ContentPillar($id, $name)';
}
