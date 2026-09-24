import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_providers.dart';

/// Calls [onRoute] for every tapped reminder (including the one that launched
/// the app — delivered once the listener mounts).
///
/// Place it inside the router scope, e.g. in `MaterialApp.router(builder: ...)`:
/// ```dart
/// builder: (context, child) => NotificationRouteListener(
///   onRoute: (route) => ref.read(routerProvider).push(route),
///   child: child!,
/// ),
/// ```
/// Auth redirects still apply (a signed-out user lands on the login screen).
class NotificationRouteListener extends ConsumerStatefulWidget {
  const NotificationRouteListener({
    super.key,
    required this.onRoute,
    required this.child,
  });

  final void Function(String route) onRoute;
  final Widget child;

  @override
  ConsumerState<NotificationRouteListener> createState() =>
      _NotificationRouteListenerState();
}

class _NotificationRouteListenerState
    extends ConsumerState<NotificationRouteListener> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(notificationRoutesProvider)
        .listen((r) => widget.onRoute(r));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
