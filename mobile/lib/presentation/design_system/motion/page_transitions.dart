import 'package:flutter/material.dart';

import '../tokens/dimens.dart';

/// Android/desktop page transition: a short slide-up + fade. Registered in
/// [GhinaTheme]'s `pageTransitionsTheme`, so GoRouter pages get it for free.
class GhinaPageTransitionsBuilder extends PageTransitionsBuilder {
  const GhinaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ghinaSlideUpTransition(animation, child);
  }
}

/// Slide-up + fade used by [GhinaPageTransitionsBuilder] and [ghinaPageRoute].
Widget ghinaSlideUpTransition(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: GhinaMotion.standard,
  );
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    ),
  );
}

/// A route with Ghina's slide-up transition (for GoRouter use
/// `CustomTransitionPage(transitionsBuilder: (c, a, s, child) => ghinaSlideUpTransition(a, child))`).
///
/// ```dart
/// Navigator.of(context).push(ghinaPageRoute((_) => const DetailPage()));
/// ```
Route<T> ghinaPageRoute<T>(
  WidgetBuilder builder, {
  bool fullscreenDialog = false,
}) {
  return PageRouteBuilder<T>(
    fullscreenDialog: fullscreenDialog,
    transitionDuration: GhinaMotion.medium,
    reverseTransitionDuration: GhinaMotion.fast,
    pageBuilder: (c, _, _) => builder(c),
    transitionsBuilder: (_, a, _, child) => ghinaSlideUpTransition(a, child),
  );
}
