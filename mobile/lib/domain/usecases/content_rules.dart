/// Pure content-planner rules — a port of the server's `src/lib/content.ts`
/// (`docs/content.md`): default pillars, stage auto-advance and XP, ISO weeks,
/// weekly slots and consistency, board/calendar/report builders, sponsor
/// summary, post reminders. Constants and algorithms must match the server.
/// Calendar days are the device's local days (the server uses Asia/Jakarta).
library;

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../entities/entities.dart';
import 'notes_rules.dart' show compareNotes, findIdeaLabel, nameKey;

// ---------------------------------------------------------------- pillars

/// Default pillars (`docs/content.md`): key (id slug), name, color.
const defaultPillarSpecs = [
  (key: 'edukasi', name: 'Edukasi', color: '#1CB0F6'),
  (key: 'hiburan', name: 'Hiburan', color: '#FF9600'),
  (key: 'promo', name: 'Promo', color: '#FF4B4B'),
  (key: 'bts', name: 'Behind the scene', color: '#CE82FF'),
  (key: 'personal', name: 'Personal', color: '#58CC02'),
];

/// `pillar-<key>-<userId>` — deterministic, so seeding on the server and on
/// two devices never duplicates.
String defaultPillarId(String key, String userId) => 'pillar-$key-$userId';

List<ContentPillar> defaultPillars(String userId, DateTime now) => [
  for (final (i, p) in defaultPillarSpecs.indexed)
    ContentPillar(
      id: defaultPillarId(p.key, userId),
      name: p.name,
      color: p.color,
      sortOrder: i,
      createdAt: now,
      updatedAt: now,
    ),
];

bool pillarNameTaken(
  List<ContentPillar> pillars,
  String name, {
  String? exceptId,
}) {
  final k = nameKey(name);
  return pillars.any((p) => p.id != exceptId && nameKey(p.name) == k);
}

