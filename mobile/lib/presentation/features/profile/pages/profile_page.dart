import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/game/game.dart' hide MascotMood;
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/session_controller.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/game_visuals.dart';
import '../widgets/streak_calendar.dart';

/// "Profil" tab: who you are in the game — level, XP, streak calendar, daily
/// goal, stats, badges — plus links to every other feature.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(syncNowProvider)();
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context, 'Belum bisa sinkron. Cek koneksi kamu, ya.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final snap = ref.watch(gameSnapshotProvider);
    return Scaffold(
      backgroundColor: g.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(context, ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.md,
              GhinaSpace.page,
              120,
            ),
            children: [
              const _Header(),
              const SizedBox(height: 20),
              ...switch (snap) {
                AsyncData(:final value) => _content(context, value),
                AsyncError() => [
                  ErrorRetry(
                    compact: true,
                    onRetry: () => ref.invalidate(gameSnapshotProvider),
                  ),
                ],
                _ => const [_ProfileSkeleton()],
              },
              const SizedBox(height: 28),
              const SectionHeader(title: 'Kelola'),
              const _Menu(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, GameSnapshot s) {
    final sum = s.summary;
    return [
      PopIn(child: _LevelCard(level: sum.level)),
      const SizedBox(height: 14),
      _StatsGrid(snapshot: s),
      const SizedBox(height: 28),
      const SectionHeader(title: 'Streak'),
      _StreakCard(summary: sum),
      const SizedBox(height: 14),
      _GoalCard(goal: sum.goal),
      const SizedBox(height: 28),
      SectionHeader(
        title: 'Pencapaian',
        subtitle:
            '${s.achievements.unlockedCount} dari ${s.achievements.total} lencana terbuka',
        actionLabel: 'Lihat semua',
        onAction: () => context.push('/achievements'),
      ),
      _AchievementsPreview(state: s.achievements),
    ];
  }
}

// ---------------------------------------------------------------- header

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final user = ref.watch(currentUserProvider);
    final name = user?.name?.trim().isNotEmpty == true
        ? user!.name!.trim()
        : (user?.displayName ?? 'Kamu');
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final color = CategoryColors.forKey(user?.id ?? name);
    final sw = ChunkySwatch.fromColor(color);
    return Row(
      children: [
        Container(
          width: 68,
          height: 72,
          decoration: BoxDecoration(color: sw.edge, shape: BoxShape.circle),
          alignment: Alignment.topCenter,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: sw.base,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 3,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: GhinaType.h1.w(900).copyWith(color: sw.on, fontSize: 30),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GhinaType.h1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (user?.email != null)
                Text(
                  user!.email!,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ChunkyIconButton(
          icon: Icons.settings_rounded,
          tooltip: 'Pengaturan',
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- level

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level});

  final LevelInfo level;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      tinted: GhinaColors.purple,
      child: Row(
        children: [
          LevelBadge(level: level.level, size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LEVEL ${level.level}',
                  style: GhinaType.overline.copyWith(
                    color: g.isDark
                        ? GhinaColors.purple.base
                        : GhinaColors.purple.edge,
                  ),
                ),
                Text(level.title, style: GhinaType.h2.w(900)),
                const SizedBox(height: 8),
                ChunkyProgressBar(
                  value: level.progress,
                  height: 20,
                  color: GhinaColors.yellow,
                  label:
                      '${Fmt.number(level.xpIntoLevel)} / ${Fmt.number(level.xpForLevel)} XP',
                ),
                const SizedBox(height: 6),
                Text(
                  level.nextTitle == null
                      ? '${Fmt.number(level.xpToNext)} XP lagi ke level ${level.level + 1}'
                      : '${Fmt.number(level.xpToNext)} XP lagi ke level ${level.level + 1} · ${level.nextTitle}',
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

// ---------------------------------------------------------------- stats

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.snapshot});

  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot.summary;
    final st = snapshot.stats;
    final tiles = [
      StatTile(
        icon: Icons.bolt_rounded,
        value: Fmt.number(s.totalXp),
        label: 'Total XP',
        color: GhinaColors.yellow,
      ),
      StatTile(
        icon: Icons.local_fire_department_rounded,
        value: '${s.streak.longest} hari',
        label: 'Rekor streak',
        color: GhinaColors.orange,
      ),
      StatTile(
        icon: Icons.school_rounded,
        value: Fmt.number(st[AchievementMetric.lessonsCompleted]),
        label: 'Pelajaran',
        color: GhinaColors.green,
      ),
      StatTile(
        icon: Icons.receipt_long_rounded,
        value: Fmt.number(st[AchievementMetric.totalTransactions]),
        label: 'Transaksi',
        color: GhinaColors.blue,
      ),
    ];
    return Column(
      children: [
        for (var r = 0; r < 2; r++) ...[
          if (r > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[r * 2]),
                const SizedBox(width: 12),
                Expanded(child: tiles[r * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- streak

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.summary});

  final GameSummary summary;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final st = summary.streak;
    final next = st.nextMilestone;
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StreakFlame(
                count: st.current,
                active: st.current > 0,
                size: 48,
                showCount: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${st.current} hari streak',
                      style: GhinaType.h2
                          .w(900)
                          .copyWith(
                            color: st.current > 0
                                ? GhinaColors.orange.base
                                : g.textPrimary,
                          ),
                    ),
                    Text(
                      st.atRisk
                          ? 'Catat transaksi hari ini biar streak aman!'
                          : st.current == 0
                          ? 'Catat transaksi hari ini buat mulai streak baru.'
                          : next != null
                          ? '${next - st.current} hari lagi ke target $next hari 🔥'
                          : 'Legendaris! Pertahankan terus.',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FreezeRow(held: st.freezesHeld, max: st.maxFreezes),
          const SizedBox(height: 16),
          StreakCalendar(today: summary.today),
        ],
      ),
    );
  }
}

class _FreezeRow extends StatelessWidget {
  const _FreezeRow({required this.held, required this.max});

  final int held;
  final int max;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final blue = GhinaColors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: blue.tint(g.brightness),
        borderRadius: GhinaRadii.rLg,
      ),
      child: Row(
        children: [
          for (var i = 0; i < max; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.ac_unit_rounded,
                size: 22,
                color: i < held ? blue.base : g.border,
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              held == 0
                  ? 'Belum punya streak freeze. Dapatkan tiap streak 7 hari.'
                  : '$held streak freeze siap jaga streak kamu.',
              style: GhinaType.bodyS
                  .w(700)
                  .copyWith(color: g.isDark ? blue.base : blue.edge),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- daily goal

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final DailyGoalProgress goal;

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final picked = await showChunkyBottomSheet<DailyGoalLevel>(
      context,
      title: 'Target harian',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in DailyGoalLevel.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: QuizOptionTile(
                label: '${l.label} · ${l.target} aktivitas',
                icon: l == goal.level
                    ? Icons.check_circle_rounded
                    : Icons.flag_rounded,
                state: l == goal.level
                    ? QuizOptionState.selected
                    : QuizOptionState.idle,
                onTap: () => Navigator.of(c).pop(l),
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == goal.level) return;
    await ref.read(gameActionsProvider).setDailyGoal(picked);
    if (context.mounted) {
      showToastBadge(
        context,
        message: 'Target diubah ke ${picked.label}. Semangat!',
        icon: Icons.flag_rounded,
        color: GhinaColors.green,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    return ChunkyCard(
      onTap: () => _change(context, ref),
      child: Row(
        children: [
          ProgressRing(
            value: goal.fraction,
            size: 64,
            stroke: 8,
            color: goal.isMet ? GhinaColors.green : GhinaColors.yellow,
            child: goal.isMet
                ? Icon(
                    Icons.check_rounded,
                    color: GhinaColors.green.base,
                    size: 30,
                  )
                : Text(
                    '${goal.done}/${goal.target}',
                    style: GhinaType.h3.w(900),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Target harian', style: GhinaType.h3),
                Text(
                  '${goal.level.label} · ${goal.target} aktivitas sehari',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  goal.isMet
                      ? 'Tercapai hari ini! 🎉'
                      : 'Kurang ${goal.remaining} lagi, gas!',
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(
                        color: goal.isMet
                            ? GhinaColors.green.base
                            : GhinaColors.orange.base,
                      ),
                ),
              ],
            ),
          ),
          Icon(Icons.edit_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- achievements

class _AchievementsPreview extends StatelessWidget {
  const _AchievementsPreview({required this.state});

  final AchievementsState state;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    // Unlocked (best tiers first), then the closest ones to unlocking.
    final unlocked = state.unlocked
      ..sort((a, b) => b.def.tier.index.compareTo(a.def.tier.index));
    final locked = state.items.where((a) => !a.unlocked).toList()
      ..sort((a, b) => b.fraction.compareTo(a.fraction));
    final show = [...unlocked, ...locked].take(4).toList();
    return ChunkyCard(
      onTap: () => context.push('/achievements'),
      child: Row(
        children: [
          for (final a in show)
            Expanded(
              child: Column(
                children: [
                  AchievementBadge(def: a.def, unlocked: a.unlocked, size: 54),
                  const SizedBox(height: 6),
                  Text(
                    a.def.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(
                      color: a.unlocked ? g.textPrimary : g.textMuted,
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

// ---------------------------------------------------------------- menu

class _Menu extends StatelessWidget {
  const _Menu();

  static const _items = <(IconData, Color, String, String, String)>[
    (
      Icons.account_balance_wallet_rounded,
      Color(0xFF1CB0F6),
      'Dompet',
      'Saldo & transfer',
      '/wallets',
    ),
    (
      Icons.category_rounded,
      Color(0xFFCE82FF),
      'Kategori',
      'Atur kategori transaksi',
      '/categories',
    ),
    (
      Icons.pie_chart_rounded,
      Color(0xFF58CC02),
      'Anggaran',
      'Budget bulanan',
      '/budgets',
    ),
    (
      Icons.autorenew_rounded,
      Color(0xFFFF9600),
      'Langganan',
      'Tagihan rutin',
      '/subscriptions',
    ),
    (
      Icons.insights_rounded,
      Color(0xFF2B70C9),
      'Proyeksi',
      'Rencana bulan depan',
      '/forecast',
    ),
    (
      Icons.bar_chart_rounded,
      Color(0xFFFF4B4B),
      'Laporan',
      'Pemasukan vs pengeluaran',
      '/reports',
    ),
    (
      Icons.mosque_rounded,
      Color(0xFF14B8A6),
      'Salat',
      'Lima waktu harian',
      '/prayers',
    ),
    (
      Icons.monitor_heart_rounded,
      Color(0xFFEC4899),
      'Kesehatan',
      'Berat & tekanan darah',
      '/health',
    ),
    (
      Icons.restaurant_rounded,
      Color(0xFFF59E0B),
      'Catatan makan',
      'Foto & kalori',
      '/food',
    ),
    (
      Icons.settings_rounded,
      Color(0xFF777777),
      'Pengaturan',
      'Mata uang, sinkron, akun',
      '/settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (icon, color, title, sub, path) in _items)
            ChunkyTile(
              framed: false,
              leading: CategoryAvatar(icon: icon, color: color, size: 40),
              title: title,
              subtitle: sub,
              showChevron: true,
              onTap: () => context.push(path),
            ),
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Skeleton(height: 120, radius: 20),
      SizedBox(height: 14),
      Row(
        children: [
          Expanded(child: Skeleton(height: 96, radius: 16)),
          SizedBox(width: 12),
          Expanded(child: Skeleton(height: 96, radius: 16)),
        ],
      ),
      SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: Skeleton(height: 96, radius: 16)),
          SizedBox(width: 12),
          Expanded(child: Skeleton(height: 96, radius: 16)),
        ],
      ),
      SizedBox(height: 28),
      Skeleton(height: 380, radius: 20),
    ],
  );
}
