import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

bool _fontsLoaded = false;

/// Loads Nunito (and Material Icons when the SDK font is found) so golden
/// shots render real glyphs instead of Ahem boxes.
Future<void> loadGhinaFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final nunito = File('assets/fonts/Nunito.ttf');
  if (nunito.existsSync()) {
    final loader = FontLoader('Nunito')
      ..addFont(Future.value(ByteData.sublistView(nunito.readAsBytesSync())));
    await loader.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null)
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
      break;
    }
  }
}

/// Wraps [child] in a MaterialApp with the Ghina theme.
Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: dark ? GhinaTheme.dark() : GhinaTheme.light(),
  home: Scaffold(body: child),
);

/// Directory for screenshots, from `GHINA_SHOTS_DIR` (null = don't write).
String? get shotsDir => Platform.environment['GHINA_SHOTS_DIR'];

/// Captures the [RepaintBoundary] found by [key] into `<shotsDir>/<name>.png`.
Future<void> saveShot(
  WidgetTester tester,
  Key key,
  String name, {
  double pixelRatio = 2,
}) async {
  final dir = shotsDir;
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$dir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
