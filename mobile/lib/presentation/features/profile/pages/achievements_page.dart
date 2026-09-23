import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/game/game.dart' hide MascotMood;
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/game_visuals.dart';

enum _Filter { all, unlocked, locked }

/// Grid of every badge: unlocked ones in their tier colour, locked ones grey
/// with a progress bar. Newly unlocked badges get celebrated once, then are
/// marked as seen.
class AchievementsPage extends ConsumerStatefulWidget {
  const AchievementsPage({super.key});

  @override
  ConsumerState<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends ConsumerState<AchievementsPage> {
  _Filter _filter = _Filter.all;
  bool _celebrated = false;

  void _maybeCelebrate(AchievementsState s) {
    if (_celebrated) return;
    _celebrated = true;
    final fresh = s.newlyUnlocked;
    if (fresh.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Same once-only path as every other reward moment (marks them seen).
      await presentNewAchievements(context, fresh);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(achievementsProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Pencapaian')),
      body: switch (async) {
        AsyncData(:final value) => _body(value),
        AsyncError() => ErrorRetry(
          onRetry: () => ref.invalidate(gameSnapshotProvider),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(GhinaSpace.page),
          child: SkeletonList(count: 5),
        ),
      },
    );
  }

  Widget _body(AchievementsState s) {
    _maybeCelebrate(s);
    final g = context.ghina;
    final items = switch (_filter) {
      _Filter.all => s.items,
      _Filter.unlocked => s.unlocked,
      _Filter.locked => s.items.where((a) => !a.unlocked).toList(),
    };
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            8,
            GhinaSpace.page,
            0,
          ),
          sliver: SliverList.list(
            children: [
              ChunkyCard(
                tinted: GhinaColors.yellow,
                child: Row(
                  children: [
                    const MascotView(mood: MascotMood.excited, size: 72),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.unlockedCount} dari ${s.total} lencana',
                            style: GhinaType.h2.w(900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.unlockedCount == 0
                                ? 'Yuk buka lencana pertamamu!'
                                : s.unlockedCount == s.total
                                ? 'Semua lencana terkumpul. Luar biasa!'
                                : 'Terus kumpulkan, kamu makin jago!',
                            style: GhinaType.bodyS.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ChunkyProgressBar(
                            value: s.total == 0 ? 0 : s.unlockedCount / s.total,
                            color: GhinaColors.yellow,
                            height: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ChunkyChoiceChips<_Filter>(
                options: const [
                  ChunkyChoice(value: _Filter.all, label: 'Semua'),
                  ChunkyChoice(value: _Filter.unlocked, label: 'Terbuka'),
                  ChunkyChoice(value: _Filter.locked, label: 'Terkunci'),
                ],
                selected: {_filter},
                onChanged: (v) {
                  if (v.isNotEmpty) setState(() => _filter = v.first);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              compact: true,
              title: _filter == _Filter.unlocked
                  ? 'Belum ada lencana terbuka'
                  : 'Semua sudah terbuka!',
              message: _filter == _Filter.unlocked
                  ? 'Catat transaksi atau selesaikan pelajaran buat membuka yang pertama.'
                  : 'Kamu keren banget 🎉',
              mood: _filter == _Filter.unlocked
                  ? MascotMood.thinking
                  : MascotMood.excited,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              0,
              GhinaSpace.page,
              40,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => PopIn(
                  delay: Duration(milliseconds: 30 * (i % 12)),
                  child: _BadgeCell(
                    item: items[i],
                    onTap: () => _showDetail(items[i]),
                  ),
                ),
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }

  void _showDetail(AchievementProgress a) {
    showChunkyBottomSheet<void>(
      context,
      showClose: true,
      builder: (c) {
        final g = c.ghina;
        final sw = tierSwatch(a.def.tier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AchievementBadge(def: a.def, unlocked: a.unlocked, size: 96),
            const SizedBox(height: 14),
            Text(a.def.title, style: GhinaType.h1, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            ChunkyPill(
              label: tierLabel(a.def.tier),
              color: sw,
              soft: !a.unlocked,
            ),
            const SizedBox(height: 10),
            Text(
              a.def.description,
              textAlign: TextAlign.center,
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: 18),
            if (a.unlocked)
              ChunkyCard(
                tinted: GhinaColors.green,
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: GhinaColors.green.base),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Terbuka! Kamu hebat.',
                        style: GhinaType.body.w(800),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              ChunkyProgressBar(
                value: a.fraction,
                height: 22,
                color: sw,
                label:
                    '${Fmt.number(a.clampedCurrent)} / ${Fmt.number(a.target)}',
              ),
              const SizedBox(height: 8),
              Text(
                'Sedikit lagi, kamu pasti bisa!',
                style: GhinaType.bodyS.copyWith(color: g.textMuted),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BadgeCell extends StatelessWidget {
  const _BadgeCell({required this.item, required this.onTap});

  final AchievementProgress item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      tinted: item.unlocked ? tierSwatch(item.def.tier) : null,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AchievementBadge(
                def: item.def,
                unlocked: item.unlocked,
                size: 58,
              ),
              if (item.isNew)
                const Positioned(
                  top: -6,
                  right: -12,
                  child: ChunkyPill(label: 'Baru', color: GhinaColors.red),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              item.def.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS
                  .w(800)
                  .copyWith(
                    color: item.unlocked ? g.textPrimary : g.textSecondary,
                  ),
            ),
          ),
          if (!item.unlocked) ...[
            ChunkyProgressBar(
              value: item.fraction,
              height: 8,
              color: tierSwatch(item.def.tier),
              animate: false,
            ),
            const SizedBox(height: 4),
            Text(
              '${Fmt.number(item.clampedCurrent)}/${Fmt.number(item.target)}',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ] else
            Text(
              tierLabel(item.def.tier),
              style: GhinaType.caption.copyWith(
                color: g.isDark
                    ? tierSwatch(item.def.tier).base
                    : tierSwatch(item.def.tier).edge,
              ),
            ),
        ],
      ),
    );
  }
}
