import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../forecast_state.dart';
import '../widgets/balance_chart.dart';

/// Look ahead at a month: planned items, subscription bills and (optionally)
/// history averages → projected in/out/net and a projected balance line.
class ForecastPage extends ConsumerWidget {
  const ForecastPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(forecastMonthProvider);
    final data = ref.watch(watchForecastProvider(month));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perkiraan'),
        actions: [
          IconButton(
            tooltip: 'Tambah rencana',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/forecast/new'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: (data.value?.isEmpty ?? true)
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: ChunkyButton(
                label: 'Tambah rencana',
                icon: Icons.add_rounded,
                onPressed: () => context.push('/forecast/new'),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: data.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingListView(),
          error: (_, _) => ListView(
            children: [
              ErrorRetry(
                onRetry: () => ref.invalidate(watchForecastProvider(month)),
              ),
            ],
          ),
          data: (f) => _ForecastBody(forecast: f),
        ),
      ),
    );
  }
}

class _ForecastBody extends ConsumerWidget {
  const _ForecastBody({required this.forecast});

  final Forecast forecast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final f = forecast;
    final currency = ref.watch(currencyProvider);
    final now = ref.watch(clockProvider).now();
    final sources = ref.watch(forecastSourcesProvider);
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final cats = {
      for (final c
          in ref.watch(watchCategoriesProvider(null)).value ??
              const <TxCategory>[])
        c.id: c,
    };
    final walletById = {for (final w in wallets) w.id: w};
    final label = monthLabel(f.month);

    final children = <Widget>[
      MonthSwitcher(
        value: f.month,
        current: YearMonth.of(now),
        onChanged: ref.read(forecastMonthProvider.notifier).set,
      ),
      const SizedBox(height: 16),
    ];

