import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' show DailyGoalLevel;
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/session_controller.dart';
import '../../settings/widgets/daily_goal_picker.dart';

/// First-run flow: mascot welcome → daily goal → categories + first wallet → done.
/// Finishing calls `completeOnboarding`, and the router moves on to `/home`.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const _steps = 4;
  int _step = 0;
  DailyGoalLevel _goal = DailyGoalLevel.defaultLevel;
  bool _finishing = false;

  void _next() => setState(() => _step = (_step + 1).clamp(0, _steps - 1));
  void _back() => setState(() => _step = (_step - 1).clamp(0, _steps - 1));

  Future<void> _saveGoal() async {
    await ref.read(gameActionsProvider).setDailyGoal(_goal);
    _next();
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await ref.read(gameActionsProvider).completeOnboarding(goal: _goal);
    // The router redirects to /home once onboardingDoneProvider flips.
    if (mounted) setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(currentUserProvider)?.displayName ?? 'Kamu';
    final body = switch (_step) {
      0 => _WelcomeStep(key: const ValueKey(0), name: name, onNext: _next),
      1 => _GoalStep(
        key: const ValueKey(1),
        goal: _goal,
        onChanged: (l) => setState(() => _goal = l),
        onNext: _saveGoal,
      ),
      2 => _SetupStep(key: const ValueKey(2), onNext: _next),
      _ => _DoneStep(
        key: const ValueKey(3),
        goal: _goal,
        loading: _finishing,
        onFinish: _finish,
      ),
    };

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, GhinaSpace.page, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: _step > 0 && _step < _steps - 1
                          ? IconButton(
                              tooltip: 'Kembali',
                              onPressed: _back,
                              icon: const Icon(Icons.arrow_back_rounded),
                            )
                          : null,
                    ),
                    Expanded(
                      child: ChunkyProgressBar(
                        value: (_step + 1) / _steps,
                        height: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: GhinaMotion.medium,
                  switchInCurve: GhinaMotion.standard,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    ),
                  ),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrollable step content with the CTA pinned at the bottom.
class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.children,
    required this.button,
    this.center = false,
  });

  final List<Widget> children;
  final Widget button;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.xl,
                GhinaSpace.page,
                GhinaSpace.lg,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: c.maxHeight - GhinaSpace.xl - GhinaSpace.lg,
                ),
                child: Column(
                  mainAxisAlignment: center
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            0,
            GhinaSpace.page,
            GhinaSpace.lg,
          ),
          child: button,
        ),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({super.key, required this.name, required this.onNext});

  final String name;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget point(IconData icon, ChunkySwatch color, String text) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.md),
      child: Row(
        children: [
          CategoryAvatar(icon: icon, color: color.base, size: 40, soft: true),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GhinaType.body.w(700).copyWith(color: g.textPrimary),
            ),
          ),
        ],
      ),
    );
    return _StepLayout(
      center: true,
      button: ChunkyButton(label: 'Mulai', onPressed: onNext),
      children: [
        const Center(child: MascotView(mood: MascotMood.waving, size: 150)),
        GhinaSpace.gapLg,
        Text(
          'Hai $name, aku Ghina! 🌱',
          textAlign: TextAlign.center,
          style: GhinaType.h1.copyWith(color: g.textPrimary),
        ),
        GhinaSpace.gapSm,
        Text(
          'Aku bakal nemenin kamu ngatur uang, sedikit demi sedikit tiap hari.',
          textAlign: TextAlign.center,
          style: GhinaType.bodyL.copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapXl,
        point(
          Icons.edit_note_rounded,
          GhinaColors.green,
          'Catat transaksi dalam hitungan detik',
        ),
        point(
          Icons.local_fire_department_rounded,
          GhinaColors.orange,
          'Jaga streak & kumpulkan XP',
        ),
        point(
          Icons.school_rounded,
          GhinaColors.purple,
          'Belajar finansial lewat pelajaran singkat',
        ),
      ],
    );
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({
    super.key,
    required this.goal,
    required this.onChanged,
    required this.onNext,
  });

  final DailyGoalLevel goal;
  final ValueChanged<DailyGoalLevel> onChanged;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    return _StepLayout(
      button: ChunkyButton(label: 'Lanjut', onPressed: onNext),
      children: [
        MascotSpeech(
          mood: MascotMood.thinking,
          mascotSize: 80,
          message:
              'Mau serajin apa kamu tiap hari? Bisa diganti kapan aja kok.',
        ),
        GhinaSpace.gapXl,
        DailyGoalPicker(selected: goal, onChanged: onChanged),
        GhinaSpace.gapMd,
        Text(
          'Aktivitas = catat transaksi, sholat, kesehatan, makanan, atau pelajaran.',
          textAlign: TextAlign.center,
          style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
        ),
      ],
    );
  }
}

/// Makes sure the account has categories and at least one wallet. Syncs first so a
/// fresh server account's defaults arrive before anything is seeded locally.
class _SetupStep extends ConsumerStatefulWidget {
  const _SetupStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<_SetupStep> createState() => _SetupStepState();
}

