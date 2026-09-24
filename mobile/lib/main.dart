import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/formatters.dart';
import 'di/di.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Fmt.initFormatting();
  runApp(ProviderScope(
    overrides: [...gameOverrides, ...reminderOverrides],
    child: const GhinaApp(),
  ));
}
