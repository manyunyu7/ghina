import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/food/pages/food_form_page.dart';
import 'package:ghina/presentation/features/food/pages/food_page.dart';
import 'package:go_router/go_router.dart';

import '../profile/_harness.dart';

final _routes = [
  GoRoute(path: '/food', builder: (_, _) => const FoodPage()),
  GoRoute(path: '/food/new', builder: (_, _) => const FoodFormPage()),
  GoRoute(
    path: '/food/:id',
    builder: (_, s) => FoodFormPage(id: s.pathParameters['id']),
  ),
];

FoodLog _log(
  String id,
  String name,
  DateTime date, {
  MealType? meal,
  int? kcal,
  String? note,
}) => FoodLog(
  id: id,
  date: date,
  name: name,
  meal: meal,
  calories: kcal,
  note: note,
  createdAt: date,
  updatedAt: date,
);

void main() {
  testWidgets('empty state invites the first log', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/food', routes: _routes);
    expect(find.text('Belum ada catatan makan'), findsOneWidget);
    await tester.tap(find.text('CATAT MAKANAN'));
    await settle(tester);
    expect(find.text('Catat makanan'), findsOneWidget); // form app bar
    await drain(tester);
  });

  testWidgets('list groups days with calories and meal chips', (tester) async {
    final h = Harness();
    h.food.s.put(
      _log(
        'a',
        'Nasi goreng',
        harnessNow.subtract(const Duration(hours: 3)),
        meal: MealType.breakfast,
        kcal: 450,
      ),
    );
    h.food.s.put(
      _log(
        'b',
        'Soto ayam',
        harnessNow.subtract(const Duration(hours: 1)),
        meal: MealType.lunch,
        kcal: 350,
        note: 'Enak banget',
      ),
    );
    h.food.s.put(
      _log(
        'c',
        'Martabak',
        harnessNow.subtract(const Duration(days: 1)),
        meal: MealType.snack,
        kcal: 600,
      ),
    );
    await pumpScreen(tester, h, location: '/food', routes: _routes);

    expect(find.text('Nasi goreng'), findsOneWidget);
    expect(find.text('Soto ayam'), findsOneWidget);
    expect(find.text('Hari ini'), findsOneWidget);
    expect(find.text('Kemarin'), findsOneWidget);
    expect(find.text('800 kkal'), findsWidgets); // today total
    expect(find.text('Enak banget'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('form shows a friendly error when the name is empty', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/food/new', routes: _routes);
    await tester.tap(find.text('SIMPAN'));
    await settle(tester, 3);
    expect(find.text('Isi nama makanannya dulu ya'), findsOneWidget);
    expect(h.food.s.items, isEmpty);
    await drain(tester);
  });

  testWidgets('submitting the form logs food and pops back', (tester) async {
    final h = Harness();
    await pumpScreen(tester, h, location: '/food/new', routes: _routes);
    await tester.enterText(
      find.byKey(const ValueKey('name')).first,
      'Gado-gado',
    );
    await tester.enterText(find.byKey(const ValueKey('calories')).first, '420');
    await tester.tap(find.text('SIMPAN'));
    await settle(tester, 20);
    await drain(tester);
    expect(h.food.s.items.values.single.name, 'Gado-gado');
    expect(h.food.s.items.values.single.calories, 420);
    expect(h.food.s.items.values.single.meal, MealType.lunch); // noon guess
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('edit mode loads the log and deletes after confirming', (
    tester,
  ) async {
    final h = Harness();
    h.food.s.put(
      _log('x', 'Bakso', harnessNow, meal: MealType.dinner, kcal: 500),
    );
    await pumpScreen(tester, h, location: '/food/x', routes: _routes);
    expect(find.text('Ubah catatan makan'), findsOneWidget);
    expect(find.text('Bakso'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);

    await tester.tap(find.byTooltip('Hapus'));
    await settle(tester, 5);
    expect(find.text('Hapus catatan makan?'), findsOneWidget);
    await tester.tap(find.text('HAPUS'));
    await settle(tester, 5);
    expect(h.food.s.items, isEmpty);
    await drain(tester);
    expect(find.text('HOME'), findsOneWidget);
  });
}
