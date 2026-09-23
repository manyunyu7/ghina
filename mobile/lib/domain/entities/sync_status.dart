enum SyncPhase {
  /// Nothing running; last sync (if any) succeeded.
  idle,

  /// A push/pull is in progress.
  syncing,

  /// Last attempt couldn't reach the server; will retry automatically.
  offline,

  /// Last attempt failed for another reason (see [SyncStatus.lastError]).
  error,
}

/// Snapshot of the sync engine for the UI.
final class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.lastSyncAt,
    this.pendingCount = 0,
    this.lastError,
  });

  static const initial = SyncStatus(phase: SyncPhase.idle);

  final SyncPhase phase;

  /// When the last successful sync finished.
  final DateTime? lastSyncAt;

  /// Local changes waiting to be pushed.
  final int pendingCount;

  /// Last error message (e.g. a rejected mutation), if any.
  final String? lastError;

  bool get isSyncing => phase == SyncPhase.syncing;
  bool get hasPending => pendingCount > 0;

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    int? pendingCount,
    String? lastError,
    bool clearError = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    pendingCount: pendingCount ?? this.pendingCount,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.lastSyncAt == lastSyncAt &&
      other.pendingCount == pendingCount &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(phase, lastSyncAt, pendingCount, lastError);

  @override
  String toString() =>
      'SyncStatus(${phase.name}, pending: $pendingCount, last: $lastSyncAt, err: $lastError)';
}
