import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../state/sync_status_provider.dart';

/// Maps the sync engine phase to the design-system badge state.
SyncIndicatorState syncIndicatorOf(SyncStatus s) => switch (s.phase) {
  SyncPhase.idle => SyncIndicatorState.synced,
  SyncPhase.syncing => SyncIndicatorState.syncing,
  SyncPhase.offline => SyncIndicatorState.offline,
  SyncPhase.error => SyncIndicatorState.error,
};

/// "Barusan", "5 menit lalu", "2 jam lalu", "3 hari lalu" or "Belum pernah".
String syncAgo(DateTime? t, DateTime now) {
  if (t == null) return 'Belum pernah';
  final d = now.difference(t);
  if (d.inSeconds < 60) return 'Barusan';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

/// The live [SyncBadge]; tapping opens `/sync`.
class LiveSyncBadge extends ConsumerWidget {
  const LiveSyncBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider).value ?? SyncStatus.initial;
    return SyncBadge(
      state: syncIndicatorOf(s),
      pendingCount: s.pendingCount,
      compact: compact,
      onTap: () => context.push('/sync'),
    );
  }
}
