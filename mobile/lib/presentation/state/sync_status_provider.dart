import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/di.dart';
import '../../domain/entities/sync_status.dart';

/// Live sync status: phase (idle/syncing/offline/error), last sync time, pending count
/// and last error. Use `ref.watch(syncStatusProvider).value ?? SyncStatus.initial`.
final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(watchSyncStatusUseCaseProvider)(),
);
