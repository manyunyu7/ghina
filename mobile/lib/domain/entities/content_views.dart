/// Read models of the content screens (`docs/content.md`). Built by the pure
/// functions in `domain/usecases/content_rules.dart`.
library;

import 'content.dart';
import 'note.dart';
import 'value_equality.dart';

/// A post joined with its account and item.
final class ContentPostView with ValueEquality {
  const ContentPostView({
    required this.post,
    required this.account,
    required this.item,
  });

  final ContentPost post;

  /// Null only when the row is missing (mid-sync).
  final SocialAccount? account;
  final ContentItem? item;

  String get id => post.id;

  /// Item title (or '').
  String get title => item?.title ?? '';

  /// `IG`, `TT`, … (`POST` when the account is missing).
  String get code => account?.code ?? 'POST';

  /// Account color, else the platform default.
  String get color => account?.color ?? SocialPlatform.other.color;

  /// `[IG-TAYANG] <title>` — the reminder/notification title.
  String get notificationTitle => '[$code-TAYANG] $title';

  @override
  List<Object?> get props => [post, account, item];

  @override
  String toString() => 'ContentPostView(${post.id}, $code, $title)';
}

/// An item with its posts (per account) and its source note.
final class ContentItemView with ValueEquality {
  const ContentItemView({required this.item, required this.posts, this.note});

  final ContentItem item;

  /// Sorted by account order.
  final List<ContentPostView> posts;
  final Note? note;

  String get id => item.id;
  String get title => item.title;
  ContentStage get stage => item.stage;

  /// Accounts with a post of this item (skipped ones included).
  List<SocialAccount> get accounts => [for (final p in posts) ?p.account];

  /// Earliest upcoming `scheduledAt` of a scheduled post, or null.
  DateTime? get nextScheduledAt {
    DateTime? best;
    for (final p in posts) {
      final at = p.post.scheduledAt;
      if (p.post.isScheduled &&
          at != null &&
          (best == null || at.isBefore(best))) {
        best = at;
      }
    }
    return best;
  }

  int get postedCount => posts.where((p) => p.post.isPosted).length;

  @override
  List<Object?> get props => [item, posts, note];

  @override
  String toString() => 'ContentItemView(${item.id}, ${item.title})';
}

/// Board filters (value-equal: safe as a family key). All null = everything.
final class ContentFilter with ValueEquality {
  const ContentFilter({this.accountId, this.pillar, this.format, this.search});

  static const all = ContentFilter();

  /// Items with a post on this account.
  final String? accountId;

  /// Pillar name (case-insensitive).
  final String? pillar;
  final ContentFormat? format;

  /// Title / idea / caption substring (case-insensitive).
  final String? search;

  bool get isEmpty =>
      accountId == null &&
      pillar == null &&
      format == null &&
      (search ?? '').trim().isEmpty;

  @override
  List<Object?> get props => [accountId, pillar, format, search];
}

/// One pipeline column.
final class ContentColumn with ValueEquality {
  const ContentColumn(this.stage, this.items);
  final ContentStage stage;

  /// Newest-updated first.
  final List<ContentItemView> items;

  @override
  List<Object?> get props => [stage, items];
}

/// The pipeline board: always 6 columns in stage order.
final class ContentBoard with ValueEquality {
  const ContentBoard(this.columns);
  final List<ContentColumn> columns;

  ContentColumn column(ContentStage s) => columns[s.index];
  int get total => columns.fold(0, (a, c) => a + c.items.length);
  bool get isEmpty => total == 0;

  @override
  List<Object?> get props => [columns];
}

/// Posts of one account in one ISO week vs its target ("IG: 1/3 minggu ini").
final class AccountWeekCount with ValueEquality {
  const AccountWeekCount({
    required this.account,
    required this.weekStart,
    required this.count,
    required this.posted,
  });

  final SocialAccount account;

  /// Monday 00:00 (local).
  final DateTime weekStart;

  /// Non-skipped posts placed in the week (scheduled + posted + dated drafts).
  final int count;

  /// Posts actually posted in the week (by `postedAt`).
  final int posted;
  int? get target => account.targetPerWeek;
  bool get met => target != null && target! > 0 && posted >= target!;