    if (f.isEmpty) {
      children.add(
        EmptyState(
          title: 'Belum ada perkiraan buat $label',
          message:
              'Catat tagihan, gajian, atau pengeluaran besar yang bakal datang. Langganan aktif & riwayat belanjamu otomatis ikut muncul di sini.',
          actionLabel: 'Tambah rencana',
          onAction: () => context.push('/forecast/new'),
        ),
      );
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: children,
      );
    }

    final totals = f.totals(sources);
    final startBalance = wallets.fold<double>(0, (s, w) => s + w.balance);
    final points = projectBalance(f, sources, startBalance);
    final end = points.last.balance;

    children
      ..add(
        _ProjectionCard(
          label: label,
          month: f.month,
          start: startBalance,
          end: end,
          net: totals.net,
          points: points,
          currency: currency,
          none: sources.none,
        ),
      )
      ..add(const SizedBox(height: 16))
      ..add(
        ChunkyChoiceChips<String>(
          multi: true,
          allowEmpty: true,
          options: [
            ChunkyChoice(
              value: 'manual',
              label: 'Rencana · ${f.planned.length}',
              icon: Icons.edit_note_rounded,
              color: GhinaColors.green,
            ),
            ChunkyChoice(
              value: 'subs',
              label: 'Langganan · ${f.subscriptionItems.length}',
              icon: Icons.event_repeat_rounded,
              color: GhinaColors.purple,
            ),
            ChunkyChoice(
              value: 'history',
              label: 'Riwayat · ${f.averages.length}',
              icon: Icons.history_rounded,
              color: GhinaColors.orange,
            ),
          ],
          selected: {
            if (sources.manual) 'manual',
            if (sources.subscriptions) 'subs',
            if (sources.history) 'history',
          },
          onChanged: (s) => ref
              .read(forecastSourcesProvider.notifier)
              .set(
                ForecastSources(
                  manual: s.contains('manual'),
                  subscriptions: s.contains('subs'),
                  history: s.contains('history'),
                ),
              ),
        ),
      )
      ..add(const SizedBox(height: 12))
      ..add(
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'Uang masuk',
                amount: totals.projectedIncome,
                currency: currency,
                tone: MoneyTone.income,
                icon: Icons.south_west_rounded,
                color: GhinaColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: 'Uang keluar',
                amount: totals.projectedExpense,
                currency: currency,
                tone: MoneyTone.expense,
                icon: Icons.north_east_rounded,
                color: GhinaColors.red,
              ),
            ),
          ],
        ),
      );

    if (sources.none) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 20),
          child: MascotSpeech(
            mood: MascotMood.thinking,
            mascotSize: 70,
            message:
                'Pilih minimal satu sumber di atas biar Ghina bisa ngira-ngira, ya.',
          ),
        ),
      );
    }

    if (sources.manual) {
      children.add(
        const SectionHeader(
          title: 'Rencana kamu',
          subtitle: 'Catatan aja, nggak ngubah saldo dompet',
          padding: EdgeInsets.only(top: 24, bottom: 12),
        ),
      );
      if (f.planned.isEmpty) {
        children.add(
          ChunkyCard(
            onTap: () => context.push('/forecast/new'),
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_rounded,
                  color: GhinaColors.green.base,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Belum ada rencana di $label. Catat satu, yuk!',
                    style: GhinaType.body
                        .w(700)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      for (var i = 0; i < f.planned.length; i++) {
        final p = f.planned[i];
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PopIn(
              delay: Duration(milliseconds: 50 * i.clamp(0, 8)),
              child: _PlannedCard(
                item: p,
                category: cats[p.categoryId],
                wallet: walletById[p.walletId],
                fallbackWallet: wallets.firstOrNull,
                currency: currency,
              ),
            ),
          ),
        );
      }
    }

    if (sources.subscriptions && f.subscriptionItems.isNotEmpty) {
      children
        ..add(
          const SectionHeader(
            title: 'Dari langganan',
            subtitle: 'Tagihan rutin yang jatuh di bulan ini',
            padding: EdgeInsets.only(top: 16, bottom: 12),
          ),
        )
        ..add(
          _ReadonlyGroup(
            rows: [
              for (final s in f.subscriptionItems)
                ChunkyTile(
                  framed: false,
                  dense: true,
                  leading: CategoryAvatar(
                    iconName: s.subscription.icon,
                    colorHex: s.subscription.color,
                    size: 38,
                  ),
                  title: s.subscription.name,
                  subtitle: Fmt.dateShortWeekday(s.date),
                  trailing: MoneyText(
                    amount: s.amount,
                    currency: s.subscription.currency.isEmpty
                        ? currency
                        : s.subscription.currency,
                    tone: MoneyTone.expense,
                    style: GhinaType.moneyS.copyWith(fontSize: 15),
                  ),
                  onTap: () =>
                      context.push('/subscriptions/${s.subscription.id}'),
                ),
            ],
          ),
        );
    }

    if (sources.history && f.averages.isNotEmpty) {
      children
        ..add(
          SectionHeader(
            title: 'Perkiraan dari riwayat',
            subtitle:
                'Rata-rata ${f.historyMonths} bulan terakhir. Kira-kira aja, bukan janji.',
            padding: const EdgeInsets.only(top: 16, bottom: 12),
          ),
        )
        ..add(
          _ReadonlyGroup(
            rows: [
              for (final a in f.averages)
                ChunkyTile(
                  framed: false,
                  dense: true,
                  leading: CategoryAvatar(
                    iconName: a.category.icon,
                    colorHex: a.category.color,
                    size: 38,
                  ),
                  title: a.category.name,
                  subtitle: 'rata-rata / bulan',
                  trailing: MoneyText(
                    text: '~${GhinaMoney.format(a.avg, currency: currency)}',
                    tone: MoneyTone.expense,
                    style: GhinaType.moneyS.copyWith(fontSize: 15),
                  ),
                ),
            ],
          ),
        );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: children,
    );
  }
}

