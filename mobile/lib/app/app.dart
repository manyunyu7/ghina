import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/design_system/design_system.dart';
import '../presentation/features/shell/notification_navigation.dart';
import '../presentation/state/session_controller.dart';
import 'router.dart';

/// Locations where a tapped reminder must wait (auth / splash / onboarding).
const _notReadyPaths = {'/splash', '/login', '/register', '/onboarding'};

class GhinaApp extends ConsumerWidget {
  const GhinaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ghina',
      debugShowCheckedModeBanner: false,
      theme: GhinaTheme.light(),
      darkTheme: GhinaTheme.dark(),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      // Reminder taps open `/tasks/<id>` (cold start included: waits until
      // signed in and past splash/onboarding).
      builder: (context, child) => NotificationRouteGate(
        router: router,
        canOpen: () =>
            ref.read(sessionControllerProvider) is SignedIn &&
            !_notReadyPaths.contains(
              router.routerDelegate.currentConfiguration.uri.path,
            ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
