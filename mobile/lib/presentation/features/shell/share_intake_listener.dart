import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/services.dart';
import '../../state/platform/platform_state.dart';
import '../../state/session_controller.dart';
import '../notes/share/share_note_flow.dart';

/// The share-target hook of the signed-in shell (`lib/data/platform/README.md`
/// → "Wiring hook"): creates `pendingShareProvider` at startup, turns each
/// pending share into a note and opens the "Catatan dari share" sheet — one at
/// a time, oldest first. The shell only exists after login + onboarding, so a
/// cold-start share waits in the queue until then. Sign-out drops the queue.
class ShareIntakeListener extends ConsumerStatefulWidget {
  const ShareIntakeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShareIntakeListener> createState() =>
      _ShareIntakeListenerState();
}

class _ShareIntakeListenerState extends ConsumerState<ShareIntakeListener> {
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<SharedPayload?>(
      pendingShareProvider,
      (_, next) => _maybeHandle(),
      fireImmediately: true,
    );
    ref.listenManual(currentUserProvider, (_, user) {
      if (user != null) _maybeHandle();
    });
    ref.listenManual(sessionControllerProvider, (_, s) {
      if (s is SignedOut) ref.read(pendingShareProvider.notifier).clear();
    });
  }

  void _maybeHandle() {
    if (_handling) return;
    if (ref.read(pendingShareProvider) == null) return;
    if (ref.read(currentUserProvider) == null) return; // keep it pending
    _handling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  Future<void> _drain() async {
    try {
      while (mounted && ref.read(currentUserProvider) != null) {
        final p = ref.read(pendingShareProvider.notifier).take();
        if (p == null) break;
        await handleSharedPayload(context, ref, p);
      }
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
