import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../state/sync_status_provider.dart';

/// Bottom-navigation shell around the four tabs, with the big center "+" that opens
/// the new-transaction flow. Shows a slim offline strip above the bar while the
/// sync engine can't reach the server.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: navigationShell),
          const OfflineBanner(),
        ],
      ),
      bottomNavigationBar: ChunkyNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        onCenterTap: () => context.push('/transactions/new'),
        items: const [
          ChunkyNavItem(icon: Icons.home_rounded, label: 'Beranda'),
          ChunkyNavItem(icon: Icons.receipt_long_rounded, label: 'Transaksi'),
          ChunkyNavItem(icon: Icons.school_rounded, label: 'Belajar'),
          ChunkyNavItem(icon: Icons.person_rounded, label: 'Profil'),
        ],
      ),
    );
  }
}

/// "Mode offline" strip; collapses to nothing while online. Tap → `/sync`.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider).value;
    final offline = s?.phase == SyncPhase.offline;
    final g = context.ghina;
    final pending = s?.pendingCount ?? 0;
    return AnimatedSize(
      duration: GhinaMotion.medium,
      curve: GhinaMotion.standard,
      child: !offline
          ? const SizedBox(width: double.infinity)
          : Material(
              color: GhinaColors.gray.tint(g.brightness),
              child: InkWell(
                onTap: () => context.push('/sync'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: g.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pending > 0
                              ? 'Mode offline · $pending perubahan nunggu disinkron'
                              : 'Mode offline · catatanmu tetap aman di HP 👍',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.bodyS
                              .w(700)
                              .copyWith(color: g.textSecondary),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: g.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
