// Renders the launcher icon (and optionally the web logo) from the in-app
// mascot so they always match it. Opt-in (not part of the normal suite):
//   GHINA_ICON_OUT=assets/icon flutter test test/tool/app_icon_render_test.dart
//   GHINA_WEB_ICON_OUT=/tmp/web flutter test test/tool/app_icon_render_test.dart
// App icon: resize assets/icon/icon.png (opaque) into ios/…/AppIcon.appiconset
// and android mipmap-*/ic_launcher.png, icon_foreground.png into
// drawable-*/ic_launcher_foreground.png (108dp canvas) with `sips`; the adaptive
// background is [iconBackground] in values/ic_launcher_background.xml.
// Web: copy icon.png → src/app/icon.png, apple-icon.png → src/app/apple-icon.png,
// logo.png → public/logo.png, and pack favicon-16/32.png into src/app/favicon.ico.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

const _out = String.fromEnvironment('GHINA_ICON_OUT');
const _webOut = String.fromEnvironment('GHINA_WEB_ICON_OUT');

/// Background of the icon: sky blue, so the green money tree pops like a tree
/// against a clear sky (and stays distinct on light and dark home screens).
const iconBackground = Color(0xFF1CB0F6);

Future<void> _render(
  WidgetTester tester,
  Widget child,
  String path, {
  double size = 1024,
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = Size(size, size);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: size, child: child),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path)..createSync(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Widget _mascot(double size) => Center(
  child: MascotView(
    mood: MascotMood.happy,
    size: size,
    animate: false,
    showShadow: false,
  ),
);

/// Rounded app tile with the mascot (web favicon / `icon.png`).
Widget _tile(double size, double mascot) => ClipRRect(
  borderRadius: BorderRadius.circular(size * 0.225),
  child: ColoredBox(color: iconBackground, child: _mascot(mascot)),
);

String _env(String define, String name) =>
    define.isNotEmpty ? define : Platform.environment[name] ?? '';

void main() {
  final out = _env(_out, 'GHINA_ICON_OUT');
  final web = _env(_webOut, 'GHINA_WEB_ICON_OUT');

  testWidgets('render app icon', (tester) async {
    // Full-bleed square: iOS icon + legacy Android icon.
    await _render(
      tester,
      ColoredBox(color: iconBackground, child: _mascot(800)),
      '$out/icon.png',
    );
    // Adaptive-icon foreground: transparent, mascot inside the 66% safe zone.
    await _render(tester, _mascot(610), '$out/icon_foreground.png');
    addTearDown(tester.view.reset);
  }, skip: out.isEmpty);

  testWidgets('render web icons', (tester) async {
    // Favicon / icon.png: rounded tile, mascot large so it reads at 16–32px.
    await _render(tester, _tile(512, 470), '$web/icon.png', size: 512);
    await _render(tester, _tile(32, 31), '$web/favicon-32.png', size: 32);
    await _render(tester, _tile(16, 16), '$web/favicon-16.png', size: 16);
    // apple-touch-icon: opaque full-bleed square (iOS rounds it).
    await _render(
      tester,
      ColoredBox(color: iconBackground, child: _mascot(150)),
      '$web/apple-icon.png',
      size: 180,
    );
    // In-page brand mark: transparent mascot.
    await _render(tester, _mascot(256), '$web/logo.png', size: 256);
    addTearDown(tester.view.reset);
  }, skip: web.isEmpty);
}