  /// Target minus planned posts (never negative); 0 without a target.
  int get emptySlots =>
      target == null ? 0 : (target! - count).clamp(0, target!);

  /// `IG: 1/3` (planned/target), or `IG: 2` without a target.
  String get label => target == null
      ? '${account.code}: $count'
      : '${account.code}: $count/$target';

  @override
  List<Object?> get props => [account, weekStart, count, posted];
}

/// Calendar data for a range (week or month grid).
final class ContentCalendar with ValueEquality {
  const ContentCalendar({
    required this.from,
    required this.to,
    required this.days,
    required this.weeks,
  });

  /// First and last local day of the range (midnight).
  final DateTime from;
  final DateTime to;

  /// `YYYY-MM-DD` → posts that day (by [ContentPost.calendarAt]), in time order.
  /// Skipped posts are left out. Only days with posts are present.
  final Map<String, List<ContentPostView>> days;

  /// Every ISO week touching the range → per-account counts (non-archived
  /// accounts, account order).
  final List<CalendarWeek> weeks;

  List<ContentPostView> on(String dateKey) => days[dateKey] ?? const [];

  @override
  List<Object?> get props => [from, to, days, weeks];
}

final class CalendarWeek with ValueEquality {
  const CalendarWeek(this.weekStart, this.accounts);

  /// Monday (local midnight).
  final DateTime weekStart;
  final List<AccountWeekCount> accounts;

  @override
  List<Object?> get props => [weekStart, accounts];
}

/// Home card "Tayang hari ini": today's non-skipped posts in time order.
final class TodayPosts with ValueEquality {
  const TodayPosts(this.posts);
  final List<ContentPostView> posts;

  bool get isEmpty => posts.isEmpty;

  /// Still to post today.
  int get pending => posts.where((p) => !p.post.isPosted).length;

  @override
  List<Object?> get props => [posts];
}

/// Consistency of one account in the report (server `consistency`).
final class AccountReport with ValueEquality {
  const AccountReport({
    required this.account,
    required this.posted,
    required this.expected,
    required this.weeks,
    required this.weeksMet,
    required this.longestStreak,
    required this.currentStreak,
  });

  final SocialAccount account;

  /// Posts posted in the range (by `postedAt`).
  final int posted;

  /// `max(1, round(target × days / 7))` — prorated to the range length; null
  /// without a target.
  final int? expected;

  /// Full ISO weeks inside the range (the weeks consistency is judged on).
  final int weeks;

  /// Weeks in the range where posted ≥ target (0 without a target).
  final int weeksMet;

  /// Longest run of consecutive met weeks in the range.
  final int longestStreak;

  /// Run of met weeks ending at the range's last week — an in-progress current
  /// week that isn't met yet doesn't break it.
  final int currentStreak;

  /// Target per week (null = none).
  int? get target => account.hasTarget ? account.targetPerWeek : null;

  /// posted / expected, 0–1+ (null without a target).
  double? get ratio =>
      expected == null || expected == 0 ? null : posted / expected!;

  @override
  List<Object?> get props => [
    account,
    posted,
    expected,
    weeks,
    weeksMet,
    longestStreak,
    currentStreak,
  ];
}

/// Posted posts grouped by pillar / format / weekday / hour (server `GroupStat`).
final class ContentGroupStat with ValueEquality {
  const ContentGroupStat({
    required this.key,
    required this.label,
    required this.posts,
    required this.withMetrics,
    required this.avgViews,
    required this.avgEngagement,
    required this.avgRate,
    required this.share,
  });

  /// Pillar name / format id / ISO weekday `1`..`7` / hour `0`..`23`; '' = none.
  final String key;

  /// Indonesian display label (`Tanpa pilar`, `Reel`, `Senin`, `19.00`).
  final String label;

  /// Posted posts in the group.
  final int posts;

  /// Posts with `views` entered (the view/rate averages are over these).
  final int withMetrics;
  final double? avgViews;

  /// Over posts with any metric.
  final double? avgEngagement;

  /// Average engagement / views (posts with views > 0).
  final double? avgRate;

  /// posts / all posted posts in the range (pillar balance chart).
  final double share;

  @override
  List<Object?> get props => [
    key,
    label,
    posts,
    withMetrics,
    avgViews,
    avgEngagement,
    avgRate,
    share,
  ];
}

