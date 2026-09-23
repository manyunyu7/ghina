import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/report_charts.dart';

/// Selected report window (web default: last 6 months).
final reportPeriodProvider = NotifierProvider<ReportPeriodState, ReportPeriod>(
  ReportPeriodState.new,
);

class ReportPeriodState extends Notifier<ReportPeriod> {
  @override
  ReportPeriod build() => ReportPeriod.last6Months;

  void set(ReportPeriod p) => state = p;
}

/// Income vs expense, spending by category, cashflow, savings rate, income
/// sources and net worth.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final data = ref.watch(watchReportProvider(period));
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            const _PeriodChips(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: data.when(
                skipLoadingOnReload: true,
                loading: () => const Column(
                  children: [
                    Skeleton(height: 140, radius: GhinaRadii.xl),
                    SizedBox(height: 16),
                    Skeleton(height: 240, radius: GhinaRadii.xl),
                    SizedBox(height: 16),
                    Skeleton(height: 240, radius: GhinaRadii.xl),
                  ],
                ),
                error: (_, _) => ErrorRetry(
                  onRetry: () => ref.invalidate(watchReportProvider(period)),
                ),
                data: (r) => r.hasData
                    ? _ReportBody(report: r)
                    : Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: EmptyState(
                          title: 'Belum ada data di periode ini',
                          message:
                              'Nggak ada pemasukan atau pengeluaran di "${r.label}". Coba periode lain, atau catat transaksi dulu.',
                          actionLabel: 'Catat transaksi',
                          onAction: () => context.push('/transactions/new'),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChips extends ConsumerWidget {
  const _PeriodChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final set = ref.read(reportPeriodProvider.notifier).set;
    final nowYear = ref.watch(clockProvider).now().year;
    final isYear = period.range == ReportRange.year;
    Widget chip(
      String label,
      bool selected,
      VoidCallback onTap, {
      IconData? icon,
    }) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChunkyChip(
        label: label,
        selected: selected,
        onTap: onTap,
        icon: icon,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Wrap(
        runSpacing: 8,
        children: [
          chip(
            '6 bulan',
            period == ReportPeriod.last6Months,
            () => set(ReportPeriod.last6Months),
          ),
          chip(
            '12 bulan',
            period == ReportPeriod.last12Months,
            () => set(ReportPeriod.last12Months),
          ),
          chip(
            'Bulan ini',
            period == ReportPeriod.thisMonth,
            () => set(ReportPeriod.thisMonth),
          ),
          chip(
            isYear ? 'Tahun ${period.year}' : 'Per tahun',
            isYear,
            icon: Icons.expand_more_rounded,
            () async {
              final y = await showChunkyBottomSheet<int>(
                context,
                title: 'Pilih tahun',
                showClose: true,
                builder: (c) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var y = nowYear; y >= nowYear - 5; y--)
                      ChunkyChip(
                        label: '$y',
                        selected: isYear && period.year == y,
                        onTap: () => Navigator.of(c).pop(y),
                      ),
                  ],
                ),
              );
              if (y != null) set(ReportPeriod.year(y));
            },
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.report});

  final ReportData report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = report;
    final currency = ref.watch(currencyProvider);
    final avgOut = r.months.isEmpty ? 0.0 : r.totalExpense / r.months.length;
    Widget stat(
      String label,
      double v,
      MoneyTone tone,
      IconData icon,
      ChunkySwatch c,
    ) => _StatCard(
      label: label,
      amount: v,
      tone: tone,
      icon: icon,
      color: c,
      currency: currency,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SavingsHero(report: r),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: stat(
                'Pemasukan',
                r.totalIncome,
                MoneyTone.income,
                Icons.south_west_rounded,
                GhinaColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: stat(
                'Pengeluaran',
                r.totalExpense,
                MoneyTone.expense,
                Icons.north_east_rounded,
                GhinaColors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: stat(
                'Tabungan bersih',
                r.netSavings,
                MoneyTone.auto,
                Icons.savings_rounded,
                GhinaColors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: stat(
                'Rata-rata keluar/bln',
                avgOut,
                MoneyTone.neutral,
                Icons.calendar_month_rounded,
                GhinaColors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _ReportCard(
          title: 'Pemasukan vs pengeluaran',
          icon: Icons.bar_chart_rounded,
          trailing: const _Legend(),
          child: SizedBox(
            height: 210,
            child: IncomeExpenseChart(months: r.months, currency: currency),
          ),
        ),
        _ReportCard(
          title: 'Pengeluaran per kategori',
          icon: Icons.donut_large_rounded,
          child: r.spending.isEmpty
              ? const _NoRows('Belum ada pengeluaran di periode ini.')
              : CategoryDonut(
                  rows: r.spending,
                  currency: currency,
                  centerLabel: 'Total keluar',
                ),
        ),
        _ReportCard(
          title: 'Kategori paling boros',
          icon: Icons.local_fire_department_rounded,
          child: r.spending.isEmpty
              ? const _NoRows('Belum ada yang bisa diurutkan.')
              : _RankList(
                  rows: r.spending.take(6).toList(),
                  currency: currency,
                  tone: MoneyTone.expense,
                ),
        ),
        _ReportCard(
          title: 'Arus kas bersih',
          icon: Icons.show_chart_rounded,
          child: SizedBox(
            height: 190,
            child: CashflowChart(months: r.months, currency: currency),
          ),
        ),
        _ReportCard(
          title: 'Sumber pemasukan',
          icon: Icons.account_balance_rounded,
          child: r.income.isEmpty
              ? const _NoRows('Belum ada pemasukan di periode ini.')
              : CategoryDonut(
                  rows: r.income,
                  currency: currency,
                  centerLabel: 'Total masuk',
                  maxSlices: 5,
                ),
        ),
        _ReportCard(
          title: 'Kekayaan bersih',
          icon: Icons.account_balance_wallet_rounded,
          child: _NetWorth(report: r, currency: currency),
        ),
      ],
    );
  }
}

class _SavingsHero extends StatelessWidget {
  const _SavingsHero({required this.report});
  final ReportData report;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rate = report.savingsRate;
    final sw = rate >= 20
        ? GhinaColors.green
        : rate >= 0
        ? GhinaColors.orange
        : GhinaColors.red;
    final (MascotMood mood, String msg) = rate >= 20
        ? (
            MascotMood.excited,
            'Keren! Kamu nabung ${rate.toStringAsFixed(0)}% dari pemasukan. Pertahankan!',
          )
        : rate >= 0
        ? (MascotMood.thinking, 'Lumayan! Coba naikin pelan-pelan ke 20%, yuk.')
        : (
            MascotMood.sad,
            'Pengeluaran lebih gede dari pemasukan. Kita rem bareng, ya 💪',
          );
    return ChunkyCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ProgressRing(
            value: rate / 100,
            size: 96,
            stroke: 11,
            color: sw,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '${rate.toStringAsFixed(rate.abs() < 10 ? 1 : 0)}%',
                  style: GhinaType.h2.w(900).copyWith(color: sw.base),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RASIO TABUNGAN',
                  style: GhinaType.overline.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  report.label,
                  style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  msg,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          MascotView(mood: mood, size: 52),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.amount,
    required this.tone,
    required this.icon,
    required this.color,
    required this.currency,
  });

  final String label;
  final double amount;
  final MoneyTone tone;
  final IconData icon;
  final ChunkySwatch color;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.all(12),
      borderRadius: GhinaRadii.rLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: g.tint(color),
                  borderRadius: GhinaRadii.rSm,
                ),
                child: Icon(icon, size: 18, color: color.base),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              amount: amount,
              currency: currency,
              tone: tone,
              style: GhinaType.moneyM.copyWith(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ChunkyCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: g.textMuted, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
            if (trailing != null) ...[const SizedBox(height: 8), trailing!],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget dot(String l, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(l, style: GhinaType.caption.copyWith(color: g.textSecondary)),
      ],
    );
    return Wrap(
      spacing: 14,
      children: [
        dot('Pemasukan', GhinaColors.green.base),
        dot('Pengeluaran', GhinaColors.red.base),
      ],
    );
  }
}

class _NoRows extends StatelessWidget {
  const _NoRows(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
    ),
  );
}

