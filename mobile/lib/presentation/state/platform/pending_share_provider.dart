import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/share_intake.dart';
import 'platform_providers.dart';

/// Shares received from other apps that no screen has handled yet (FIFO).
/// `state` is the oldest pending payload, or null.
///
/// Wiring (app shell, once — see `lib/data/platform/README.md`):
/// ```dart
/// ref.listen<SharedPayload?>(pendingShareProvider, (_, next) {
///   if (next == null || !signedIn) return;
///   final payload = ref.read(pendingShareProvider.notifier).take()!;
///   // create the note (source: "share") and open the "from share" sheet
/// }, fireImmediately: true);
/// ```
class PendingShareController extends Notifier<SharedPayload?> {
  final _queue = <SharedPayload>[];

  @override
  SharedPayload? build() {
    final sub = ref.watch(shareIntakeProvider).payloads.listen((p) {
      if (p.isEmpty) return;
      _queue.add(p);
      if (ref.mounted) state = _queue.first;
    });
    ref.onDispose(sub.cancel);
    return _queue.isEmpty ? null : _queue.first;
  }

  /// Number of shares waiting (incl. [state]).
  int get pendingCount => _queue.length;

  /// Removes and returns the oldest pending share; the next one (if any)
  /// becomes the new state.
  SharedPayload? take() {
    if (_queue.isEmpty) return null;
    final p = _queue.removeAt(0);
    state = _queue.isEmpty ? null : _queue.first;
    return p;
  }

  /// Drops everything pending (e.g. on sign-out).
  void clear() {
    _queue.clear();
    state = null;
  }
}

/// Kept alive for the whole app session so a share arriving before the UI is
/// ready (cold start) is not lost.
final pendingShareProvider =
    NotifierProvider<PendingShareController, SharedPayload?>(
      PendingShareController.new,
    );
