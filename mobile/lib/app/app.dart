import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/design_system/design_system.dart';
import 'router.dart';

class GhinaApp extends ConsumerWidget {
  const GhinaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Ghina',
      debugShowCheckedModeBanner: false,
      theme: GhinaTheme.light(),
      darkTheme: GhinaTheme.dark(),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
