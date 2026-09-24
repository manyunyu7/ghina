import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/game/task_game_providers.dart';
import '../../../state/session_controller.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/home_sections.dart';
import '../widgets/home_tasks.dart';

/// Beranda: game stats, mascot, daily goal, money overview, shortcuts, and what's
/// coming up. Also presents pending reward celebrations whenever it's on screen.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _celebrating = false;

  bool get _visible =>
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  void _maybeCelebrate() {
    if (_celebrating) return;
    _celebrating = true;
    unawaited(_runCelebrations());
  }

  Future<void> _runCelebrations() async {
    try {
      // Let pushed screens finish closing (and possibly celebrate themselves) first.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted || !_visible) return;
      await presentPendingCelebrations(context);
    } finally {
      _celebrating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final now = ref.watch(clockProvider).now();
    final user = ref.watch(currentUserProvider);
    final currency = ref.watch(currencyProvider);
    final game = ref.watch(gameSummaryProvider);
    final dash = ref.watch(watchDashboardProvider);
    final summary = game.value;
    // Records yesterday's "FIRE kosong" snapshot on the first open of a day.
    ref.listen(fireClearRecorderProvider, (_, _) {});

    if (summary != null && summary.celebrations.isNotEmpty && _visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeCelebrate();
      });
    }

    final hour = now.hour;
    final greeting = hour < 11
        ? 'Selamat pagi'
        : hour < 15
        ? 'Selamat siang'
        : hour < 19
        ? 'Selamat sore'
        : 'Selamat malam';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            HomeStatsBar(summary: summary),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => pullToSync(context, ref),
                child: ListView(
                  key: const PageStorageKey('home-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    GhinaSpace.lg,
                    GhinaSpace.page,
                    GhinaSpace.xxl,
                  ),
                  children: [
                    Text(
                      '$greeting, ${user?.displayName ?? 'kamu'}!',
                      style: GhinaType.h1.copyWith(color: g.textPrimary),
                    ),
                    Text(
                      Fmt.dateFull(now),
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                    GhinaSpace.gapLg,
                    ..._gameSection(game),
                    GhinaSpace.gapLg,
                    ..._moneySection(dash, currency, now),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _gameSection(AsyncValue game) {
    if (game.hasError && game.value == null) {
      return [
        MascotSpeech(
          mood: MascotMood.sad,
          mascotSize: 84,
          message:
              'Ups, progresmu belum kebaca. Tarik ke bawah buat coba lagi, ya.',
        ),
      ];
    }
    final s = ref.watch(gameSummaryProvider).value;
    if (s == null) {
      return const [
        Row(
          children: [
            Skeleton.circle(size: 84),
            SizedBox(width: 12),
            Expanded(child: Skeleton(height: 64, radius: 16)),
          ],
        ),
        SizedBox(height: 16),
        Skeleton(height: 108, radius: 20),
      ];
    }
    final line = ref.watch(homeMascotProvider);
    return [
      HomeMascot(
        mood: line?.mood ?? s.mood,
        message: line?.message ?? s.message,
      ),
      GhinaSpace.gapLg,
      DailyGoalCard(summary: s),
    ];
  }

  List<Widget> _moneySection(
    AsyncValue<DashboardSummary> dash,
    String currency,
    DateTime now,
  ) {
    final d = dash.value;
    if (d == null && dash.hasError) {
      return [
        EmptyState(
          compact: true,
          mood: MascotMood.sad,
          title: 'Ups, ada yang salah',
          message: 'Data keuanganmu gagal dimuat. Coba lagi, yuk.',
          actionLabel: 'Coba lagi',
          onAction: () => ref.invalidate(watchDashboardProvider),
        ),
        GhinaSpace.gapXl,
        const HomeTasksSection(),
      ];
    }
    if (d == null) {
      return const [
        Skeleton(height: 104, radius: 20),
        SizedBox(height: 12),
        Skeleton(height: 120, radius: 20),
        SizedBox(height: 24),
        HomeTasksSection(),
        SizedBox(height: 24),
        SkeletonList(count: 3),
      ];
    }

    final path = ref.watch(learnPathProvider).value;
    final hearts = ref.watch(gameSummaryProvider).value?.hearts;
    final budgets = ref
        .watch(watchBudgetMonthProvider(YearMonth.of(now)))
        .value;
    final subs = ref.watch(watchSubscriptionsProvider).value;
    final dueSoon = [
      for (final s in subs?.active ?? const <Subscription>[])
        if (s.daysUntilNext(now) <= 7) s,
    ]..sort((a, b) => a.daysUntilNext(now).compareTo(b.daysUntilNext(now)));

    return [
      BalanceCard(dash: d, currency: currency),
      GhinaSpace.gapMd,
      MonthFlowCard(dash: d, currency: currency),
      GhinaSpace.gapXl,
      const HomeTasksSection(),
      if (path != null) ...[GhinaSpace.gapLg, ContinueLearningCard(path: path)],
      GhinaSpace.gapXl,
      const SectionHeader(title: 'Menu'),
      const QuickActionsGrid(),
      if (d.spendingByCategory.isNotEmpty) ...[
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Pengeluaran bulan ini',
          actionLabel: 'Laporan',
          onAction: () => context.push('/reports'),
        ),
        SpendingCard(items: d.spendingByCategory, currency: currency),
      ],
      if (budgets != null) ...[
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Anggaran',
          actionLabel: budgets.items.isEmpty ? null : 'Lihat semua',
          onAction: budgets.items.isEmpty
              ? null
              : () => context.push('/budgets'),
        ),
        BudgetSnapshotCard(month: budgets, hearts: hearts, currency: currency),
      ],
      if (dueSoon.isNotEmpty) ...[
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Tagihan sebentar lagi',
          actionLabel: 'Langganan',
          onAction: () => context.push('/subscriptions'),
        ),
        UpcomingSubscriptionsCard(
          items: dueSoon.take(3).toList(),
          now: now,
          currency: currency,
        ),
      ],
      GhinaSpace.gapXl,
      SectionHeader(
        title: 'Transaksi terakhir',
        actionLabel: d.recent.isEmpty ? null : 'Lihat semua',
        onAction: d.recent.isEmpty ? null : () => context.go('/transactions'),
      ),
      if (d.recent.isEmpty)
        ChunkyCard(
          child: EmptyState(
            compact: true,
            mascotSize: 96,
            title: 'Belum ada transaksi',
            message: 'Catat yang pertama, yuk! Cuma 10 detik kok.',
            actionLabel: 'Catat sekarang',
            onAction: () => context.push('/transactions/new'),
          ),
        )
      else
        RecentTransactionsCard(
          items: d.recent.take(5).toList(),
          currency: currency,
          now: now,
        ),
    ];
  }
}
