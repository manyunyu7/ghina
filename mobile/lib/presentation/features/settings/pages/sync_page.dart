import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/sync_status_provider.dart';
import '../../shell/sync_indicator.dart';

/// Sync status, last sync, pending changes, last error, and a manual "sync now".
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  bool _running = false;

  Future<void> _syncNow() async {
    setState(() => _running = true);
    final r = await ref.read(syncNowProvider)();
    if (!mounted) return;
    setState(() => _running = false);
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Semua udah sinkron! ✨',
          icon: Icons.cloud_done_rounded,
          color: GhinaColors.green,
        );
      case Err(:final failure):
        showToastBadge(
          context,
          message: failure is NetworkFailure
              ? 'Belum ada internet. Nanti aku coba lagi otomatis 👍'
              : failure.message,
          icon: failure is NetworkFailure
              ? Icons.cloud_off_rounded
              : Icons.error_outline_rounded,
          color: failure is NetworkFailure ? GhinaColors.gray : GhinaColors.red,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(syncStatusProvider);
    final s = async.value ?? SyncStatus.initial;
    final now = ref.watch(clockProvider).now();
    final busy = _running || s.isSyncing;

    final (mood, title, message, color) = switch (s.phase) {
      SyncPhase.syncing => (
        MascotMood.thinking,
        'Lagi sinkron…',
        'Bentar ya, aku lagi nyocokin datamu sama server.',
        GhinaColors.blue,
      ),
      SyncPhase.offline => (
        MascotMood.sleeping,
        'Kamu lagi offline',
        'Santai, semua catatanmu tersimpan di HP. Begitu online, aku kirim otomatis 👍',
        GhinaColors.gray,
      ),
      SyncPhase.error => (
        MascotMood.sad,
        'Sinkron lagi bermasalah',
        'Ada yang belum berhasil dikirim. Aku bakal coba lagi, atau kamu bisa coba sekarang.',
        GhinaColors.red,
      ),
      SyncPhase.idle when s.hasPending => (
        MascotMood.happy,
        'Ada yang nunggu dikirim',
        'Perubahan terbarumu bakal segera dikirim ke server.',
        GhinaColors.orange,
      ),
      SyncPhase.idle => (
        MascotMood.excited,
        'Semua aman & sinkron!',
        'Datamu di HP dan di web udah sama persis.',
        GhinaColors.green,
      ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Sinkronisasi')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  GhinaSpace.lg,
                  GhinaSpace.page,
                  GhinaSpace.xl,
                ),
                children: [
                  ChunkyCard(
                    tinted: color,
                    padding: const EdgeInsets.all(GhinaSpace.xl),
                    child: Column(
                      children: [
                        MascotView(mood: mood, size: 110),
                        GhinaSpace.gapMd,
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GhinaType.h2.copyWith(color: g.textPrimary),
                        ),
                        GhinaSpace.gapSm,
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: GhinaType.body.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                        GhinaSpace.gapLg,
                        SyncBadge(
                          state: syncIndicatorOf(s),
                          pendingCount: s.pendingCount,
                        ),
                      ],
                    ),
                  ),
                  GhinaSpace.gapLg,
                  ChunkyCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        ChunkyTile(
                          framed: false,
                          dense: true,
                          leading: CategoryAvatar(
                            icon: Icons.schedule_rounded,
                            color: GhinaColors.blue.base,
                            size: 40,
                            soft: true,
                          ),
                          title: syncAgo(s.lastSyncAt, now),
                          subtitle: 'Terakhir sinkron',
                        ),
                        ChunkyTile(
                          framed: false,
                          dense: true,
                          leading: CategoryAvatar(
                            icon: Icons.upload_rounded,
                            color:
                                (s.hasPending
                                        ? GhinaColors.orange
                                        : GhinaColors.green)
                                    .base,
                            size: 40,
                            soft: true,
                          ),
                          title: s.hasPending
                              ? '${s.pendingCount} perubahan'
                              : 'Semua terkirim',
                          subtitle: 'Nunggu dikirim ke server',
                        ),
                      ],
                    ),
                  ),
                  if (s.lastSyncAt != null) ...[
                    GhinaSpace.gapSm,
                    Text(
                      'Sinkron terakhir: ${Fmt.dateShortWeekday(s.lastSyncAt!)}, ${Fmt.time(s.lastSyncAt!)}',
                      textAlign: TextAlign.center,
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ],
                  if (s.lastError != null && s.lastError!.isNotEmpty) ...[
                    GhinaSpace.gapLg,
                    ChunkyCard(
                      tinted: GhinaColors.red,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: GhinaColors.red.base,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Error terakhir',
                                  style: GhinaType.h3.copyWith(
                                    color: g.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.lastError!,
                                  style: GhinaType.bodyS.copyWith(
                                    color: g.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  GhinaSpace.gapXl,
                  const SectionHeader(title: 'Gimana cara kerjanya?'),
                  const _HowItWorks(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                0,
                GhinaSpace.page,
                GhinaSpace.lg,
              ),
              child: ChunkyButton(
                label: 'Sinkron sekarang',
                icon: Icons.sync_rounded,
                loading: busy,
                onPressed: busy ? null : _syncNow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget point(
      IconData icon,
      ChunkySwatch color,
      String title,
      String body,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryAvatar(icon: icon, color: color.base, size: 40, soft: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GhinaType.h3.copyWith(color: g.textPrimary)),
                Text(
                  body,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ChunkyCard(
      child: Column(
        children: [
          point(
            Icons.phone_iphone_rounded,
            GhinaColors.green,
            'Tersimpan di HP dulu',
            'Semua yang kamu catat langsung tersimpan di HP, bahkan tanpa internet.',
          ),
          point(
            Icons.cloud_sync_rounded,
            GhinaColors.blue,
            'Dikirim otomatis',
            'Pas online, perubahanmu dikirim ke server dan data dari web ikut diunduh.',
          ),
          point(
            Icons.devices_rounded,
            GhinaColors.purple,
            'Sama di semua perangkat',
            'Buka Ghina di web atau HP lain, datanya tetap sama.',
          ),
        ],
      ),
    );
  }
}