class _RankList extends StatelessWidget {
  const _RankList({
    required this.rows,
    required this.currency,
    required this.tone,
  });

  final List<CategoryTotal> rows;
  final String currency;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              children: [
                Row(
                  children: [
                    CategoryAvatar(
                      iconName: rows[i].category?.icon ?? 'circle',
                      colorHex: rows[i].color,
                      size: 34,
                      soft: true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        rows[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MoneyText(
                      amount: rows[i].total,
                      currency: currency,
                      tone: MoneyTone.neutral,
                      style: GhinaType.moneyS.copyWith(fontSize: 14),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${rows[i].pct.toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ChunkyProgressBar(
                  value: (rows[i].pct / 100).clamp(0.02, 1.0),
                  color: CategoryColors.swatch(rows[i].color),
                  height: 10,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NetWorth extends StatelessWidget {
  const _NetWorth({required this.report, required this.currency});
  final ReportData report;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final total = report.netWorth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            amount: total,
            currency: currency,
            tone: MoneyTone.neutral,
            style: GhinaType.moneyL,
            countUp: true,
          ),
        ),
        Text(
          'Total saldo semua dompet aktif',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 14),
        if (report.wallets.isEmpty) const _NoRows('Belum ada dompet.'),
        for (final w in report.wallets)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    WalletAvatar(wallet: w, size: 34, soft: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MoneyText(
                      amount: w.balance,
                      currency: w.currency.isEmpty ? currency : w.currency,
                      tone: w.balance < 0 ? MoneyTone.auto : MoneyTone.neutral,
                      style: GhinaType.moneyS.copyWith(fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ChunkyProgressBar(
                  value: total > 0 ? (w.balance / total).clamp(0.02, 1.0) : 0,
                  color: CategoryColors.swatch(w.color),
                  height: 10,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
