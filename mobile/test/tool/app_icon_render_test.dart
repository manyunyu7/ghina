// Renders the launcher icon from the in-app mascot so the icon always matches it.
// Opt-in (not part of the normal suite):
//   GHINA_ICON_OUT=assets/icon flutter test test/tool/app_icon_render_test.dart
// then: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

const _out = String.fromEnvironment('GHINA_ICON_OUT');

/// Background of the icon. Light "feather" green keeps the green mascot readable.
const iconBackground = Color(0xFFD7FFB8);

Future<void> _render(WidgetTester tester, Widget child, String path, {double size = 1024}) async {
  final key = GlobalKey();
  tester.view.physicalSize = Size(size, size);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(key: key, child: SizedBox.square(dimension: size, child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path)..createSync(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Widget _mascot(double size) => Center(
      child: MascotView(mood: MascotMood.happy, size: size, animate: false, showShadow: false),
    );

void main() {
  final out = _out.isNotEmpty ? _out : Platform.environment['GHINA_ICON_OUT'] ?? '';

  testWidgets('render app icon', (tester) async {
    // Full-bleed square: iOS icon + legacy Android icon.
    await _render(tester, ColoredBox(color: iconBackground, child: _mascot(760)), '$out/icon.png');
    // Adaptive-icon foreground: transparent, mascot inside the 66% safe zone.
    await _render(tester, _mascot(600), '$out/icon_foreground.png');
    addTearDown(tester.view.reset);
  }, skip: out.isEmpty);
}
