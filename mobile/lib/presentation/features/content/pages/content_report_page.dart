import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../content_format.dart';
import '../widgets/content_visuals.dart';
import '../widgets/report_charts.dart';

enum _Preset { week, days30, month, months3, custom }

enum _Metric { views, engagement, rate }

enum _Dim { pillar, format, weekday, hour }

/// Laporan konten: posts per account vs target, consistency streaks, best
/// posts, averages by pillar/format/weekday/hour, pillar balance, sponsors.
class ContentReportPage extends ConsumerStatefulWidget {
  const ContentReportPage({super.key});

  @override
  ConsumerState<ContentReportPage> createState() => _ContentReportPageState();
}

class _ContentReportPageState extends ConsumerState<ContentReportPage> {
  _Preset _preset = _Preset.days30;
  DateTime? _from;
  DateTime? _to;
  bool _bestByViews = true;
  _Metric _metric = _Metric.views;
  _Dim _dim = _Dim.pillar;

  ({DateTime from, DateTime to}) _range(DateTime now) {
    final today = startOfDay(now);
    return switch (_preset) {
      _Preset.week => weekRange(today),
      _Preset.days30 => (from: addDays(today, -29), to: today),
      _Preset.month => (
        from: DateTime(today.year, today.month, 1),
        to: DateTime(today.year, today.month + 1, 0),
      ),
      _Preset.months3 => (
        from: DateTime(today.year, today.month - 2, 1),
        to: today,
      ),
      _Preset.custom => (from: _from ?? addDays(today, -29), to: _to ?? today),
    };
  }

