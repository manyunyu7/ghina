import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' show DailyGoalLevel;
import '../../../../domain/usecases/usecases.dart' show supportedCurrencies;
import '../../../design_system/design_system.dart';
import '../../../design_system/gallery/ui_gallery_screen.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/session_controller.dart';
import '../../../state/sync_status_provider.dart';
import '../../shell/sync_indicator.dart';
import '../widgets/daily_goal_picker.dart';

/// App version shown in the footer (`--dart-define=APP_VERSION=…`; pubspec default).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// Profile, preferences, daily goal, data & sync, and sign out.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _name;
  String? _currency;
  bool _saving = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    _name = TextEditingController(text: u?.name ?? '');
    _currency = u?.currency;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _dirty(AppUser? u) =>
      u != null &&
      (_name.text.trim() != (u.name ?? '').trim() || _currency != u.currency);

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Namanya jangan kosong, ya');
      return;
    }
    if (name.length > 60) {
      setState(() => _nameError = 'Maksimal 60 karakter');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    final r = await ref
        .read(sessionControllerProvider.notifier)
        .updateProfile(name: name, currency: _currency);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Profil tersimpan!',
          icon: Icons.check_circle_rounded,
          color: GhinaColors.green,
        );
      case Err(:final failure):
        _snack(
          failure is NetworkFailure
              ? 'Ubah profil butuh internet. Coba lagi pas online, ya.'
              : failure.message,
        );
    }
  }

  Future<void> _setGoal(DailyGoalLevel level) async {
    await ref.read(gameActionsProvider).setDailyGoal(level);
    if (!mounted) return;
    showToastBadge(
      context,
      message: 'Target harian: ${level.label} (${level.target}/hari)',
      icon: Icons.flag_rounded,
      color: GhinaColors.blue,
    );
  }

  Future<void> _resetData(int pending) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Unduh ulang semua data?',
      message: pending > 0
          ? 'Data di HP dihapus lalu diunduh lagi dari server. $pending perubahan yang belum tersinkron bakal hilang.'
          : 'Data di HP dihapus lalu diunduh lagi dari server. Data di server aman.',
      confirmLabel: 'Unduh ulang',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(resetLocalDataProvider)();
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Data segar dari server ✨',
          icon: Icons.cloud_done_rounded,
          color: GhinaColors.green,
        );
      case Err(:final failure):
        _snack(
          failure is NetworkFailure
              ? 'Butuh internet buat unduh ulang data.'
              : failure.message,
        );
    }
  }

  Future<void> _resetGame() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Reset progres game?',
      message:
          'Pelajaran, target harian, dan lencana yang sudah dilihat di HP ini direset. '
          'Kamu juga bakal diajak ulang perkenalan awal (onboarding). '
          'Transaksi dan datamu nggak tersentuh.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(gameActionsProvider).resetLocalProgress();
  }

  Future<void> _signOut(int pending) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Yakin mau keluar?',
      message: pending > 0
          ? 'Ada $pending perubahan yang belum tersinkron dan bakal hilang kalau kamu keluar sekarang.'
          : 'Data di HP ini akan dihapus. Semua tetap aman di server kok.',
      confirmLabel: 'Keluar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final user = ref.watch(currentUserProvider);
    final goal = ref.watch(dailyGoalLevelProvider).value;
    final summary = ref.watch(gameSummaryProvider).value;
    final sync = ref.watch(syncStatusProvider).value ?? SyncStatus.initial;
    final pending = sync.pendingCount;
    final dirty = _dirty(user);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.md,
            GhinaSpace.page,
            GhinaSpace.xxl,
          ),
          children: [
            _ProfileHeader(
              user: user,
              level: summary?.level.level,
              title: summary?.level.title,
            ),
            GhinaSpace.gapXl,
            const SectionHeader(
              title: 'Profil',
              subtitle: 'Perlu internet buat menyimpan',
            ),
            ChunkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChunkyTextField(
                    key: const ValueKey('settings-name'),
                    label: 'Nama tampilan',
                    hint: 'Nama panggilanmu',
                    controller: _name,
                    errorText: _nameError,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    prefixIcon: Icons.person_rounded,
                    onChanged: (_) => setState(() {}),
                  ),
                  GhinaSpace.gapMd,
                  Text(
                    'Mata uang utama',
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                  GhinaSpace.gapSm,
                  ChunkyChoiceChips<String>(
                    scrollable: true,
                    options: [
                      for (final c in supportedCurrencies)
                        ChunkyChoice(value: c, label: c),
                    ],
                    selected: {?_currency},
                    onChanged: (s) => setState(() => _currency = s.first),
                  ),
                  GhinaSpace.gapSm,
                  Text(
                    'Dipakai untuk total dan dompet baru.',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                  GhinaSpace.gapLg,
                  ChunkyButton(
                    label: 'Simpan profil',
                    size: ChunkyButtonSize.medium,
                    expand: true,
                    loading: _saving,
                    onPressed: dirty && !_saving ? _saveProfile : null,
                  ),
                ],
              ),
            ),
            GhinaSpace.gapXl,
            const SectionHeader(
              title: 'Target harian',
              subtitle: 'Berapa aktivitas yang mau kamu kejar tiap hari?',
            ),
            DailyGoalPicker(selected: goal, onChanged: _setGoal),
            GhinaSpace.gapXl,
            const SectionHeader(title: 'Data & sinkronisasi'),
            ChunkyCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  ChunkyTile(
                    framed: false,
                    title: 'Status sinkron',
                    subtitle:
                        'Terakhir: ${syncAgo(sync.lastSyncAt, ref.watch(clockProvider).now())}',
                    leading: CategoryAvatar(
                      icon: Icons.cloud_sync_rounded,
                      color: GhinaColors.blue.base,
                      size: 40,
                    ),
                    trailing: SyncBadge(
                      state: syncIndicatorOf(sync),
                      pendingCount: pending,
                      compact: true,
                    ),
                    showChevron: true,
                    onTap: () => context.push('/sync'),
                  ),
                  ChunkyTile(
                    framed: false,
                    title: 'Unduh ulang data',
                    subtitle: 'Hapus data di HP & ambil lagi dari server',
                    leading: CategoryAvatar(
                      icon: Icons.cloud_download_rounded,
                      color: GhinaColors.orange.base,
                      size: 40,
                    ),
                    onTap: () => _resetData(pending),
                  ),
                  ChunkyTile(
                    framed: false,
                    title: 'Reset progres game',
                    subtitle: 'Pelajaran, target harian & onboarding di HP ini',
                    leading: CategoryAvatar(
                      icon: Icons.restart_alt_rounded,
                      color: GhinaColors.purple.base,
                      size: 40,
                    ),
                    onTap: _resetGame,
                  ),
                  if (kDebugMode)
                    ChunkyTile(
                      framed: false,
                      title: 'UI Gallery',
                      subtitle: 'Khusus debug',
                      leading: CategoryAvatar(
                        icon: Icons.palette_rounded,
                        color: GhinaColors.pink.base,
                        size: 40,
                      ),
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const UiGalleryScreen(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            GhinaSpace.gapXl,
            ChunkyButton(
              label: 'Keluar',
              variant: ChunkyButtonVariant.danger,
              icon: Icons.logout_rounded,
              onPressed: () => _signOut(pending),
            ),
            GhinaSpace.gapLg,
            Center(
              child: Text(
                'Ghina v$appVersion · dibuat dengan 💚',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, this.level, this.title});

  final AppUser? user;
  final int? level;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final name = user?.name?.trim().isNotEmpty == true
        ? user!.name!.trim()
        : (user?.displayName ?? 'Kamu');
    final initials = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final color = ChunkySwatch.fromColor(
      CategoryColors.forKey(user?.email ?? name),
    );
    return ChunkyCard(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.base,
              shape: BoxShape.circle,
              border: Border.all(color: color.edge, width: 3),
            ),
            child: Text(
              initials,
              style: GhinaType.h2.w(900).copyWith(color: color.on),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h2.copyWith(color: g.textPrimary),
                ),
                if (user?.email != null)
                  Text(
                    user!.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                if (level != null) ...[
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ChunkyPill(
                      label: 'Level $level · $title',
                      color: GhinaColors.purple,
                      soft: true,
                      icon: Icons.military_tech_rounded,
                      uppercase: false,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
