import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

/// One category budget: usage bar, remaining/over, expected vs actual
/// variance (like the web) and the transactions that make it up.
class BudgetCard extends StatefulWidget {
  const BudgetCard({
    super.key,
    required this.view,
    required this.currency,
    required this.onTap,
    this.onTransactionTap,
  });

  final BudgetView view;
  final String currency;
  final VoidCallback onTap;
  final ValueChanged<String>? onTransactionTap;

  @override
  State<BudgetCard> createState() => _BudgetCardState();
}

class _BudgetCardState extends State<BudgetCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final v = widget.view;
    final cur = widget.currency;
    final name = v.category?.name ?? 'Kategori terhapus';
    final pct = v.pct;
    final near = !v.over && pct >= 90;
    final pctColor = v.over
        ? GhinaColors.red.base
        : pct >= 75
        ? GhinaColors.orange.base
        : (g.isDark ? GhinaColors.green.base : GhinaColors.green.edge);
    final count = v.transactions.length;

    return ChunkyCard(
      onTap: widget.onTap,
      semanticLabel: 'Budget $name',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(
                iconName: v.category?.icon ?? 'circle',
                colorHex: v.category?.color ?? CategoryTotal.uncategorizedColor,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    if (v.over || near)
                      ChunkyPill(
                        label: v.over ? 'Jebol' : 'Mepet',
                        color: v.over ? GhinaColors.red : GhinaColors.orange,
                      )
                    else
                      ChunkyPill(
                        label: 'Aman',
                        color: GhinaColors.green,
                        soft: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${pct.round()}%',
                style: GhinaType.h2.w(900).copyWith(color: pctColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChunkyProgressBar.budget(used: pct / 100, height: 14),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${pct.round()}% terpakai',
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
              RemainingLabel(
                remaining: v.remaining,
                currency: cur,
                small: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Variance(view: v, currency: cur),
          if (count > 0) ...[
            const SizedBox(height: 4),
            InkWell(
              borderRadius: GhinaRadii.rMd,
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: g.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$count transaksi',
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textSecondary),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: GhinaMotion.fast,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: g.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: GhinaMotion.medium,
              curve: GhinaMotion.standard,
              alignment: Alignment.topCenter,
              child: _open
                  ? Column(
                      children: [
                        Divider(height: 1, thickness: 2, color: g.border),
                        for (final t in v.transactions.take(20))
                          ChunkyTile(
                            framed: false,
                            dense: true,
                            title: (t.note?.trim().isNotEmpty ?? false)
                                ? t.note!.trim()
                                : name,
                            subtitle: Fmt.relativeDay(t.date),
                            trailing: MoneyText(
                              amount: t.amount,
                              currency: cur,
                              tone: MoneyTone.expense,
                              style: GhinaType.moneyS.copyWith(fontSize: 14),
                            ),
                            onTap: widget.onTransactionTap == null
                                ? null
                                : () => widget.onTransactionTap!(t.id),
                          ),
                        if (count > 20)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '+${count - 20} transaksi lagi',
                              style: GhinaType.caption.copyWith(
                                color: g.textMuted,
                              ),
                            ),
                          ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ],
      ),
    );
  }
}

/// Expected · Actual · Difference strip.
class _Variance extends StatelessWidget {
  const _Variance({required this.view, required this.currency});

  final BudgetView view;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final diff = view.spent - view.budget.amount;
    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GhinaType.caption.copyWith(color: g.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GhinaType.moneyS.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
      ),
      child: Row(
        children: [
          cell(
            'Target',
            GhinaMoney.format(view.budget.amount, currency: currency),
            g.textPrimary,
          ),
          cell(
            'Aktual',
            GhinaMoney.format(view.spent, currency: currency),
            g.textPrimary,
          ),
          cell(
            'Selisih',
            '${diff > 0 ? '+' : '−'}${GhinaMoney.format(diff.abs(), currency: currency)}',
            diff > 0
                ? GhinaColors.red.base
                : (g.isDark ? GhinaColors.green.base : GhinaColors.green.edge),
          ),
        ],
      ),
    );
  }
}

/// "Sisa Rp X" (green) or "Lebih Rp X" (red).
class RemainingLabel extends StatelessWidget {
  const RemainingLabel({
    super.key,
    required this.remaining,
    required this.currency,
    this.small = false,
  });

  final double remaining;
  final String currency;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final over = remaining < 0;
    final style = (small ? GhinaType.caption : GhinaType.bodyS).w(900);
    return Text(
      over
          ? 'Lebih ${GhinaMoney.format(-remaining, currency: currency)}'
          : 'Sisa ${GhinaMoney.format(remaining, currency: currency)}',
      style: style.copyWith(
        color: over
            ? GhinaColors.red.base
            : (g.isDark ? GhinaColors.green.base : GhinaColors.green.edge),
      ),
    );
  }
}
