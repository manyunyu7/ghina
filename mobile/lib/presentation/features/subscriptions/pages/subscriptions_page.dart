import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/due_chip.dart';

/// Recurring payments: monthly damage, what's due soon (with quick pay), and
/// paused ones.
class SubscriptionsPage extends ConsumerWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(watchSubscriptionsProvider);
    final hasItems = data.value?.items.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Langganan'),
        actions: [
          IconButton(
            tooltip: 'Tambah langganan',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/subscriptions/new'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: hasItems
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: ChunkyButton(
                label: 'Tambah langganan',
                icon: Icons.add_rounded,
                onPressed: () => context.push('/subscriptions/new'),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: data.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingListView(),
          error: (_, _) => ListView(
            children: [
              ErrorRetry(
                onRetry: () => ref.invalidate(watchSubscriptionsProvider),
              ),
            ],
          ),
          data: (s) => s.items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 40),
                  children: [
                    EmptyState(
                      title: 'Belum ada langganan',
                      message:
                          'Catat Netflix, Spotify, gym, atau apa pun yang kamu bayar rutin. Nanti kelihatan total per bulannya!',
                      actionLabel: 'Tambah langganan',
                      onAction: () => context.push('/subscriptions/new'),
                    ),
                  ],
                )
              : _SubscriptionsBody(summary: s),
        ),
      ),
    );
  }
}

class _SubscriptionsBody extends ConsumerWidget {
  const _SubscriptionsBody({required this.summary});

  final SubscriptionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final currency = ref.watch(currencyProvider);
    final now = ref.watch(clockProvider).now();
    final wallets = {
      for (final w
          in ref.watch(watchAllWalletsProvider).value ?? const <Wallet>[])
        w.id: w,
    };
    final active = summary.active.toList()
      ..sort((a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)));
    final paused = summary.items.where((s) => !s.active).toList();
    final dueSoon = active.where((s) => s.daysUntilNext(now) <= 7).length;

    Widget card(Subscription s, int i) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PopIn(
        delay: Duration(milliseconds: 50 * i.clamp(0, 8)),
        child: _SubscriptionCard(
          sub: s,
          wallet: wallets[s.walletId],
          now: now,
          currency: currency,
        ),
      ),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        ChunkyCard(
          color: GhinaColors.purple,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LANGGANAN PER BULAN',
                      style: GhinaType.overline.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        amount: summary.monthlyTotal,
                        currency: currency,
                        color: Colors.white,
                        tone: MoneyTone.neutral,
                        style: GhinaType.moneyL,
                        countUp: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '≈ ${GhinaMoney.format(summary.yearlyTotal, currency: currency)} setahun · ${active.length} dari ${summary.items.length} aktif',
                      style: GhinaType.bodyS
                          .w(700)
                          .copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const MascotView(mood: MascotMood.thinking, size: 72),
            ],
          ),
        ),
        if (dueSoon > 0) ...[
          const SizedBox(height: 12),
          ChunkyCard(
            tinted: GhinaColors.orange,
            depth: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  color: GhinaColors.orange.base,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$dueSoon tagihan jatuh tempo minggu ini. Siapin saldonya, ya!',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (active.isNotEmpty) ...[
          const SectionHeader(
            title: 'Tagihan berikutnya',
            subtitle: 'Urut dari yang paling dekat',
            padding: EdgeInsets.only(top: 22, bottom: 12),
          ),
          for (var i = 0; i < active.length; i++) card(active[i], i),
        ],
        if (paused.isNotEmpty) ...[
          const SectionHeader(
            title: 'Dijeda',
            subtitle: 'Nggak dihitung ke total bulanan',
            padding: EdgeInsets.only(top: 14, bottom: 12),
          ),
          for (var i = 0; i < paused.length; i++)
            card(paused[i], active.length + i),
        ],
      ],
    );
  }
}

class _SubscriptionCard extends ConsumerStatefulWidget {
  const _SubscriptionCard({
    required this.sub,
    required this.wallet,
    required this.now,
    required this.currency,
  });

  final Subscription sub;
  final Wallet? wallet;
  final DateTime now;
  final String currency;

