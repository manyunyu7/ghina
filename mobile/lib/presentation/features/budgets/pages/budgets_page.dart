import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/session_controller.dart';
import '../budgets_state.dart';
import '../widgets/budget_card.dart';
import '../../../shared/widgets/widgets.dart';

/// Monthly budgets: hearts (budget health), total vs spent, per-category cards.
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetsMonthProvider);
    final data = ref.watch(watchBudgetMonthProvider(month));
    final canAdd = data.value?.unbudgetedCategories.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anggaran'),
        actions: [
          IconButton(
            tooltip: 'Tambah budget',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/budgets/new'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: canAdd
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: ChunkyButton(
                label: 'Pasang budget',
                icon: Icons.add_rounded,
                onPressed: () => context.push('/budgets/new'),
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
                onRetry: () => ref.invalidate(watchBudgetMonthProvider(month)),
              ),
            ],
          ),
          data: (bm) => _BudgetsBody(month: bm),
        ),
      ),
    );
  }
}

class _BudgetsBody extends ConsumerWidget {
  const _BudgetsBody({required this.month});

  final BudgetMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final now = ref.watch(clockProvider).now();
    final current = YearMonth.of(now);
    final noCategories =
        month.items.isEmpty && month.unbudgetedCategories.isEmpty;

    final children = <Widget>[
      MonthSwitcher(
        value: month.month,
        current: current,
        onChanged: ref.read(budgetsMonthProvider.notifier).set,
      ),
      const SizedBox(height: 16),
    ];

    if (noCategories) {
      children.add(
        EmptyState(
          title: 'Belum ada kategori pengeluaran',
          message:
              'Budget dipasang per kategori pengeluaran. Bikin kategorinya dulu, nanti balik lagi ke sini ya.',
          actionLabel: 'Buat kategori',
          onAction: () => context.push('/categories/new'),
        ),
      );
    } else {
      children
        ..add(_HeartsCard(month: month, isCurrent: month.month == current))
        ..add(const SizedBox(height: 12));
      if (month.items.isEmpty) {
        children.add(
          EmptyState(
            title: 'Belum ada budget buat ${monthLabel(month.month)}',
            message:
                'Pasang batas belanja per kategori biar kamu tahu kapan harus ngerem. Ghina bantu jagain! 🐷',
            actionLabel: 'Pasang budget',
            onAction: () => context.push('/budgets/new'),
          ),
        );
      } else {
        children
          ..add(
            _SummaryCard(
              month: month,
              currency: currency,
              now: now,
              isCurrent: month.month == current,
            ),
          )
          ..add(const SizedBox(height: 16))
          ..add(
            _MascotReaction(month: month, isCurrent: month.month == current),
          )
          ..add(
            const SectionHeader(
              title: 'Per kategori',
              subtitle: 'Yang paling kepake paling atas',
              padding: EdgeInsets.only(top: 20, bottom: 12),
            ),
          );
        for (var i = 0; i < month.items.length; i++) {
          final b = month.items[i];
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PopIn(
                delay: Duration(milliseconds: 50 * i.clamp(0, 8)),
                child: BudgetCard(
                  view: b,
                  currency: currency,
                  onTap: () => context.push('/budgets/${b.budget.id}'),
                  onTransactionTap: (id) => context.push('/transactions/$id'),
                ),
              ),
            ),
          );
        }
      }
      if (month.unbudgetedCategories.isNotEmpty && month.items.isNotEmpty) {
        children.add(_Unbudgeted(categories: month.unbudgetedCategories));
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: children,
    );
  }
}

// ---------------------------------------------------------------- hearts

class _HeartsCard extends ConsumerWidget {
  const _HeartsCard({required this.month, required this.isCurrent});

