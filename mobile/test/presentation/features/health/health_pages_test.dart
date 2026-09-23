import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/health/pages/health_form_page.dart';
import 'package:ghina/presentation/features/health/pages/health_page.dart';
import 'package:go_router/go_router.dart';

import '../profile/_harness.dart';

final _routes = [
  GoRoute(path: '/health', builder: (_, _) => const HealthPage()),
  GoRoute(path: '/health/new', builder: (_, _) => const HealthFormPage()),
  GoRoute(
    path: '/health/:id',
    builder: (_, s) => HealthFormPage(id: s.pathParameters['id']),
  ),
];

HealthEntry _e(
  String id,
  int daysAgo, {
  double? w,
  int? s,
  int? d,
  int? p,
  String? note,
}) {
  final date = harnessNow.subtract(Duration(days: daysAgo));
  return HealthEntry(
    id: id,
    date: date,
    weight: w,
    systolic: s,
    diastolic: d,
    pulse: p,
    note: note,
    createdAt: date,
    updatedAt: date,
  );
}

void main() {
  testWidgets('empty state offers weight and blood pressure', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/health', routes: _routes);
    expect(find.text('Belum ada catatan kesehatan'), findsOneWidget);
    expect(find.text('CATAT BERAT BADAN'), findsOneWidget);
    expect(find.text('CATAT TEKANAN DARAH'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('shows latest readings, BP category, charts and history', (
    tester,
  ) async {
    final h = Harness();
    h.health.s.put(_e('1', 0, w: 68.5, s: 132, d: 84, p: 75, note: 'Pagi'));
    h.health.s.put(_e('2', 2, w: 69.2));
    h.health.s.put(_e('3', 4, s: 118, d: 76));
    await pumpScreen(tester, h, location: '/health', routes: _routes);

    expect(find.text('68,5'), findsOneWidget);
    expect(find.text('132/84'), findsOneWidget);
    expect(find.text('Tinggi · Tahap 1'), findsWidgets);
    expect(find.byType(LineChart), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('Riwayat'), 300);
    expect(find.textContaining('68,5 kg'), findsWidgets);
    await drain(tester);
  });

  testWidgets('weight form validates before saving', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/health/new', routes: _routes);
    await tester.tap(find.text('SIMPAN'));
    await settle(tester, 3);
    expect(find.text('Isi berat badanmu dulu ya'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('weight')).first, '900');
    await tester.tap(find.text('SIMPAN'));
    await settle(tester, 3);
    expect(
      find.text('Berat badan sepertinya salah (1–500 kg)'),
      findsOneWidget,
    );
    expect(h.health.s.items, isEmpty);
    await drain(tester);
  });

  testWidgets('blood pressure mode classifies live and saves', (tester) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/health/new?mode=bp',
      routes: _routes,
    );
    expect(find.byKey(const ValueKey('weight')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('systolic')).first, '130');
    await tester.enterText(find.byKey(const ValueKey('diastolic')).first, '85');
    await tester.pump();
    expect(find.text('Kategori: Tinggi · Tahap 1'), findsOneWidget);
    await tester.tap(find.text('SIMPAN'));
    await settle(tester, 20);
    await drain(tester);
    final saved = h.health.s.items.values.single;
    expect(saved.systolic, 130);
    expect(saved.diastolic, 85);
    expect(saved.weight, isNull);
    // First health entry ever unlocks a badge.
    expect(find.text('Lencana baru! 🎉'), findsOneWidget);
    expect(find.text('Cek Kesehatan'), findsOneWidget);
    await tester.tap(find.text('MANTAP!'));
    await settle(tester, 10);
    await drain(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('edit mode loads the entry and can delete it', (tester) async {
    final h = Harness();
    h.health.s.put(_e('x', 1, w: 70, s: 120, d: 80));
    await pumpScreen(tester, h, location: '/health/x', routes: _routes);
    expect(find.text('Ubah catatan'), findsOneWidget);
    String field(String key) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;
    expect(field('weight'), '70');
    expect(field('systolic'), '120');
    expect(field('diastolic'), '80');
    expect(find.text('KEDUANYA'), findsNothing); // segment labels aren't caps
    expect(find.text('Keduanya'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus'));
    await settle(tester, 5);
    await tester.tap(find.text('HAPUS'));
    await settle(tester, 5);
    expect(h.health.s.items, isEmpty);
    await drain(tester);
  });
}