class _SetupStepState extends ConsumerState<_SetupStep> {
  bool _preparing = true;
  bool _creating = false;
  final _walletName = TextEditingController(text: 'Dompet Tunai');
  final _balance = TextEditingController();
  WalletType _type = WalletType.cash;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _walletName.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      await ref.read(syncNowProvider)().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline or slow: fall back to whatever is local.
    }
    if (!mounted) return;
    try {
      final cats = await ref.read(watchCategoriesProvider(null).future);
      if (cats.isEmpty && mounted) {
        await ref.read(seedDefaultCategoriesProvider)();
      }
    } catch (_) {
      // Shown as "belum siap" below; the user can still continue.
    }
    if (mounted) setState(() => _preparing = false);
  }

  Future<void> _createWallet() async {
    final name = _walletName.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Kasih nama dompetnya dulu, ya');
      return;
    }
    setState(() {
      _nameError = null;
      _creating = true;
    });
    final r = await ref.read(createWalletProvider)(
      WalletInput(
        name: name,
        type: _type,
        currency: ref.read(currencyProvider),
        color: switch (_type) {
          WalletType.bank => '#3b82f6',
          WalletType.ewallet => '#8b5cf6',
          _ => '#22c55e',
        },
        initialBalance: Fmt.parseAmount(_balance.text) ?? 0,
      ),
    );
    if (!mounted) return;
    setState(() => _creating = false);
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Dompet siap! 👛',
          icon: Icons.check_circle_rounded,
          color: GhinaColors.green,
        );
      case Err(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final cats = ref.watch(watchCategoriesProvider(null));
    final wallets = ref.watch(watchWalletsProvider);
    final catCount = cats.value?.length ?? 0;
    final walletList = wallets.value ?? const <Wallet>[];
    final hasWallet = walletList.isNotEmpty;
    final ready = !_preparing && catCount > 0 && hasWallet;

    Widget check(
      String title,
      String subtitle, {
      required bool done,
      required bool busy,
    }) => ChunkyTile(
      title: title,
      subtitle: subtitle,
      leading: busy
          ? const SizedBox(
              width: 40,
              height: 40,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          : CategoryAvatar(
              icon: done ? Icons.check_rounded : Icons.more_horiz_rounded,
              color: done ? GhinaColors.green.base : GhinaColors.gray.base,
              size: 40,
            ),
    );

    final showWalletForm = !_preparing && !hasWallet;

    return _StepLayout(
      button: showWalletForm
          ? ChunkyButton(
              label: 'Buat dompet',
              loading: _creating,
              onPressed: _creating ? null : _createWallet,
            )
          : ChunkyButton(
              label: 'Lanjut',
              onPressed: ready ? widget.onNext : null,
            ),
      children: [
        MascotSpeech(
          mood: _preparing ? MascotMood.thinking : MascotMood.happy,
          mascotSize: 80,
          message: _preparing
              ? 'Bentar ya, aku lagi nyiapin semuanya…'
              : hasWallet
              ? 'Semua siap! Kategori & dompet udah beres 👌'
              : 'Satu lagi: kamu biasa nyimpen uang di mana?',
        ),
        GhinaSpace.gapXl,
        check(
          'Kategori',
          _preparing
              ? 'Lagi disiapkan…'
              : (catCount > 0
                    ? '$catCount kategori siap dipakai'
                    : 'Belum ada kategori'),
          done: catCount > 0,
          busy: _preparing,
        ),
        GhinaSpace.gapMd,
        check(
          'Dompet',
          _preparing
              ? 'Lagi dicek…'
              : hasWallet
              ? walletList.map((w) => w.name).join(', ')
              : 'Bikin dompet pertamamu di bawah',
          done: hasWallet,
          busy: _preparing,
        ),
        if (showWalletForm) ...[
          GhinaSpace.gapXl,
          ChunkyTextField(
            key: const ValueKey('wallet-name'),
            label: 'Nama dompet',
            controller: _walletName,
            errorText: _nameError,
            prefixIcon: Icons.account_balance_wallet_rounded,
          ),
          GhinaSpace.gapLg,
          Text(
            'Jenis',
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
          GhinaSpace.gapSm,
          ChunkyChoiceChips<WalletType>(
            options: [
              for (final t in const [
                WalletType.cash,
                WalletType.bank,
                WalletType.ewallet,
              ])
                ChunkyChoice(
                  value: t,
                  label: t.label,
                  icon: GhinaIcons.walletType(t.wire),
                ),
            ],
            selected: {_type},
            onChanged: (s) => setState(() => _type = s.first),
          ),
          GhinaSpace.gapLg,
          ChunkyTextField(
            key: const ValueKey('wallet-balance'),
            label: 'Saldo sekarang (opsional)',
            hint: '0',
            controller: _balance,
            keyboardType: TextInputType.number,
            prefixIcon: Icons.payments_rounded,
          ),
        ],
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({
    super.key,
    required this.goal,
    required this.loading,
    required this.onFinish,
  });

  final DailyGoalLevel goal;
  final bool loading;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final (icon, color) = dailyGoalLook(goal);
    return _StepLayout(
      center: true,
      button: ChunkyButton(
        label: 'Ayo mulai!',
        loading: loading,
        onPressed: loading ? null : onFinish,
      ),
      children: [
        const Center(child: MascotView(mood: MascotMood.excited, size: 150)),
        GhinaSpace.gapLg,
        Text(
          'Kamu siap! 🎉',
          textAlign: TextAlign.center,
          style: GhinaType.h1.copyWith(color: g.textPrimary),
        ),
        GhinaSpace.gapSm,
        Text(
          'Catat transaksi pertamamu hari ini buat mulai streak.',
          textAlign: TextAlign.center,
          style: GhinaType.bodyL.copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapXl,
        ChunkyCard(
          tinted: color,
          child: Row(
            children: [
              Icon(icon, color: color.base, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target harian: ${goal.label}',
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    Text(
                      '${goal.target} aktivitas sehari',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