  Future<void> _custom() async {
    final now = ref.read(clockProvider).now();
    final r = _range(now);
    final from = await showGhinaDatePicker(
      context,
      initial: r.from,
      title: 'Dari tanggal',
      today: now,
    );
    if (from == null || !mounted) return;
    final to = await showGhinaDatePicker(
      context,
      initial: r.to.isBefore(from) ? from : r.to,
      title: 'Sampai tanggal',
      firstDate: from,
      today: now,
    );
    if (to == null || !mounted) return;
    setState(() {
      _preset = _Preset.custom;
      _from = startOfDay(from);
      _to = startOfDay(to);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.read(clockProvider).now();
    final range = _range(now);
    final async = ref.watch(watchContentReportProvider(range));
    final g = context.ghina;
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan konten')),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: GhinaSpace.page,
                ),
                children: [
                  for (final (p, label) in [
                    (_Preset.week, 'Minggu ini'),
                    (_Preset.days30, '30 hari'),
                    (_Preset.month, 'Bulan ini'),
                    (_Preset.months3, '3 bulan'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        child: ChunkyChip(
                          key: ValueKey('range-${p.name}'),
                          label: label,
                          selected: _preset == p,
                          onTap: () => setState(() => _preset = p),
                        ),
                      ),
                    ),
                  Center(
                    child: ChunkyChip(
                      key: const ValueKey('range-custom'),
                      label: 'Kustom',
                      icon: Icons.date_range_rounded,
                      selected: _preset == _Preset.custom,
                      onTap: _custom,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                4,
                GhinaSpace.page,
                8,
              ),
              child: Text(
                '${Fmt.date(range.from)} – ${Fmt.date(range.to)}',
                key: const ValueKey('report-range'),
                style: GhinaType.bodyS.w(700).copyWith(color: g.textSecondary),
              ),
            ),
            ...async.when(
              skipLoadingOnReload: true,
              loading: () => [
                const SizedBox(height: 400, child: LoadingListView()),
              ],
              error: (_, _) => [
                ErrorRetry(
                  onRetry: () =>
                      ref.invalidate(watchContentReportProvider(range)),
                ),
              ],
              data: (r) => r.hasData
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GhinaSpace.page,
                        ),
                        child: _body(r),
                      ),
                    ]
                  : [
                      EmptyState(
                        mood: MascotMood.thinking,
                        title: 'Belum ada data',
                        message:
                            'Belum ada posting yang tayang di rentang ini. Coba rentang lain atau tandai posting yang sudah tayang.',
                        actionLabel: 'Ke papan konten',
                        onAction: () => context.go('/content'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ContentReport r) {
    final currency = ref.watch(currencyProvider);
    final pillars = ref.watch(watchContentPillarsProvider).value ?? const [];
    final t = r.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.rocket_launch_rounded,
                value: '${t.posted}',
                label: 'Tayang',
                color: GhinaColors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: Icons.schedule_rounded,
                value: '${t.scheduled}',
                label: 'Terjadwal',
                color: GhinaColors.yellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.visibility_rounded,
                value: compactCount(t.views),
                label: 'Views',
                color: GhinaColors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: Icons.favorite_rounded,
                value: compactCount(t.engagement),
                label: 'Engagement',
                color: GhinaColors.pink,
              ),
            ),
          ],
        ),
        if (r.accounts.any((a) => a.posted > 0 || a.target != null)) ...[
          const SizedBox(height: 28),
          const SectionHeader(
            title: 'Per akun',
            subtitle: 'Tayang vs target (disesuaikan rentang)',
          ),
          for (final a in r.accounts)
            if (a.posted > 0 || (a.target != null && !a.account.archived))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AccountCard(report: a),
              ),
        ],
        if (r.bestByViews.isNotEmpty || r.bestByEngagement.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionHeader(
            title: 'Posting terbaik',
            trailing: SizedBox(
              width: 180,
              child: ChunkySegmented<bool>(
                height: 30,
                value: _bestByViews,
                onChanged: (v) => setState(() => _bestByViews = v),
                segments: const [
                  ChunkySegment(value: true, label: 'Views'),
                  ChunkySegment(value: false, label: 'Engage'),
                ],
              ),
            ),
          ),
          _BestList(
            posts: _bestByViews ? r.bestByViews : r.bestByEngagement,
            byViews: _bestByViews,
          ),
        ],
        if (t.posted > 0) ...[
          const SizedBox(height: 28),
          const SectionHeader(title: 'Rata-rata'),
          _averages(r, pillars),
          if (r.byPillar.isNotEmpty) ...[
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Keseimbangan pilar',
              subtitle: 'Porsi posting yang tayang',
            ),
            ChunkyCard(
              key: const ValueKey('pillar-balance'),
              padding: const EdgeInsets.all(16),
              child: ShareBar(
                parts: [
                  for (final p in r.byPillar)
                    (
                      label: p.label,
                      share: p.share,
                      count: p.posts,
                      color: p.key.isEmpty
                          ? context.ghina.textMuted
                          : pillarColor(context, p.key, pillars),
                    ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 28),
        _sponsors(r, currency),
      ],
    );
  }

  Widget _averages(ContentReport r, List<ContentPillar> pillars) {
    final groups = switch (_dim) {
      _Dim.pillar => r.byPillar,
      _Dim.format => r.byFormat,
      _Dim.weekday => r.byWeekday,
      _Dim.hour => r.byHour,
    };
    double v(ContentGroupStat s) => switch (_metric) {
      _Metric.views => s.avgViews ?? 0,
      _Metric.engagement => s.avgEngagement ?? 0,
      _Metric.rate => (s.avgRate ?? 0) * 100,
    };
    String show(ContentGroupStat s) => switch (_metric) {
      _Metric.views => s.avgViews == null ? '–' : compactCount(s.avgViews!),
      _Metric.engagement =>
        s.avgEngagement == null ? '–' : compactCount(s.avgEngagement!),
      _Metric.rate => percentLabel(s.avgRate),
    };
    final hasMetrics = groups.any((s) => s.withMetrics > 0);
    final swatch = switch (_metric) {
      _Metric.views => GhinaColors.blue,
      _Metric.engagement => GhinaColors.pink,
      _Metric.rate => GhinaColors.purple,
    };
    final g = context.ghina;
    return ChunkyCard(
      key: const ValueKey('averages'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (d, label) in [
                (_Dim.pillar, 'Pilar'),
                (_Dim.format, 'Format'),
                (_Dim.weekday, 'Hari'),
                (_Dim.hour, 'Jam'),
              ])
                ChunkyChip(
                  key: ValueKey('dim-${d.name}'),
                  label: label,
                  selected: _dim == d,
                  color: GhinaColors.purple,
                  onTap: () => setState(() => _dim = d),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ChunkySegmented<_Metric>(
            height: 32,
            value: _metric,
            onChanged: (m) => setState(() => _metric = m),
            segments: [
              ChunkySegment(
                value: _Metric.views,
                label: 'Views',
                color: GhinaColors.blue,
              ),
              ChunkySegment(
                value: _Metric.engagement,
                label: 'Engage',
                color: GhinaColors.pink,
              ),
              ChunkySegment(
                value: _Metric.rate,
                label: 'Rate',
                color: GhinaColors.purple,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasMetrics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Isi performa posting (views, likes…) untuk melihat rata-ratanya 📊',
                textAlign: TextAlign.center,
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            )
          else if (_dim == _Dim.weekday || _dim == _Dim.hour)
            SimpleBarChart(
              key: ValueKey('avg-chart-${_dim.name}'),
              color: swatch,
              formatAxis: (x) =>
                  _metric == _Metric.rate ? '${x.round()}%' : compactCount(x),
              data: [
                for (final s in groups)
                  (
                    label: _dim == _Dim.hour
                        ? s.key.padLeft(2, '0')
                        : s.label.substring(0, s.label.length.clamp(0, 3)),
                    value: v(s),
                    tooltip: '${s.label}: ${show(s)} · ${s.posts} posting',
                  ),
              ],
            )
          else
            HBarList(
              color: swatch,
              rows: [
                for (final s in groups)
                  (
                    label: s.label,
                    value: v(s),
                    display: show(s),
                    dot: _dim == _Dim.pillar && s.key.isNotEmpty
                        ? pillarColor(context, s.key, pillars)
                        : null,
                  ),
              ],
            ),
          if (hasMetrics) ...[
            const SizedBox(height: 6),
            Text(
              'Rata-rata dari posting yang sudah diisi performanya.',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sponsors(ContentReport r, String currency) {
    final s = r.sponsors;
    final g = context.ghina;
    if (s.byMonth.isEmpty && s.unpaid.isEmpty) return const SizedBox.shrink();
    final names = {for (final a in r.accounts) a.account.id: a.account};
    final months = s.byMonth.length > 12
        ? s.byMonth.sublist(s.byMonth.length - 12)
        : s.byMonth;
    final today = startOfDay(ref.read(clockProvider).now());
    return Column(
      key: const ValueKey('report-sponsors'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Sponsor', subtitle: 'Semua waktu'),
        if (s.byMonth.isNotEmpty)
          ChunkyCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total sudah dibayar',
                  style: GhinaType.bodyS
                      .w(700)
                      .copyWith(color: g.textSecondary),
                ),
                MoneyText(
                  amount: s.paidTotal,
                  currency: currency,
                  tone: MoneyTone.income,
                  style: GhinaType.moneyL,
                ),
                const SizedBox(height: 14),
                SimpleBarChart(
                  key: const ValueKey('sponsor-months'),
                  height: 160,
                  color: GhinaColors.green,
                  formatAxis: (v) => GhinaMoney.format(
                    v,
                    currency: currency,
                    compact: true,
                  ).replaceFirst('Rp ', ''),
                  data: [
                    for (final m in months)
                      (
                        label: Fmt.monthShort(int.parse(m.month.substring(5))),
                        value: m.amount,
                        tooltip:
                            '${Fmt.monthShort(int.parse(m.month.substring(5)))} ${m.month.substring(0, 4)}: '
                            '${GhinaMoney.format(m.amount, currency: currency)}',
                      ),
                  ],
                ),
                if (s.byAccount.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final a in s.byAccount)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          if (names[a.accountId] != null)
                            AccountAvatar(
                              account: names[a.accountId]!,
                              size: 26,
                            )
                          else
                            Icon(Icons.inventory_2_rounded, color: g.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              names[a.accountId]?.atHandle ?? 'Tanpa akun',
                              style: GhinaType.body
                                  .w(700)
                                  .copyWith(color: g.textPrimary),
                            ),
                          ),
                          MoneyText(
                            amount: a.amount,
                            currency: currency,
                            tone: MoneyTone.neutral,
                            style: GhinaType.moneyS,
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        if (s.unpaid.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Belum dibayar',
            style: GhinaType.h3.copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 8),
          for (final d in s.unpaid)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChunkyTile(
                key: ValueKey('unpaid-${d.item.id}'),
                leading: Icon(
                  Icons.handshake_rounded,
                  color: d.overdue
                      ? GhinaColors.red.base
                      : GhinaColors.orange.base,
                ),
                title: d.sponsor.brand,
                subtitle: [
                  d.item.title,
                  if (d.sponsor.due != null)
                    'jatuh tempo ${contentDayLabel(parseDateKey(d.sponsor.due!), today)}',
                ].join(' · '),
                trailing: d.overdue
                    ? const ChunkyPill(label: 'Telat', color: GhinaColors.red)
                    : Text(
                        d.sponsor.amount == 0
                            ? 'Barter'
                            : GhinaMoney.format(
                                d.sponsor.amount,
                                currency: d.sponsor.currency,
                                compact: true,
                              ),
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                onTap: () => context.push(contentItemRoute(d.item.id)),
              ),
            ),
        ],
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.report});
  final AccountReport report;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = report.account;
    final expected = report.expected;
    final ratio = report.ratio;
    return ChunkyCard(
      key: ValueKey('report-account-${a.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AccountAvatar(account: a, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.atHandle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              Text(
                expected == null
                    ? '${report.posted} tayang'
                    : '${report.posted}/$expected',
                key: ValueKey('report-account-count-${a.id}'),
                style: GhinaType.h3.copyWith(color: g.textPrimary),
              ),
            ],
          ),
          if (expected != null) ...[
            const SizedBox(height: 10),
            ChunkyProgressBar(
              value: (ratio ?? 0).clamp(0.0, 1.0),
              color: (ratio ?? 0) >= 1
                  ? GhinaColors.green
                  : readableSwatch(context, a.color),
              height: 12,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _Fact(
                  icon: Icons.event_available_rounded,
                  text: report.weeks == 0
                      ? 'Belum ada minggu penuh'
                      : 'Target tercapai ${report.weeksMet}/${report.weeks} minggu',
                ),
                if (report.currentStreak > 0)
                  _Fact(
                    icon: Icons.local_fire_department_rounded,
                    color: GhinaColors.orange.base,
                    text: 'Streak ${report.currentStreak} minggu',
                  ),
                if (report.longestStreak > 0 &&
                    report.longestStreak != report.currentStreak)
                  _Fact(
                    icon: Icons.emoji_events_rounded,
                    text: 'Terpanjang ${report.longestStreak}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? g.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: GhinaType.bodyS.w(700).copyWith(color: g.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _BestList extends StatelessWidget {
  const _BestList({required this.posts, required this.byViews});
  final List<ContentPostView> posts;
  final bool byViews;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (posts.isEmpty) {
      return Text(
        'Belum ada performa yang diisi.',
        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
      );
    }
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        children: [
          for (var i = 0; i < posts.length; i++)
            InkWell(
              key: ValueKey('best-${posts[i].id}'),
              borderRadius: GhinaRadii.rMd,
              onTap: () => context.push(contentPostRoute(posts[i].id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: GhinaType.h3.copyWith(
                          color: i == 0 ? GhinaColors.yellow.edge : g.textMuted,
                        ),
                      ),
                    ),
                    if (posts[i].account != null) ...[
                      AccountAvatar(account: posts[i].account!, size: 28),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        posts[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(700)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      byViews
                          ? '${compactCount(posts[i].post.metrics.views ?? 0)} views'
                          : '${compactCount(posts[i].post.metrics.engagement)} eng.',
                      style: GhinaType.bodyS
                          .w(800)
                          .copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
