import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' hide MascotMood;
import '../../../../domain/game/game.dart' as game show MascotMood;
import '../../../design_system/design_system.dart';
import '../../../shared/game_visuals.dart';
import '../../shell/sync_indicator.dart';

// ---------------------------------------------------------------- top stats bar

/// Level · streak · XP · hearts · sync badge, pinned above the scroll view.
class HomeStatsBar extends StatelessWidget {
  const HomeStatsBar({super.key, required this.summary});

  final GameSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final g = context.ghina;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page - 4,
        8,
        GhinaSpace.page - 4,
        10,
      ),
      decoration: BoxDecoration(
        color: g.background,
        border: Border(bottom: BorderSide(color: g.border, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s == null) ...[
                      const Skeleton(width: 34, height: 34, radius: 10),
                      const SizedBox(width: 14),
                      const Skeleton(width: 48, height: 24),
                      const SizedBox(width: 14),
                      const Skeleton(width: 60, height: 24),
                    ] else ...[
                      Tooltip(
                        message: 'Level ${s.level.level} · ${s.level.title}',
                        child: GestureDetector(
                          onTap: () => context.go('/profile'),
                          child: LevelBadge(level: s.level.level, size: 34),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Semantics(
                        label: 'Streak ${s.streak.current} hari',
                        child: GestureDetector(
                          onTap: () => context.go('/profile'),
                          child: StreakFlame(
                            count: s.streak.current,
                            active: s.streak.loggedToday,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      StatPill(
                        icon: Icons.bolt_rounded,
                        value: Fmt.number(s.totalXp),
                        color: GhinaColors.yellow,
                        size: 22,
                        semanticLabel: '${s.totalXp} XP',
                        onTap: () => context.push('/achievements'),
                      ),
                      const SizedBox(width: 12),
                      StatPill(
                        icon: Icons.favorite_rounded,
                        value: '${s.hearts.current}',
                        color: s.hearts.current == 0
                            ? GhinaColors.gray
                            : GhinaColors.red,
                        size: 22,
                        semanticLabel: '${s.hearts.current} hati',
                        onTap: () => context.push('/budgets'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const LiveSyncBadge(compact: true),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- daily goal

class DailyGoalCard extends StatelessWidget {
  const DailyGoalCard({super.key, required this.summary});

  final GameSummary summary;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final goal = summary.goal;
    final met = goal.isMet;
    return ChunkyCard(
      tinted: met ? GhinaColors.green : null,
      onTap: () => context.push('/settings'),
      semanticLabel: 'Target harian ${goal.done} dari ${goal.target}',
      child: Row(
        children: [
          ProgressRing(
            value: goal.fraction,
            size: 76,
            stroke: 10,
            color: met ? GhinaColors.green : GhinaColors.yellow,
            child: met
                ? Icon(
                    Icons.check_rounded,
                    size: 34,
                    color: GhinaColors.green.base,
                  )
                : Text(
                    '${goal.done}/${goal.target}',
                    style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TARGET HARIAN',
                  style: GhinaType.overline.copyWith(color: g.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  met
                      ? 'Target tercapai! 🎉'
                      : 'Tinggal ${goal.remaining} aktivitas lagi',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChunkyPill(
                      label: goal.level.label,
                      color: GhinaColors.blue,
                      soft: true,
                      uppercase: false,
                    ),
                    ChunkyPill(
                      label: '+${summary.xpToday} XP hari ini',
                      color: GhinaColors.yellow,
                      soft: true,
                      icon: Icons.bolt_rounded,
                      uppercase: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- balance

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.dash, required this.currency});

  final DashboardSummary dash;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final white70 = Colors.white.withValues(alpha: 0.82);
    final n = dash.wallets.length;
    return ChunkyCard(
      color: GhinaColors.blue,
      onTap: () => context.push('/wallets'),
      semanticLabel: 'Total saldo, buka dompet',
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL SALDO',
                  style: GhinaType.overline.copyWith(color: white70),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    amount: dash.totalBalance,
                    currency: currency,
                    tone: MoneyTone.neutral,
                    color: Colors.white,
                    countUp: true,
                    style: GhinaType.moneyL.copyWith(fontSize: 34),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  n == 0 ? 'Belum ada dompet · tambah yuk' : 'di $n dompet',
                  style: GhinaType.bodyS.w(700).copyWith(color: white70),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white,
            size: 30,
          ),
        ],
      ),
    );
  }
}

/// This month's income / expense / net, plus today's spending.
class MonthFlowCard extends StatelessWidget {
  const MonthFlowCard({super.key, required this.dash, required this.currency});

  final DashboardSummary dash;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget col(
      String label,
      IconData icon,
      ChunkySwatch color,
      num amount,
      MoneyTone tone,
    ) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color.base),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              amount: amount,
              currency: currency,
              tone: tone,
              compact: true,
              style: GhinaType.moneyM,
            ),
          ),
        ],
      ),
    );

    final budgetLine = dash.monthBudgeted > 0
        ? ' · anggaran ${GhinaMoney.format(dash.monthBudgeted, currency: currency, compact: true)}'
        : '';
    return ChunkyCard(
      onTap: () => context.push('/reports'),
      semanticLabel: 'Arus kas bulan ini',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Fmt.monthYear(dash.month.start).toUpperCase(),
            style: GhinaType.overline.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              col(
                'Pemasukan',
                Icons.south_west_rounded,
                GhinaColors.green,
                dash.monthIncome,
                MoneyTone.income,
              ),
              const SizedBox(width: 10),
              col(
                'Pengeluaran',
                Icons.north_east_rounded,
                GhinaColors.red,
                dash.monthExpense,
                MoneyTone.expense,
              ),
              const SizedBox(width: 10),
              col(
                'Selisih',
                Icons.balance_rounded,
                GhinaColors.blue,
                dash.monthNet,
                MoneyTone.auto,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: g.surfaceAlt,
              borderRadius: GhinaRadii.rMd,
            ),
            child: Text(
              'Hari ini keluar ${GhinaMoney.format(dash.todayExpense, currency: currency)}$budgetLine',
              style: GhinaType.bodyS.w(700).copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- learn

class ContinueLearningCard extends StatelessWidget {
  const ContinueLearningCard({super.key, required this.path});

  final LearnPathProgress path;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final next = path.nextLesson;
    if (next == null) {
      return ChunkyCard(
        tinted: GhinaColors.purple,
        onTap: () => context.push('/learn'),
        child: Row(
          children: [
            CategoryAvatar(
              icon: Icons.school_rounded,
              color: GhinaColors.purple.base,
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Semua pelajaran beres! Ulangi kapan aja buat bintang penuh 🎓',
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
            ),
          ],
        ),
      );
    }
    UnitProgress? unit;
    for (final u in path.units) {
      if (u.unit.id == next.unitId) unit = u;
    }
    return ChunkyCard(
      tinted: GhinaColors.purple,
      onTap: () => context.push('/learn/lesson/${next.lesson.id}'),
      semanticLabel: 'Lanjut belajar: ${next.lesson.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(
                icon: Icons.school_rounded,
                color: GhinaColors.purple.base,
                size: 48,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      path.completedLessons == 0
                          ? 'MULAI BELAJAR'
                          : 'LANJUT BELAJAR',
                      style: GhinaType.overline.copyWith(
                        color: GhinaColors.purple.base,
                      ),
                    ),
                    Text(
                      next.lesson.title,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    if (unit != null)
                      Text(
                        '${unit.unit.title} · ${unit.completedLessons}/${unit.totalLessons} pelajaran',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: path.completedLessons == 0 ? 'Mulai' : 'Lanjut',
            color: GhinaColors.purple,
            size: ChunkyButtonSize.medium,
            expand: true,
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: () => context.push('/learn/lesson/${next.lesson.id}'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- quick actions

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.color, this.path);
  final String label;
  final IconData icon;
  final ChunkySwatch color;
  final String path;
}

const _actions = [
  // Belajar left the tab bar (Tugas took its place): keep it one tap away.
  _QuickAction('Belajar', Icons.school_rounded, GhinaColors.purple, '/learn'),
  _QuickAction(
    'Dompet',
    Icons.account_balance_wallet_rounded,
    GhinaColors.blue,
    '/wallets',
  ),
  _QuickAction(
    'Anggaran',
    Icons.pie_chart_rounded,
    GhinaColors.green,
    '/budgets',
  ),
  _QuickAction(
    'Langganan',
    Icons.autorenew_rounded,
    GhinaColors.pink,
    '/subscriptions',
  ),
  _QuickAction(
    'Proyeksi',
    Icons.insights_rounded,
    GhinaColors.orange,
    '/forecast',
  ),
  _QuickAction(
    'Laporan',
    Icons.bar_chart_rounded,
    GhinaColors.blue,
    '/reports',
  ),
  _QuickAction('Sholat', Icons.mosque_rounded, GhinaColors.lime, '/prayers'),
  _QuickAction(
    'Kesehatan',
    Icons.monitor_heart_rounded,
    GhinaColors.red,
    '/health',
  ),
  _QuickAction(
    'Makanan',
    Icons.restaurant_rounded,
    GhinaColors.yellow,
    '/food',
  ),
];

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, c) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _actions.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: c.maxWidth > 520 ? 5 : 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 78 + 18 * scale,
        ),
        itemBuilder: (context, i) {
          final a = _actions[i];
          return ChunkyCard(
            key: ValueKey('qa-${a.path}'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            borderRadius: GhinaRadii.rLg,
            onTap: () => context.push(a.path),
            semanticLabel: a.label,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CategoryAvatar(icon: a.icon, color: a.color.base, size: 42),
                const SizedBox(height: 6),
                Text(
                  a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- spending donut

class SpendingCard extends StatelessWidget {
  const SpendingCard({super.key, required this.items, required this.currency});

  final List<CategoryTotal> items;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final top = items.take(4).toList();
    final restTotal = items.skip(4).fold<double>(0, (s, x) => s + x.total);
    final restPct = items.skip(4).fold<double>(0, (s, x) => s + x.pct);
    final total = items.fold<double>(0, (s, x) => s + x.total);

    Widget legend(Color color, String name, double pct) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: GhinaRadii.rSm,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${pct.round()}%',
            style: GhinaType.bodyS.w(900).copyWith(color: g.textSecondary),
          ),
        ],
      ),
    );

    return ChunkyCard(
      onTap: () => context.push('/reports'),
      semanticLabel: 'Pengeluaran per kategori',
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(enabled: false),
                    sections: [
                      for (final c in top)
                        PieChartSectionData(
                          value: c.total,
                          color: CategoryColors.parse(c.color),
                          radius: 20,
                          showTitle: false,
                        ),
                      if (restTotal > 0)
                        PieChartSectionData(
                          value: restTotal,
                          color: GhinaColors.gray.base,
                          radius: 20,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(38),
                  child: FittedBox(
                    child: Text(
                      GhinaMoney.format(
                        total,
                        currency: currency,
                        compact: true,
                      ),
                      style: GhinaType.moneyS
                          .w(900)
                          .copyWith(color: g.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in top)
                  legend(CategoryColors.parse(c.color), c.name, c.pct),
                if (restTotal > 0)
                  legend(GhinaColors.gray.base, 'Lainnya', restPct),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- budgets

class BudgetSnapshotCard extends StatelessWidget {
  const BudgetSnapshotCard({
    super.key,
    required this.month,
    required this.hearts,
    required this.currency,
  });

  final BudgetMonth month;
  final HeartsState? hearts;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (month.items.isEmpty) {
      return ChunkyCard(
        child: Row(
          children: [
            CategoryAvatar(
              icon: Icons.pie_chart_rounded,
              color: GhinaColors.green.base,
              size: 44,
              soft: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Belum ada anggaran bulan ini. Pasang batas biar hatimu aman ❤️',
                style: GhinaType.body.w(700).copyWith(color: g.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            ChunkyButton(
              label: 'Buat',
              size: ChunkyButtonSize.small,
              onPressed: () => context.push('/budgets/new'),
            ),
          ],
        ),
      );
    }
    final top = month.items.take(3).toList();
    final near = hearts?.nearLimit.length ?? 0;
    return ChunkyCard(
      onTap: () => context.push('/budgets'),
      semanticLabel: 'Anggaran bulan ini',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in top.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              children: [
                CategoryAvatar(
                  iconName: b.category?.icon,
                  colorHex: b.category?.color,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.category?.name ?? 'Kategori',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.body
                                  .w(800)
                                  .copyWith(color: g.textPrimary),
                            ),
                          ),
                          Text(
                            b.over ? 'Lewat!' : '${b.pct.round()}%',
                            style: GhinaType.bodyS
                                .w(900)
                                .copyWith(
                                  color: b.over
                                      ? GhinaColors.red.base
                                      : b.pct >= 75
                                      ? GhinaColors.orange.base
                                      : g.textSecondary,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ChunkyProgressBar.budget(used: b.pct / 100, height: 12),
                      const SizedBox(height: 4),
                      Text(
                        '${GhinaMoney.format(b.spent, currency: currency)} dari ${GhinaMoney.format(b.budget.amount, currency: currency)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (month.overCount > 0 || near > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    (month.overCount > 0 ? GhinaColors.red : GhinaColors.orange)
                        .tint(g.brightness),
                borderRadius: GhinaRadii.rMd,
              ),
              child: Text(
                month.overCount > 0
                    ? '${month.overCount} anggaran kelewat. Tiap satu makan 1 hati 💔'
                    : '$near anggaran hampir habis. Rem dikit, yuk!',
                style: GhinaType.bodyS
                    .w(800)
                    .copyWith(
                      color: month.overCount > 0
                          ? GhinaColors.red.base
                          : GhinaColors.orange.base,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- subscriptions

class UpcomingSubscriptionsCard extends StatelessWidget {
  const UpcomingSubscriptionsCard({
    super.key,
    required this.items,
    required this.now,
    required this.currency,
  });

  final List<Subscription> items;
  final DateTime now;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final s in items)
            ChunkyTile(
              framed: false,
              dense: true,
              onTap: () => context.push('/subscriptions/${s.id}'),
              leading: CategoryAvatar(
                iconName: s.icon,
                colorHex: s.color,
                size: 40,
              ),
              title: s.name,
              subtitle: switch (s.daysUntilNext(now)) {
                <= 0 => 'Jatuh tempo hari ini',
                1 => 'Besok',
                final d =>
                  '$d hari lagi · ${Fmt.dateShortWeekday(s.nextOccurrence(now))}',
              },
              trailing: MoneyText(
                amount: s.amount,
                currency: s.currency,
                tone: MoneyTone.neutral,
                style: GhinaType.moneyS,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- recent transactions

class RecentTransactionsCard extends StatelessWidget {
  const RecentTransactionsCard({
    super.key,
    required this.items,
    required this.currency,
    required this.now,
  });

  final List<TransactionView> items;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final t in items)
            TransactionRow(view: t, currency: currency, now: now),
        ],
      ),
    );
  }
}

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.view,
    required this.currency,
    required this.now,
  });

  final TransactionView view;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = view;
    final leading = t.type == TxType.adjustment
        ? CategoryAvatar(
            icon: Icons.tune_rounded,
            color: GhinaColors.gray.base,
            size: 40,
            soft: true,
          )
        : t.type == TxType.transfer
        ? CategoryAvatar(
            icon: Icons.swap_horiz_rounded,
            color: GhinaColors.blue.base,
            size: 40,
          )
        : CategoryAvatar(
            iconName: t.category?.icon,
            colorHex: t.category?.color,
            size: 40,
          );
    final what = switch (t.type) {
      TxType.transfer =>
        '${t.wallet?.name ?? 'Dompet'} → ${t.toWallet?.name ?? 'Dompet'}',
      TxType.adjustment => t.wallet?.name ?? 'Dompet',
      _ => t.category?.name ?? t.type.label,
    };
    return ChunkyTile(
      framed: false,
      dense: true,
      onTap: () => context.push('/transactions/${t.id}'),
      leading: leading,
      title: t.title,
      subtitle: '$what · ${Fmt.relativeDay(t.date, now: now)}',
      trailing: t.type == TxType.adjustment
          ? MoneyText(
              text: GhinaMoney.format(
                t.amount,
                currency: t.wallet?.currency ?? currency,
                showSign: true,
              ),
              tone: MoneyTone.neutral,
              color: context.ghina.textSecondary,
              style: GhinaType.moneyS,
            )
          : MoneyText(
              amount: t.amount,
              currency: t.wallet?.currency ?? currency,
              tone: switch (t.type) {
                TxType.expense => MoneyTone.expense,
                TxType.income => MoneyTone.income,
                _ => MoneyTone.transfer,
              },
              style: GhinaType.moneyS,
            ),
    );
  }
}

// ---------------------------------------------------------------- mascot

class HomeMascot extends StatelessWidget {
  const HomeMascot({super.key, required this.mood, required this.message});

  /// The engine's mood (task-aware line from `homeMascotProvider`).
  final game.MascotMood mood;
  final String message;

  @override
  Widget build(BuildContext context) =>
      MascotSpeech(mood: mascotMoodOf(mood), mascotSize: 84, message: message);
}