  @override
  ConsumerState<_SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends ConsumerState<_SubscriptionCard> {
  bool _paying = false;

  Subscription get s => widget.sub;
  String get _cur => s.currency.isEmpty ? widget.currency : s.currency;

  Future<void> _pay() async {
    final next = s.nextOccurrence(widget.now);
    final walletName = widget.wallet?.name ?? 'dompet pertamamu';
    final ok = await showChunkyConfirm(
      context,
      title: 'Bayar ${s.name}?',
      message:
          'Ghina catat pengeluaran ${GhinaMoney.format(s.amount, currency: _cur)} dari $walletName hari ini, lalu tagihan berikutnya maju ke ${Fmt.date(s.cycle.advance(next))}.',
      confirmLabel: 'Bayar',
      mood: MascotMood.happy,
    );
    if (!ok || !mounted) return;
    setState(() => _paying = true);
    final rewards = RewardTracker.start(ref);
    final r = await ref.read(paySubscriptionProvider)(s.id);
    if (!mounted) return;
    setState(() => _paying = false);
    switch (r) {
      case Ok():
        await rewards.finish(
          context,
          xpToast: (xp) => '${s.name} lunas! +$xp XP',
          doneToast: '${s.name} lunas!',
        );
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  Future<void> _more() async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: s.name,
      showClose: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyTile(
            dense: true,
            leading: Icon(
              s.active ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
              color: GhinaColors.blue.base,
              size: 30,
            ),
            title: s.active ? 'Jeda dulu' : 'Aktifkan lagi',
            subtitle: s.active
                ? 'Nggak dihitung ke total bulanan'
                : 'Masuk lagi ke tagihan rutin',
            onTap: () => Navigator.of(c).pop('toggle'),
          ),
          const SizedBox(height: 8),
          ChunkyTile(
            dense: true,
            leading: Icon(
              Icons.edit_rounded,
              color: GhinaColors.green.base,
              size: 30,
            ),
            title: 'Ubah',
            onTap: () => Navigator.of(c).pop('edit'),
          ),
          const SizedBox(height: 8),
          ChunkyTile(
            dense: true,
            leading: Icon(
              Icons.delete_rounded,
              color: GhinaColors.red.base,
              size: 30,
            ),
            title: 'Hapus',
            onTap: () => Navigator.of(c).pop('delete'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'toggle':
        final r = await ref.read(toggleSubscriptionProvider)(s.id);
        if (!mounted) return;
        switch (r) {
          case Ok(:final value):
            showToastBadge(
              context,
              message: value ? '${s.name} aktif lagi' : '${s.name} dijeda dulu',
              icon: value ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: GhinaColors.blue,
            );
          case Err(:final failure):
            showErrorToast(context, failure.message);
        }
      case 'edit':
        context.push('/subscriptions/${s.id}');
      case 'delete':
        final ok = await showChunkyConfirm(
          context,
          title: 'Hapus ${s.name}?',
          message:
              'Cuma pengingatnya yang dihapus. Transaksi yang sudah tercatat tetap aman.',
          confirmLabel: 'Hapus',
          destructive: true,
        );
        if (!ok || !mounted) return;
        final r = await ref.read(deleteSubscriptionProvider)(s.id);
        if (r case Err(:final failure) when mounted) {
          showErrorToast(context, failure.message);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final next = s.active ? s.nextOccurrence(widget.now) : s.nextBilling;
    final days = s.daysUntilNext(widget.now);
    final card = ChunkyCard(
      onTap: () => context.push('/subscriptions/${s.id}'),
      semanticLabel: s.name,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CategoryAvatar(iconName: s.icon, colorHex: s.color, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: GhinaMoney.format(s.amount, currency: _cur),
                            style: GhinaType.moneyM.copyWith(
                              color: g.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: s.cycle.per,
                            style: GhinaType.bodyS.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Lainnya',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_vert_rounded, color: g.textMuted),
                onPressed: _more,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (s.active)
                      DueChip(days: days)
                    else
                      ChunkyPill(
                        label: 'Dijeda',
                        color: GhinaColors.gray,
                        soft: true,
                      ),
                    Text(
                      Fmt.dateShortWeekday(next),
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                    if (widget.wallet != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 14,
                            color: g.textMuted,
                          ),
                          const SizedBox(width: 3),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              widget.wallet!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.caption.copyWith(
                                color: g.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (s.active) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChunkyButton(
                    label: 'Bayar',
                    size: ChunkyButtonSize.small,
                    icon: Icons.check_rounded,
                    loading: _paying,
                    color: days <= 1 ? GhinaColors.green : GhinaColors.blue,
                    variant: ChunkyButtonVariant.secondary,
                    onPressed: _pay,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    return s.active ? card : Opacity(opacity: 0.65, child: card);
  }
}
