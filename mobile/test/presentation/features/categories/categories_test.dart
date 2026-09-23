import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../transactions/_feature_harness.dart';

Future<List<TxCategory>> allCats(WidgetTester tester, ProviderContainer c) =>
    real(tester, () => c.read(watchCategoriesUseCaseProvider)().first);

void main() {
  setUpAll(loadFonts);

  testWidgets('empty: seeds the default categories', (tester) async {
    final c = makeContainer();
    await pumpApp(tester, c, '/categories');
    expect(find.text('Belum ada kategori pengeluaran'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('category-seed')));
    await settle(tester);
    expect(find.text('Food & Drink'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    await tester.tap(find.text('Pemasukan'));
    await settle(tester);
    expect(find.text('Salary'), findsOneWidget);
    expect((await allCats(tester, c)).length, defaultCategories.length);
    await tearDownApp(tester, c);
  });

  testWidgets('create: validation, then saves with icon & color', (
    tester,
  ) async {
    final c = makeContainer();
    await pumpApp(tester, c, '/categories/new');
    await tester.tap(find.byKey(const ValueKey('category-save')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kasih nama dulu, ya'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('category-name')),
        matching: find.byType(TextField),
      ),
      'Kopi',
    );
    await tester.tap(find.bySemanticsLabel('coffee'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('category-save')));
    await settle(tester);
    final cats = await allCats(tester, c);
    expect(cats.single.name, 'Kopi');
    expect(cats.single.icon, 'coffee');
    expect(cats.single.type, CategoryType.expense);
    await tearDownApp(tester, c);
  });

  testWidgets('edit loads the category and deletes it after confirm', (
    tester,
  ) async {
    final c = makeContainer();
    final cat = await real(
      tester,
      () async => (await c.read(createCategoryProvider)(
        const CategoryInput(
          name: 'Gaji',
          type: CategoryType.income,
          icon: 'briefcase',
          color: '#22c55e',
        ),
      )).valueOrThrow,
    );
    await pumpApp(tester, c, '/categories/${cat.id}');
    expect(find.text('Edit kategori'), findsOneWidget);
    expect(find.text('Gaji'), findsWidgets);
    await scrollTo(tester, find.byKey(const ValueKey('category-delete')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('category-delete')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('tanpa kategori'), findsOneWidget);
    await tester.tap(find.text('HAPUS'));
    await settle(tester);
    expect(await allCats(tester, c), isEmpty);
    await tearDownApp(tester, c);
  });
}
