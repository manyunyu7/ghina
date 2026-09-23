import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/trend_chart.dart';

/// `68` / `68,5`
String formatKg(double w) =>
    w == w.roundToDouble() ? Fmt.number(w) : Fmt.number(w, decimals: 1);

ChunkySwatch bpSwatch(BpCategory c) => ChunkySwatch.fromColor(Color(c.color));

/// The AHA categories, for the legend (port of the web's `bp.ts`).
const bpLegend = <(String, int, String)>[
  ('Normal', 0xFF16A34A, '< 120 / < 80'),
  ('Meningkat', 0xFFF59E0B, '120–129 / < 80'),
  ('Tinggi · Tahap 1', 0xFFF59E0B, '130–139 / 80–89'),
  ('Tinggi · Tahap 2', 0xFFEF4444, '≥ 140 / ≥ 90'),
  ('Krisis hipertensi', 0xFFDC2626, '≥ 180 / ≥ 120'),
];

/// Weight + blood pressure: latest readings, trend charts and history.
class HealthPage extends ConsumerWidget {
  const HealthPage({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(syncNowProvider)();
    } catch (_) {
      if (context.mounted) {
        showErrorToast(context, 'Belum bisa sinkron. Cek koneksi kamu, ya.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(watchHealthEntriesProvider);
    final hasData = async.value?.isNotEmpty ?? false;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Kesehatan'),
        actions: [
          IconButton(
            tooltip: 'Catat',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/health/new'),
          ),
        ],
      ),
      bottomNavigationBar: hasData ? const _AddBar() : null,
      body: RefreshIndicator(
        onRefresh: () => _refresh(context, ref),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => ListView(
            children: [
              const SizedBox(height: 24),
              EmptyState(
                title: 'Belum ada catatan kesehatan',
                message:
                    'Catat berat badan atau tekanan darahmu biar trennya kelihatan. +5 XP tiap catatan!',
                mood: MascotMood.waving,
                actionLabel: 'Catat berat badan',
                onAction: () => context.push('/health/new?mode=weight'),
              ),
              Center(
                child: ChunkyButton(
                  label: 'Catat tekanan darah',
                  variant: ChunkyButtonVariant.outline,
                  size: ChunkyButtonSize.medium,
                  expand: false,
                  onPressed: () => context.push('/health/new?mode=bp'),
                ),
              ),
            ],
          ),
          AsyncData(:final value) => _content(context, value),
          AsyncError() => ListView(
            children: [
              ErrorRetry(
                onRetry: () => ref.invalidate(watchHealthEntriesProvider),
              ),
            ],
          ),
          _ => const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 5),
          ),
        },
      ),
    );
  }

  Widget _content(BuildContext context, List<HealthEntry> entries) {
    final weights = entries.where((e) => e.weight != null).toList();
    final bps = entries
        .where((e) => e.systolic != null && e.diastolic != null)
        .toList();
    final pulses = entries.where((e) => e.pulse != null).toList();

    final wSeries = weights.take(30).toList().reversed.toList();
    final bpSeries = bps.take(30).toList().reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _WeightStat(weights: weights)),
              const SizedBox(width: 12),
              Expanded(child: _BpStat(latest: bps.firstOrNull)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _PulseStat(latest: pulses.firstOrNull),
        if (wSeries.isNotEmpty) ...[
          const SizedBox(height: 28),
          const SectionHeader(title: 'Tren berat badan'),
          ChunkyCard(
            padding: const EdgeInsets.fromLTRB(8, 18, 16, 8),
            child: TrendChart(
              labels: [for (final e in wSeries) Fmt.relativeDay(e.date)],
              series: [
                TrendSeries(
                  label: 'Berat',
                  values: [for (final e in wSeries) e.weight],
                  color: GhinaColors.green,
                  fill: true,
                ),
              ],
              unit: ' kg',
              decimals: 1,
            ),
          ),
        ],
        if (bpSeries.isNotEmpty) ...[
          const SizedBox(height: 28),
          const SectionHeader(title: 'Tren tekanan darah'),
          ChunkyCard(
            padding: const EdgeInsets.fromLTRB(8, 18, 16, 12),
            child: Column(
              children: [
                TrendChart(
                  labels: [for (final e in bpSeries) Fmt.relativeDay(e.date)],
                  series: [
                    TrendSeries(
                      label: 'Sistolik',
                      values: [
                        for (final e in bpSeries) e.systolic!.toDouble(),
                      ],
                      color: GhinaColors.red,
                    ),
                    TrendSeries(
                      label: 'Diastolik',
                      values: [
                        for (final e in bpSeries) e.diastolic!.toDouble(),
                      ],
                      color: GhinaColors.blue,
                    ),
                  ],
                  guides: [
                    (120, GhinaColors.red.base),
                    (80, GhinaColors.blue.base),
                  ],
                ),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 16,
                  children: [
                    _Dot(color: GhinaColors.red, label: 'Sistolik'),
                    _Dot(color: GhinaColors.blue, label: 'Diastolik'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _BpLegendCard(),
        ],
        const SizedBox(height: 28),
        SectionHeader(title: 'Riwayat', subtitle: '${entries.length} catatan'),
        ChunkyCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [for (final e in entries) _HistoryRow(entry: e)],
          ),
        ),
      ],
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      decoration: BoxDecoration(
        color: g.background,
        border: Border(top: BorderSide(color: g.border, width: 2)),
      ),
      padding: EdgeInsets.fromLTRB(
        GhinaSpace.page,
        12,
        GhinaSpace.page,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: ChunkyButton(
              label: 'Berat',
              icon: Icons.monitor_weight_rounded,
              onPressed: () => context.push('/health/new?mode=weight'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ChunkyButton(
              label: 'Tensi',
              icon: Icons.favorite_rounded,
              color: GhinaColors.red,
              onPressed: () => context.push('/health/new?mode=bp'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.unit,
    this.footer,
  });

  final IconData icon;
  final ChunkySwatch color;
  final String label;
  final String value;
  final String? unit;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryAvatar(icon: icon, color: color.base, size: 34),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(color: g.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: GhinaType.moneyL),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit!,
                    style: GhinaType.body
                        .w(800)
                        .copyWith(color: g.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (footer != null) ...[const SizedBox(height: 6), footer!],
        ],
      ),
    );
  }
}

class _WeightStat extends StatelessWidget {
  const _WeightStat({required this.weights});

  final List<HealthEntry> weights;

  @override
  Widget build(BuildContext context) {
    final latest = weights.firstOrNull?.weight;
    final prev = weights.length > 1 ? weights[1].weight : null;
    final delta = latest != null && prev != null ? latest - prev : null;
    return _StatCard(
      icon: Icons.monitor_weight_rounded,
      color: GhinaColors.green,
      label: 'Berat',
      value: latest == null ? '—' : formatKg(latest),
      unit: latest == null ? null : 'kg',
      footer: delta == null || delta.abs() < 0.05
          ? null
          : Row(
              children: [
                Icon(
                  delta > 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                  color: delta > 0
                      ? GhinaColors.orange.base
                      : GhinaColors.green.base,
                ),
                Flexible(
                  child: Text(
                    '${formatKg(delta.abs())} kg',
                    style: GhinaType.caption.copyWith(
                      color: delta > 0
                          ? GhinaColors.orange.base
                          : GhinaColors.green.base,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _BpStat extends StatelessWidget {
  const _BpStat({required this.latest});

  final HealthEntry? latest;

  @override
  Widget build(BuildContext context) {
    final e = latest;
    final cat = e?.bpCategory;
    return _StatCard(
      icon: Icons.favorite_rounded,
      color: GhinaColors.red,
      label: 'Tekanan darah',
      value: e == null ? '—' : '${e.systolic}/${e.diastolic}',
      footer: cat == null
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ChunkyPill(
                label: cat.label,
                color: bpSwatch(cat),
                uppercase: false,
              ),
            ),
    );
  }
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({required this.latest});

  final HealthEntry? latest;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = latest?.pulse;
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CategoryAvatar(
            icon: Icons.monitor_heart_rounded,
            color: GhinaColors.pink.base,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Denyut nadi',
              style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
            ),
          ),
          Text(p == null ? '—' : '$p', style: GhinaType.moneyM),
          if (p != null) ...[
            const SizedBox(width: 4),
            Text(
              'bpm',
              style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});

  final ChunkySwatch color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color.base, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
      ),
    ],
  );
}

class _BpLegendCard extends StatelessWidget {
  const _BpLegendCard();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'KATEGORI TEKANAN DARAH',
            style: GhinaType.overline.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: 8),
          for (final (label, color, range) in bpLegend)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: GhinaType.bodyS.w(800))),
                  Text(
                    range,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HealthEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final cat = e.bpCategory;
    final parts = [
      if (e.weight != null) '${formatKg(e.weight!)} kg',
      if (e.systolic != null && e.diastolic != null)
        '${e.systolic}/${e.diastolic} mmHg',
      if (e.pulse != null) '${e.pulse} bpm',
      if (e.note != null && e.note!.isNotEmpty) e.note!,
    ];
    final hasBp = e.systolic != null;
    return ChunkyTile(
      framed: false,
      leading: CategoryAvatar(
        icon: e.weight != null && hasBp
            ? Icons.monitor_heart_rounded
            : hasBp
            ? Icons.favorite_rounded
            : Icons.monitor_weight_rounded,
        color: hasBp ? GhinaColors.red.base : GhinaColors.green.base,
        size: 40,
      ),
      title: Fmt.relativeDay(e.date),
      subtitle: parts.join(' · '),
      trailing: cat == null
          ? null
          : ChunkyPill(
              label: cat.label.split(' · ').last,
              color: bpSwatch(cat),
              soft: true,
              uppercase: false,
            ),
      showChevron: cat == null,
      onTap: () => context.push('/health/${e.id}'),
    );
  }
}
