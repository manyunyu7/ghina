import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../state/notifications/notification_route_listener.dart';

/// Opens routes of tapped reminders (`/tasks/<id>`) on [router], waiting until
/// [canOpen] is true (signed in and past splash/onboarding/login — e.g. a cold
/// start from a notification) before pushing. Only the latest pending route is
/// kept.
class NotificationRouteOpener {
  NotificationRouteOpener({required this.router, required this.canOpen});

  final GoRouter router;
  final bool Function() canOpen;
  String? _pending;
  bool _listening = false;

  void open(String route) {
    _pending = route;
    _flush();
  }

  void _flush() {
    final r = _pending;
    if (r == null) return _stopListening();
    if (!canOpen()) {
      if (!_listening) {
        router.routerDelegate.addListener(_flush);
        _listening = true;
      }
      return;
    }
    _pending = null;
    _stopListening();
    // Push after the current frame so a redirect in progress settles first.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => router.push(r))
      ..ensureVisualUpdate();
  }

  /// Re-checks a pending route (e.g. when the session changes).
  void retry() => _flush();

  void _stopListening() {
    if (!_listening) return;
    router.routerDelegate.removeListener(_flush);
    _listening = false;
  }

  void dispose() => _stopListening();
}

/// Wraps the app (inside `MaterialApp.router(builder:)`) and routes reminder
/// taps through a [NotificationRouteOpener].
class NotificationRouteGate extends StatefulWidget {
  const NotificationRouteGate({
    super.key,
    required this.router,
    required this.canOpen,
    required this.child,
  });

  final GoRouter router;
  final bool Function() canOpen;
  final Widget child;

  @override
  State<NotificationRouteGate> createState() => NotificationRouteGateState();
}

class NotificationRouteGateState extends State<NotificationRouteGate> {
  late NotificationRouteOpener _opener = _create();

  NotificationRouteOpener _create() => NotificationRouteOpener(
    router: widget.router,
    canOpen: () => widget.canOpen(),
  );

  /// Re-checks a pending route (call when the session / onboarding changes).
  void retry() => _opener.retry();

  @override
  void didUpdateWidget(NotificationRouteGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      _opener.dispose();
      _opener = _create();
    }
  }

  @override
  void dispose() {
    _opener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationRouteListener(
    onRoute: (r) => _opener.open(r),
    child: widget.child,
  );
}