int comparePillars(ContentPillar a, ContentPillar b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// sortOrder, then handle.
int compareAccounts(SocialAccount a, SocialAccount b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.handle.toLowerCase().compareTo(b.handle.toLowerCase());
}

// ---------------------------------------------------------------- stages

/// Stage after a post change (never backwards): all non-skipped posts posted
/// (and at least one) → `tayang`; else any post scheduled → at least
/// `terjadwal` (an item the user moved further keeps its stage).
ContentStage autoStage(ContentStage current, Iterable<ContentPost> posts) {
  final all = posts.toList();
  final live = all.where((p) => !p.isSkipped).toList();
  var target = current;
  if (live.isNotEmpty && live.every((p) => p.isPosted)) {
    target = ContentStage.tayang;
  } else if (all.any((p) => p.isScheduled)) {
    target = ContentStage.terjadwal;
  }
  return target.index > current.index ? target : current;
}

/// XP for moving an item forward from [from] to [to]: the sum of the `xp` of
/// every stage newly reached (ide→naskah +3 … →tayang +10). Backwards = 0.
int stageXp(ContentStage from, ContentStage to) {
  if (to.index <= from.index) return 0;
  return ContentStage.values
      .sublist(from.index + 1, to.index + 1)
      .fold(0, (a, s) => a + s.xp);
}

/// The device-only [ContentItem.sponsorPaidAt] for [next] (saved or pulled):
/// kept from [before] while the sponsor stays paid, [at] when it just became
/// paid, null while unpaid.
DateTime? recordSponsorPaid(
  ContentItem? before,
  ContentItem next,
  DateTime at,
) {
  if (next.sponsor?.paid != true) return null;
  if (before?.sponsor?.paid == true && before?.sponsorPaidAt != null) {
    return before!.sponsorPaidAt;
  }
  return next.sponsorPaidAt ?? at;
}

/// Records that the item reached [stage] at [at]: every stage up to [stage]
/// missing from [log] gets [at]; existing entries are kept (moving back and
/// forth never changes when a stage was first reached).
Map<ContentStage, DateTime> recordStage(
  Map<ContentStage, DateTime> log,
  ContentStage stage,
  DateTime at,
) {
  final out = Map.of(log);
  for (final s in ContentStage.values) {
    if (s.index > stage.index) break;
    out.putIfAbsent(s, () => at);
  }
  return out;
}

// ---------------------------------------------------------------- weeks

/// Monday 00:00 (local) of [d]'s ISO week.
DateTime weekStartOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Monday–Sunday around [day].
({DateTime from, DateTime to}) weekRange(DateTime day) {
  final s = weekStartOf(day);
  return (from: s, to: DateTime(s.year, s.month, s.day + 6));
}

/// The month grid: Monday on/before the 1st → Sunday on/after the last day.
({DateTime from, DateTime to}) monthGridRange(YearMonth m) {
  final s = weekStartOf(m.start);
  final e = weekStartOf(DateTime(m.year, m.month + 1, 0));
  return (from: s, to: DateTime(e.year, e.month, e.day + 6));
}

/// Mondays of the ISO weeks lying entirely inside [from]..[to] (server
/// `fullWeeksInRange`).
List<DateTime> fullWeeksIn(DateTime from, DateTime to) {
  final f = startOfDay(from), t = startOfDay(to);
  return [
    for (final w in weeksIn(f, t))
      if (!w.isBefore(f) && !DateTime(w.year, w.month, w.day + 6).isAfter(t)) w,
  ];
}

/// Local days in [from]..[to] (inclusive).
int daysIn(DateTime from, DateTime to) =>
    daysBetween(startOfDay(to), startOfDay(from)) + 1;

/// Mondays of every ISO week overlapping [from]..[to] (server `weeksInRange`).
List<DateTime> weeksIn(DateTime from, DateTime to) {
  final out = <DateTime>[];
  final end = startOfDay(to);
  for (
    var w = weekStartOf(from);
    !w.isAfter(end);
    w = DateTime(w.year, w.month, w.day + 7)
  ) {
    out.add(w);
  }
  return out;
}

bool _inWeek(DateTime? at, DateTime weekStart) {
  if (at == null) return false;
  final end = DateTime(weekStart.year, weekStart.month, weekStart.day + 7);
  return !at.isBefore(weekStart) && at.isBefore(end);
}

/// One account's slot in the week (server `weekSlots`): `count` = non-skipped
/// posts placed in the week (by [ContentPost.calendarAt]), `posted` = posts
/// posted in the week (by `postedAt`).
AccountWeekCount accountWeekCount(
  SocialAccount account,
  Iterable<ContentPost> posts,
  DateTime weekStart,
) {
  var count = 0, posted = 0;
  for (final p in posts) {
    if (p.accountId != account.id || p.isSkipped) continue;
    if (_inWeek(p.calendarAt, weekStart)) count++;
    if (p.isPosted && _inWeek(p.postedAt, weekStart)) posted++;
  }
  return AccountWeekCount(
    account: account,
    weekStart: weekStart,
    count: count,
    posted: posted,
  );
}

/// Posted count per week (Monday) for one account (server `postedPerWeek`).
Map<DateTime, int> postedPerWeek(
  Iterable<ContentPost> posts,
  String accountId,
) {
  final m = <DateTime, int>{};
  for (final p in posts) {
    if (p.accountId != accountId || !p.isPosted || p.postedAt == null) continue;
    final w = weekStartOf(p.postedAt!);
    m[w] = (m[w] ?? 0) + 1;
  }
  return m;
}

/// Consistency over [weeks] (ascending Mondays): weeks meeting [target], the
/// longest run of met weeks and the current run ending at the last week — a
/// last week equal to [currentWeek] that isn't met yet doesn't break the run
/// (server `consistency`).
({int weeksMet, int weeks, int longestStreak, int currentStreak}) consistency(
  Map<DateTime, int> counts,
  int? target,
  List<DateTime> weeks, {
  DateTime? currentWeek,
}) {
  if (target == null || target <= 0) {
    return (
      weeksMet: 0,
      weeks: weeks.length,
      longestStreak: 0,
      currentStreak: 0,
    );
  }
  final met = [for (final w in weeks) (counts[w] ?? 0) >= target];
  var longest = 0, run = 0;
  for (final m in met) {
    run = m ? run + 1 : 0;
    if (run > longest) longest = run;
  }
  var i = met.length - 1;
  if (i >= 0 && !met[i] && weeks[i] == currentWeek) i--;
  var current = 0;
  for (; i >= 0 && met[i]; i--) {
    current++;
  }
  return (
    weeksMet: met.where((x) => x).length,
    weeks: weeks.length,
    longestStreak: longest,
    currentStreak: current,
  );
}

/// Weeks where [account] met its target, each with `at` = the `postedAt` of the
/// post that reached the target (the target-th post of that week). For the
/// "weekly target met" XP/achievements.
List<({DateTime weekStart, DateTime at})> weeklyTargetsMet(
  SocialAccount account,
  Iterable<ContentPost> posts,
) {
  final target = account.targetPerWeek ?? 0;
  if (target <= 0) return const [];
  final byWeek = <DateTime, List<DateTime>>{};
  for (final p in posts) {
    if (p.accountId != account.id || !p.isPosted || p.postedAt == null) {
      continue;
    }
    byWeek.putIfAbsent(weekStartOf(p.postedAt!), () => []).add(p.postedAt!);
  }
  final out = <({DateTime weekStart, DateTime at})>[];
  for (final e in byWeek.entries) {
    if (e.value.length < target) continue;
    e.value.sort();
    out.add((weekStart: e.key, at: e.value[target - 1]));
  }
  return out..sort((a, b) => a.weekStart.compareTo(b.weekStart));
}

/// Posted at or before the scheduled local day ("posting on schedule").
bool postedOnSchedule(ContentPost p) {
  final s = p.scheduledAt, at = p.postedAt;
  if (!p.isPosted || s == null || at == null) return false;
  return dateKey(at).compareTo(dateKey(s)) <= 0;
}

// ---------------------------------------------------------------- metrics

/// Days after `postedAt` before the "Isi performa?" prompt.
const metricsPromptDays = 3;

/// engagement / views, or null without views.
double? engagementRate(PostMetrics m) =>
    (m.views ?? 0) > 0 ? m.engagement / m.views! : null;

/// "Isi performa?": posted ≥ 3 days ago and no metrics entered yet.
bool needsMetricsPrompt(ContentPost p, DateTime now) =>
    p.isPosted &&
    p.postedAt != null &&
    p.metricsAt == null &&
    p.metrics.isEmpty &&
    !p.postedAt!.add(const Duration(days: metricsPromptDays)).isAfter(now);

// ---------------------------------------------------------------- views

List<ContentPostView> _postViews(
  Iterable<ContentPost> posts,
  Map<String, SocialAccount> accounts,
  Map<String, ContentItem> items,
) => [
  for (final p in posts)
    ContentPostView(
      post: p,
      account: accounts[p.accountId],
      item: items[p.contentId],
    ),
];

int _byAccountOrder(ContentPostView a, ContentPostView b) {
  final x = a.account, y = b.account;
  if (x == null || y == null) {
    return (x == null ? 1 : 0) - (y == null ? 1 : 0);
  }
  final c = compareAccounts(x, y);
  return c != 0 ? c : a.post.createdAt.compareTo(b.post.createdAt);
}

/// Item views (posts sorted by account order) keyed by item id.
Map<String, ContentItemView> buildItemViews(
  List<ContentItem> items,
  List<ContentPost> posts,
  List<SocialAccount> accounts, {
  List<Note> notes = const [],
}) {
  final acc = {for (final a in accounts) a.id: a};
  final byItem = {for (final i in items) i.id: i};
  final postsBy = <String, List<ContentPost>>{};
  for (final p in posts) {
    postsBy.putIfAbsent(p.contentId, () => []).add(p);
  }
  final noteBy = {for (final n in notes) n.id: n};
  return {
    for (final i in items)
      i.id: ContentItemView(
        item: i,
        posts: _postViews(postsBy[i.id] ?? const [], acc, byItem)
          ..sort(_byAccountOrder),
        note: i.noteId == null ? null : noteBy[i.noteId],
      ),
  };
}

bool _matchesFilter(ContentItemView v, ContentFilter f) {
  if (f.accountId != null &&
      !v.posts.any((p) => p.post.accountId == f.accountId)) {
    return false;
  }
  if (f.pillar != null && nameKey(v.item.pillar ?? '') != nameKey(f.pillar!)) {
    return false;
  }
  if (f.format != null && v.item.format != f.format) return false;
  final q = f.search?.trim().toLowerCase() ?? '';
  if (q.isNotEmpty) {
    final hay = [
      v.item.title,
      v.item.idea,
      for (final p in v.posts) p.post.caption,
      for (final p in v.posts) p.post.hashtags,
    ].join('\n').toLowerCase();
    if (!hay.contains(q)) return false;
  }
  return true;
}

/// The pipeline board for [filter]: 6 columns, most recently updated first.
ContentBoard buildContentBoard(
  List<ContentItem> items,
  List<ContentPost> posts,
  List<SocialAccount> accounts,
  ContentFilter filter, {
  List<Note> notes = const [],
}) {
  final views =
      buildItemViews(
        items,
        posts,
        accounts,
        notes: notes,
      ).values.where((v) => _matchesFilter(v, filter)).toList()..sort((a, b) {
        final c = b.item.updatedAt.compareTo(a.item.updatedAt);
        return c != 0 ? c : a.item.id.compareTo(b.item.id);
      });
  return ContentBoard([
    for (final s in ContentStage.values)
      ContentColumn(s, [
        for (final v in views)
          if (v.item.stage == s) v,
      ]),
  ]);
}

int _byCalendarAt(ContentPostView a, ContentPostView b) {
  final c = a.post.calendarAt!.compareTo(b.post.calendarAt!);
  return c != 0 ? c : _byAccountOrder(a, b);
}

/// Calendar of [from]..[to] (local days, inclusive): non-skipped posts by
/// `calendarAt` (postedAt for posted posts, else scheduledAt), plus per-week
/// slots of the non-archived accounts vs their targets.
ContentCalendar buildContentCalendar(
  DateTime from,
  DateTime to,
  List<ContentPost> posts,
  List<ContentItem> items,
  List<SocialAccount> accounts,
) {
  final f = startOfDay(from), t = startOfDay(to);
  final end = DateTime(t.year, t.month, t.day + 1);
  final acc = {for (final a in accounts) a.id: a};
  final byItem = {for (final i in items) i.id: i};
  final days = <String, List<ContentPostView>>{};
  final inRange = posts.where((p) {
    final at = p.calendarAt;
    return !p.isSkipped && at != null && !at.isBefore(f) && at.isBefore(end);
  });
  for (final v in _postViews(inRange, acc, byItem)) {
    days.putIfAbsent(dateKey(v.post.calendarAt!), () => []).add(v);
  }
  for (final l in days.values) {
    l.sort(_byCalendarAt);
  }
  final live = accounts.where((a) => !a.archived).toList()
    ..sort(compareAccounts);
  return ContentCalendar(
    from: f,
    to: t,
    days: days,
    weeks: [
      for (final w in weeksIn(f, t))
        CalendarWeek(w, [for (final a in live) accountWeekCount(a, posts, w)]),
    ],
  );
}

/// "Tayang hari ini": non-skipped posts placed on [now]'s local day.
TodayPosts buildTodayPosts(
  DateTime now,
  List<ContentPost> posts,
  List<ContentItem> items,
  List<SocialAccount> accounts,
) {
  final key = dateKey(now);
  final acc = {for (final a in accounts) a.id: a};
  final byItem = {for (final i in items) i.id: i};
  final list = _postViews(
    posts.where(
      (p) =>
          !p.isSkipped && p.calendarAt != null && dateKey(p.calendarAt!) == key,
    ),
    acc,
    byItem,
  )..sort(_byCalendarAt);
  return TodayPosts(list);
}

/// Idea inbox: notes with the "Ide Konten" label (see `findIdeaLabel`), not
/// archived and not yet converted (`linkedContentId == null`), pinned first
/// then newest.
List<Note> ideaInbox(List<Note> notes, List<NoteLabel> labels) {
  final label = findIdeaLabel(labels);
  if (label == null) return const [];
  return notes
      .where(
        (n) => !n.archived && n.linkedContentId == null && n.hasLabel(label.id),
      )
      .toList()
    ..sort(compareNotes);
}

// ---------------------------------------------------------------- report

double? _avg(List<num> xs) =>
    xs.isEmpty ? null : xs.fold<num>(0, (a, b) => a + b) / xs.length;

List<ContentGroupStat> _groupStats(
  List<ContentPostView> posted,
  String Function(ContentPostView) keyOf,
  String Function(String key) labelOf,
) {
  final groups = <String, List<PostMetrics>>{};
  for (final p in posted) {
    groups.putIfAbsent(keyOf(p), () => []).add(p.post.metrics);
  }
  final total = posted.length;
  return [
    for (final e in groups.entries)
      ContentGroupStat(
        key: e.key,
        label: labelOf(e.key),
        posts: e.value.length,
        withMetrics: e.value.where((m) => m.views != null).length,
        avgViews: _avg([
          for (final m in e.value)
            if (m.views != null) m.views!,
        ]),
        avgEngagement: _avg([
          for (final m in e.value)
            if (!m.isEmpty) m.engagement,
        ]),
        avgRate: _avg([
          for (final m in e.value)
            if ((m.views ?? 0) > 0) engagementRate(m)!,
        ]),
        share: total == 0 ? 0 : e.value.length / total,
      ),
  ]..sort((a, b) {
    final c = b.posts.compareTo(a.posts);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
}

int _byNumKey(ContentGroupStat a, ContentGroupStat b) =>
    int.parse(a.key).compareTo(int.parse(b.key));

/// Paid income per month / account and the unpaid list, over all items
/// (server `sponsorSummary`). [txDates] = transaction id → date.
SponsorSummary sponsorSummary({
  required List<ContentItem> items,
  required List<ContentPost> posts,
  Map<String, DateTime> txDates = const {},
  required DateTime now,
}) {
  final today = dateKey(now);
  final byMonth = <String, ({double amount, int count})>{};
  final byAccount = <String, double>{};
  final unpaid = <SponsorDue>[];
  for (final item in items) {
    final s = item.sponsor;
    if (s == null) continue;
    if (!s.paid) {
      unpaid.add(
        SponsorDue(
          item: item,
          sponsor: s,
          overdue: s.due != null && s.due!.compareTo(today) < 0,
        ),
      );
      continue;
    }
    final tx = s.transactionId == null ? null : txDates[s.transactionId];
    final day = tx != null ? dateKey(tx) : (s.due ?? dateKey(item.createdAt));
    final month = day.substring(0, 7);
    final m = byMonth[month];
    byMonth[month] = (
      amount: (m?.amount ?? 0) + s.amount,
      count: (m?.count ?? 0) + 1,
    );
    final accs = {
      for (final p in posts)
        if (p.contentId == item.id) p.accountId,
    }.toList();
    final keys = accs.isEmpty ? [''] : accs;
    for (final a in keys) {
      byAccount[a] = (byAccount[a] ?? 0) + s.amount / keys.length;
    }
  }
  unpaid.sort((a, b) {
    final c = (a.sponsor.due ?? '9999').compareTo(b.sponsor.due ?? '9999');
    return c != 0 ? c : a.item.title.compareTo(b.item.title);
  });
  return SponsorSummary(
    byMonth: [
      for (final e in byMonth.entries)
        SponsorMonth(
          month: e.key,
          amount: e.value.amount,
          count: e.value.count,
        ),
    ]..sort((a, b) => a.month.compareTo(b.month)),
    byAccount: [
      for (final e in byAccount.entries)
        SponsorAccountIncome(accountId: e.key, amount: e.value),
    ]..sort((a, b) => b.amount.compareTo(a.amount)),
    unpaid: unpaid,
  );
}

/// The report for the local days [from]..[to] (inclusive) as of [now] (server
/// `buildContentReport`): posted posts by `postedAt`; expected posts prorated
/// (`round(target × days / 7)`, ≥ 1); consistency on the full ISO weeks inside
/// the range ([now]'s week is the in-progress one, which doesn't break a
/// streak); plus the sponsor summary. [top] = size of the best-post lists.
ContentReport buildContentReport({
  required DateTime from,
  required DateTime to,
  required DateTime now,
  required List<ContentItem> items,
  required List<ContentPost> posts,
  required List<SocialAccount> accounts,
  Map<String, DateTime> txDates = const {},
  int top = 5,
}) {
  final f = startOfDay(from), t = startOfDay(to);
  final end = DateTime(t.year, t.month, t.day + 1);
  bool inRange(DateTime? d) => d != null && !d.isBefore(f) && d.isBefore(end);
  final acc = {for (final a in accounts) a.id: a};
  final byItem = {for (final i in items) i.id: i};
  final postedPosts = posts.where((p) => p.isPosted && inRange(p.postedAt));
  final posted = _postViews(postedPosts, acc, byItem);
  final weeks = fullWeeksIn(f, t);
  final days = daysIn(f, t);
  final currentWeek = weekStartOf(now);

  final sorted = [...accounts]..sort(compareAccounts);
  final accountReports = [
    for (final a in sorted)
      () {
        final mine = postedPosts.where((p) => p.accountId == a.id).toList();
        final target = a.hasTarget ? a.targetPerWeek : null;
        final c = consistency(
          postedPerWeek(mine, a.id),
          target,
          weeks,
          currentWeek: currentWeek,
        );
        final expected = target == null ? null : (target * days / 7).round();
        return AccountReport(
          account: a,
          posted: mine.length,
          expected: expected == null ? null : (expected < 1 ? 1 : expected),
          weeks: c.weeks,
          weeksMet: c.weeksMet,
          longestStreak: c.longestStreak,
          currentStreak: c.currentStreak,
        );
      }(),
  ];

  final byViews = posted.where((p) => p.post.metrics.views != null).toList()
    ..sort((a, b) {
      final c = b.post.metrics.views!.compareTo(a.post.metrics.views!);
      return c != 0
          ? c
          : b.post.metrics.engagement.compareTo(a.post.metrics.engagement);
    });
  final byEng = posted.where((p) => p.post.metrics.engagement > 0).toList()
    ..sort((a, b) {
      final c = b.post.metrics.engagement.compareTo(a.post.metrics.engagement);
      return c != 0
          ? c
          : (b.post.metrics.views ?? 0).compareTo(a.post.metrics.views ?? 0);
    });

  return ContentReport(
    from: f,
    to: t,
    weeks: weeks,
    days: days,
    totals: ContentTotals(
      posted: posted.length,
      scheduled: posts
          .where((p) => p.isScheduled && inRange(p.scheduledAt))
          .length,
      skipped: posts.where((p) => p.isSkipped && inRange(p.scheduledAt)).length,
      views: posted.fold(0, (s, p) => s + (p.post.metrics.views ?? 0)),
      engagement: posted.fold(0, (s, p) => s + p.post.metrics.engagement),
    ),
    accounts: accountReports,
    bestByViews: byViews.take(top).toList(),
    bestByEngagement: byEng.take(top).toList(),
    byPillar: _groupStats(
      posted,
      (p) => p.item?.pillar ?? '',
      (k) => k.isEmpty ? 'Tanpa pilar' : k,
    ),
    byFormat: _groupStats(
      posted,
      (p) => p.item?.format?.wire ?? '',
      (k) => k.isEmpty ? 'Tanpa format' : ContentFormat.tryFromWire(k)!.label,
    ),
    byWeekday: _groupStats(
      posted,
      (p) => '${p.post.postedAt!.weekday}',
      (k) => isoWeekdayNames[int.parse(k) - 1],
    )..sort(_byNumKey),
    byHour: _groupStats(
      posted,
      (p) => '${p.post.postedAt!.hour}',
      (k) => '${k.padLeft(2, '0')}.00',
    )..sort(_byNumKey),
    sponsors: sponsorSummary(
      items: items,
      posts: posts,
      txDates: txDates,
      now: now,
    ),
  );
}

// ---------------------------------------------------------------- sponsorship

/// Note of the income transaction recorded for a paid sponsor.
String sponsorTransactionNote(String brand) => 'Endorse $brand';

// ---------------------------------------------------------------- reminders

/// App route of a post (notification tap target).
String contentPostRoute(String postId) => '/content/posts/$postId';

/// App route of a content item.
String contentItemRoute(String itemId) => '/content/$itemId';

/// Reminder key of a post (never clashes with task ids).
String contentReminderKey(String postId) => 'content-post-$postId';

/// `[IG-TAYANG] <title>` (server `postNotificationTitle`).
String postNotificationTitle(SocialAccount? account, String title) =>
    '[${account?.code ?? 'POST'}-TAYANG] $title';

/// Local notifications for scheduled posts with a reminder, at
/// `scheduledAt − remindBefore` (past ones skipped): title
/// `[IG-TAYANG] <item title>`, body `Hari ini 19.00 · @handle`. Soonest first,
/// capped at [max].
List<Reminder> computeContentReminders(
  List<ContentPost> posts,
  List<ContentItem> items,
  List<SocialAccount> accounts,
  DateTime now, {
  int max = 60,
}) {
  final acc = {for (final a in accounts) a.id: a};
  final byItem = {for (final i in items) i.id: i};
  final out = <Reminder>[];
  for (final p in posts) {
    final fireAt = p.remindAt;
    final at = p.scheduledAt;
    if (fireAt == null || at == null || fireAt.isBefore(now)) continue;
    final item = byItem[p.contentId];
    if (item == null) continue;
    final account = acc[p.accountId];
    out.add(
      Reminder(
        key: contentReminderKey(p.id),
        title: postNotificationTitle(account, item.title),
        body: [
          '${Fmt.relativeDay(at, now: fireAt)} ${Fmt.time(at)}',
          ?account?.atHandle,
        ].join(' · '),
        fireAt: fireAt,
        route: contentPostRoute(p.id),
      ),
    );
  }
  return sortAndCapReminders(out, max);
}

/// Soonest first (ties by key), at most [max].
List<Reminder> sortAndCapReminders(List<Reminder> reminders, int max) {
  final out = [...reminders]
    ..sort((a, b) {
      final c = a.fireAt.compareTo(b.fireAt);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return out.length > max ? out.sublist(0, max) : out;
}

// ---------------------------------------------------------------- validation

/// Throws a [ValidationFailure] unless [v] is `#rrggbb`.
String requireHex(String? v, {String field = 'color'}) {
  if (v == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) {
    throw ValidationFailure('Warna tidak valid', field: field);
  }
  return v;
}