/// Range totals (server `report.totals`).
final class ContentTotals with ValueEquality {
  const ContentTotals({
    required this.posted,
    required this.scheduled,
    required this.skipped,
    required this.views,
    required this.engagement,
  });

  /// Posted in the range (by `postedAt`).
  final int posted;

  /// Still `scheduled` with `scheduledAt` in the range.
  final int scheduled;

  /// `skipped` with `scheduledAt` in the range.
  final int skipped;
  final int views;
  final int engagement;

  @override
  List<Object?> get props => [posted, scheduled, skipped, views, engagement];
}

/// Paid sponsor income of one month (`YYYY-MM`).
final class SponsorMonth with ValueEquality {
  const SponsorMonth({
    required this.month,
    required this.amount,
    required this.count,
  });

  /// `YYYY-MM`
  final String month;
  final double amount;
  final int count;

  @override
  List<Object?> get props => [month, amount, count];
}

/// Paid sponsor income of one account (split equally across an item's accounts).
final class SponsorAccountIncome with ValueEquality {
  const SponsorAccountIncome({required this.accountId, required this.amount});

  /// '' = an item without posts.
  final String accountId;
  final double amount;

  @override
  List<Object?> get props => [accountId, amount];
}

/// An unpaid sponsorship.
final class SponsorDue with ValueEquality {
  const SponsorDue({
    required this.item,
    required this.sponsor,
    required this.overdue,
  });
  final ContentItem item;
  final Sponsor sponsor;

  /// Past its `due` day.
  final bool overdue;

  @override
  List<Object?> get props => [item, sponsor, overdue];
}

/// Sponsorship summary over all items (server `sponsorSummary`).
final class SponsorSummary with ValueEquality {
  const SponsorSummary({
    required this.byMonth,
    required this.byAccount,
    required this.unpaid,
  });

  /// Paid income per month (by the linked transaction's date, else `due`, else
  /// the item's creation), oldest first.
  final List<SponsorMonth> byMonth;

  /// Paid income per account, biggest first.
  final List<SponsorAccountIncome> byAccount;

  /// Unpaid sponsors, soonest due first (no due date last), then title.
  final List<SponsorDue> unpaid;

  double get paidTotal => byMonth.fold(0, (a, m) => a + m.amount);

  @override
  List<Object?> get props => [byMonth, byAccount, unpaid];
}

/// Content report for a local date range (`docs/content.md` → Reports; server
/// `buildContentReport` + `sponsorSummary`).
final class ContentReport with ValueEquality {
  const ContentReport({
    required this.from,
    required this.to,
    required this.weeks,
    required this.days,
    required this.totals,
    required this.accounts,
    required this.bestByViews,
    required this.bestByEngagement,
    required this.byPillar,
    required this.byFormat,
    required this.byWeekday,
    required this.byHour,
    required this.sponsors,
  });

  /// First and last local day (midnight).
  final DateTime from;
  final DateTime to;

  /// Mondays of the full ISO weeks inside the range.
  final List<DateTime> weeks;

  /// Days in the range.
  final int days;
  final ContentTotals totals;

  /// Every account (archived ones too — they may have posted in the range).
  final List<AccountReport> accounts;

  /// Top 5 posted posts by views (ties: engagement) / by engagement (> 0).
  final List<ContentPostView> bestByViews;
  final List<ContentPostView> bestByEngagement;

  /// Also the pillar balance (`posts`/`share`), biggest first.
  final List<ContentGroupStat> byPillar;
  final List<ContentGroupStat> byFormat;

  /// ISO weekday of `postedAt`, Monday first (only weekdays with posts).
  final List<ContentGroupStat> byWeekday;

  /// Hour of `postedAt` (only hours with posts).
  final List<ContentGroupStat> byHour;

  /// Not range-bound (like the web).
  final SponsorSummary sponsors;

  bool get hasData =>
      totals.posted > 0 ||
      totals.scheduled > 0 ||
      sponsors.byMonth.isNotEmpty ||
      sponsors.unpaid.isNotEmpty;

  @override
  List<Object?> get props => [
    from,
    to,
    weeks,
    days,
    totals,
    accounts,
    bestByViews,
    bestByEngagement,
    byPillar,
    byFormat,
    byWeekday,
    byHour,
    sponsors,
  ];
}