  final BudgetMonth month;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    // The engine owns this month's hearts; other months are derived the same way.
    var hearts = (5 - month.overCount).clamp(0, 5);
    var max = 5;
    if (isCurrent) {
      final h = ref.watch(gameSummaryProvider).value?.hearts;
      if (h != null &&
          h.month.year == month.month.year &&
          h.month.month == month.month.month) {
        hearts = h.current;
        max = h.max;
      }
    }
    final lost = max - hearts;
    final String title;
    final String body;
    if (month.items.isEmpty) {
      title = 'Hati kamu masih utuh';
      body =
          'Tiap kategori yang jebol budget bikin 1 hati hilang. Pasang budget biar ketahuan!';
    } else if (lost == 0) {
      title = 'Semua hati aman!';
      body =
          'Tiap kategori yang jebol budget = 1 hati hilang. Jaga $max hati sampai akhir bulan, ya.';
    } else {
      title = hearts == 0 ? 'Hatinya habis…' : '$lost hati hilang';
      body =
          '${month.overCount} kategori kelewat budget. Tiap kategori yang jebol = 1 hati.';
    }
    return ChunkyCard(
      tinted: lost == 0 ? null : GhinaColors.red,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              HeartsRow(hearts: hearts, max: max, size: 22),
            ],
          ),
          const SizedBox(height: 4),
          Text(body, style: GhinaType.bodyS.copyWith(color: g.textSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- summary

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.month,
    required this.currency,
    required this.now,
    required this.isCurrent,
  });

  final BudgetMonth month;
  final String currency;
  final DateTime now;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final remaining = month.totalRemaining;
    final daysLeft = daysInMonth(now.year, now.month) - now.day + 1;
    final perDay = remaining > 0 ? remaining / daysLeft : 0.0;
    return ChunkyCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL BUDGET',
                      style: GhinaType.overline.copyWith(
                        color: g.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        amount: month.totalBudgeted,
                        currency: currency,
                        tone: MoneyTone.neutral,
                        style: GhinaType.moneyL,
                        countUp: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TERPAKAI',
                      style: GhinaType.overline.copyWith(
                        color: g.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: MoneyText(
                        amount: month.totalSpent,
                        currency: currency,
                        tone: MoneyTone.neutral,
                        color: month.over ? GhinaColors.red.base : null,
                        style: GhinaType.moneyM.copyWith(fontSize: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ChunkyProgressBar.budget(
            used: month.totalPct / 100,
            height: 22,
            label: '${month.totalPct.round()}%',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${month.totalPct.round()}% terpakai',
                  style: GhinaType.bodyS
                      .w(700)
                      .copyWith(color: g.textSecondary),
                ),
              ),
              RemainingLabel(remaining: remaining, currency: currency),
            ],
          ),
          if (isCurrent && remaining > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: g.tint(GhinaColors.blue),
                borderRadius: GhinaRadii.rMd,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.today_rounded,
                    size: 20,
                    color: GhinaColors.blue.base,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Jatah aman '),
                          TextSpan(
                            text:
                                '${GhinaMoney.format(perDay, currency: currency)}/hari',
                            style: GhinaType.bodyS
                                .w(900)
                                .copyWith(color: g.textPrimary),
                          ),
                          TextSpan(text: ' buat $daysLeft hari lagi'),
                        ],
                      ),
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- mascot

class _MascotReaction extends StatelessWidget {
  const _MascotReaction({required this.month, required this.isCurrent});

  final BudgetMonth month;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final over = month.items.where((b) => b.over).toList();
    final near = month.items.where((b) => !b.over && b.pct >= 90).toList();
    String name(BudgetView b) => b.category?.name ?? 'kategori ini';
    final (MascotMood mood, String title, String message) = over.isNotEmpty
        ? (
            MascotMood.sad,
            'Yah, ada yang jebol',
            over.length == 1
                ? 'Budget ${name(over.first)} kelewat dikit. Gapapa, ${isCurrent ? 'sisa bulan ini kita rem bareng' : 'bulan depan kita atur lagi'} ya 💪'
                : '${over.length} budget kelewat: ${over.take(3).map(name).join(', ')}. Pelan-pelan kita benerin ya 💪',
          )
        : near.isNotEmpty
        ? (
            MascotMood.thinking,
            'Hati-hati ya',
            'Budget ${name(near.first)} udah ${near.first.pct.round()}%. Rem dikit, yuk!',
          )
        : (
            MascotMood.happy,
            'Mantap!',
            isCurrent
                ? 'Semua budget masih aman. Pertahankan sampai akhir bulan!'
                : 'Semua budget di bulan ini aman terkendali.',
          );
    return MascotSpeech(
      mood: mood,
      title: title,
      message: message,
      mascotSize: 76,
    );
  }
}

// ---------------------------------------------------------------- unbudgeted

class _Unbudgeted extends ConsumerWidget {
  const _Unbudgeted({required this.categories});

  final List<TxCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Belum ada budget',
          subtitle: 'Ketuk buat pasang batasnya',
          padding: EdgeInsets.only(top: 12, bottom: 12),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in categories)
              ChunkyChip(
                label: c.name,
                icon: GhinaIcons.of(c.icon),
                color: CategoryColors.swatch(c.color),
                selected: false,
                onTap: () {
                  ref.read(budgetDraftCategoryProvider.notifier).set(c.id);
                  context.push('/budgets/new');
                },
              ),
          ],
        ),
      ],
    );
  }
}