class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({
    required this.label,
    required this.month,
    required this.start,
    required this.end,
    required this.net,
    required this.points,
    required this.currency,
    required this.none,
  });

  final String label;
  final YearMonth month;
  final double start;
  final double end;
  final double net;
  final List<BalancePoint> points;
  final String currency;
  final bool none;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final negative = end < 0;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SALDO AKHIR ${Fmt.monthShort(month.month).toUpperCase()} (PERKIRAAN)',
            style: GhinaType.overline.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              amount: end,
              currency: currency,
              tone: MoneyTone.neutral,
              color: negative ? GhinaColors.red.base : null,
              style: GhinaType.moneyL,
              countUp: true,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChunkyPill(
                label:
                    '${net >= 0 ? '+' : '-'}${GhinaMoney.format(net.abs(), currency: currency)} bersih',
                color: net >= 0 ? GhinaColors.green : GhinaColors.red,
                soft: true,
                uppercase: false,
                icon: net >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
              ),
              Text(
                'dari saldo sekarang ${GhinaMoney.format(start, currency: currency, compact: true)}',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: none
                ? Center(
                    child: Text(
                      'Pilih sumber di bawah',
                      style: GhinaType.bodyS.copyWith(color: g.textMuted),
                    ),
                  )
                : BalanceChart(
                    points: points,
                    currency: currency,
                    monthShort: Fmt.monthShort(month.month),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.amount,
    required this.currency,
    required this.tone,
    required this.icon,
    required this.color,
  });

  final String label;
  final double amount;
  final String currency;
  final MoneyTone tone;
  final IconData icon;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      borderRadius: GhinaRadii.rLg,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: g.tint(color),
              borderRadius: GhinaRadii.rMd,
            ),
            child: Icon(icon, color: color.base, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    amount: amount,
                    currency: currency,
                    tone: tone,
                    style: GhinaType.moneyM,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadonlyGroup extends StatelessWidget {
  const _ReadonlyGroup({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 2, thickness: 2, color: g.border),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _PlannedCard extends ConsumerStatefulWidget {
  const _PlannedCard({
    required this.item,
    required this.category,
    required this.wallet,
    required this.fallbackWallet,
    required this.currency,
  });

  final PlannedTransaction item;
  final TxCategory? category;
  final Wallet? wallet;
  final Wallet? fallbackWallet;
  final String currency;

  @override
  ConsumerState<_PlannedCard> createState() => _PlannedCardState();
}

class _PlannedCardState extends ConsumerState<_PlannedCard> {
  bool _busy = false;

  PlannedTransaction get p => widget.item;
  bool get _expense => p.type == TxType.expense;
  String get _title => (p.note?.trim().isNotEmpty ?? false)
      ? p.note!.trim()
      : (_expense ? 'Pengeluaran' : 'Pemasukan');

  Future<void> _toggle() async {
    final r = await ref.read(togglePlannedDoneProvider)(p.id);
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        if (value) {
          showToastBadge(
            context,
            message: 'Sip, "$_title" beres ✔',
            icon: Icons.check_circle_rounded,
            color: GhinaColors.green,
          );
        }
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  Future<void> _convert() async {
    final target = widget.wallet ?? widget.fallbackWallet;
    if (target == null) {
      await showChunkyConfirm(
        context,
        title: 'Butuh dompet dulu',
        message:
            'Bikin dompet dulu di halaman Dompet, lalu balik lagi ke sini ya.',
        confirmLabel: 'Oke',
        cancelLabel: 'Tutup',
        mood: MascotMood.thinking,
      );
      return;
    }
    final amount = GhinaMoney.format(p.amount, currency: widget.currency);
    final ok = await showChunkyConfirm(
      context,
      title: 'Jadikan transaksi beneran?',
      message:
          'Ghina catat ${_expense ? 'pengeluaran' : 'pemasukan'} $amount ${_expense ? 'dari' : 'ke'} "${target.name}" tanggal ${Fmt.date(p.date)}, saldo dompetnya ikut berubah. Rencananya lalu dihapus.',
      confirmLabel: 'Jadikan transaksi',
      mood: MascotMood.happy,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final rewards = RewardTracker.start(ref);
    final r = await ref.read(convertPlannedProvider)(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok():
        await rewards.finish(
          context,
          xpToast: (xp) => 'Tercatat! +$xp XP',
          doneToast: 'Tercatat!',
        );
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final done = p.done;
    final c = widget.category;
    final meta = [
      Fmt.dateShortWeekday(p.date),
      if (c != null) c.name,
      if (widget.wallet != null) widget.wallet!.name,
    ].join(' · ');
    final card = ChunkyCard(
      onTap: () => context.push('/forecast/${p.id}'),
      semanticLabel: _title,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: done ? 'Tandai belum' : 'Tandai selesai',
                child: GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AnimatedContainer(
                      duration: GhinaMotion.fast,
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? GhinaColors.green.base
                            : Colors.transparent,
                        border: Border.all(
                          color: done ? GhinaColors.green.edge : g.border,
                          width: 3,
                        ),
                      ),
                      child: done
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CategoryAvatar(
                iconName:
                    c?.icon ?? (_expense ? 'trending-down' : 'trending-up'),
                colorHex: c?.color ?? (_expense ? '#ef4444' : '#22c55e'),
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(
                        color: g.textPrimary,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationThickness: 2,
                      ),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    amount: p.amount,
                    currency: widget.currency,
                    tone: _expense ? MoneyTone.expense : MoneyTone.income,
                    style: GhinaType.moneyM.copyWith(fontSize: 19),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ChunkyButton(
                label: 'Jadikan transaksi',
                icon: Icons.swap_horiz_rounded,
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.outline,
                loading: _busy,
                onPressed: _convert,
              ),
            ],
          ),
        ],
      ),
    );
    return done ? Opacity(opacity: 0.6, child: card) : card;
  }
}
