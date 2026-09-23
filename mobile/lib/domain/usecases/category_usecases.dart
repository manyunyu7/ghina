import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

/// Curated category icon ids (web `CATEGORY_ICONS`, lucide names).
const categoryIcons = [
  'utensils',
  'shopping-cart',
  'shopping-bag',
  'car',
  'bus',
  'fuel',
  'home',
  'zap',
  'wifi',
  'phone',
  'heart-pulse',
  'pill',
  'graduation-cap',
  'book-open',
  'gamepad-2',
  'film',
  'music',
  'plane',
  'gift',
  'coffee',
  'dumbbell',
  'shirt',
  'baby',
  'dog',
  'briefcase',
  'landmark',
  'piggy-bank',
  'trending-up',
  'wallet',
  'banknote',
  'credit-card',
  'circle-dollar-sign',
  'receipt',
  'circle',
];

/// A default category definition.
typedef DefaultCategory = ({
  String name,
  String icon,
  String color,
  CategoryType type,
});

/// The web's default set (`DEFAULT_EXPENSE_CATEGORIES` + `DEFAULT_INCOME_CATEGORIES`).
/// Names are kept identical to the web so seeding stays idempotent across devices.
const List<DefaultCategory> defaultCategories = [
  (
    name: 'Food & Drink',
    icon: 'utensils',
    color: '#f97316',
    type: CategoryType.expense,
  ),
  (
    name: 'Groceries',
    icon: 'shopping-cart',
    color: '#22c55e',
    type: CategoryType.expense,
  ),
  (
    name: 'Transport',
    icon: 'car',
    color: '#3b82f6',
    type: CategoryType.expense,
  ),
  (
    name: 'Shopping',
    icon: 'shopping-bag',
    color: '#ec4899',
    type: CategoryType.expense,
  ),
  (
    name: 'Bills & Utilities',
    icon: 'zap',
    color: '#eab308',
    type: CategoryType.expense,
  ),
  (name: 'Housing', icon: 'home', color: '#8b5cf6', type: CategoryType.expense),
  (
    name: 'Health',
    icon: 'heart-pulse',
    color: '#ef4444',
    type: CategoryType.expense,
  ),
  (
    name: 'Entertainment',
    icon: 'film',
    color: '#06b6d4',
    type: CategoryType.expense,
  ),
  (
    name: 'Education',
    icon: 'graduation-cap',
    color: '#14b8a6',
    type: CategoryType.expense,
  ),
  (
    name: 'Salary',
    icon: 'briefcase',
    color: '#16a34a',
    type: CategoryType.income,
  ),
  (
    name: 'Business',
    icon: 'landmark',
    color: '#0ea5e9',
    type: CategoryType.income,
  ),
  (
    name: 'Investment',
    icon: 'trending-up',
    color: '#8b5cf6',
    type: CategoryType.income,
  ),
  (name: 'Gift', icon: 'gift', color: '#ec4899', type: CategoryType.income),
];

final class CategoryInput {
  const CategoryInput({
    required this.name,
    this.type = CategoryType.expense,
    this.color = '#6366f1',
    this.icon = 'circle',
  });

  final String name;
  final CategoryType type;

  /// `#rrggbb` (e.g. from [colorPalette]); invalid values fall back to the first palette color.
  final String color;

  /// Must be one of [categoryIcons]; anything else falls back to `circle`.
  final String icon;
}

TxCategory _build(
  String id,
  CategoryInput input,
  DateTime createdAt,
  DateTime now,
) => TxCategory(
  id: id,
  name: requireName(input.name),
  type: input.type,
  color: RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(input.color)
      ? input.color
      : colorPalette.first,
  icon: categoryIcons.contains(input.icon) ? input.icon : categoryIcons.last,
  createdAt: createdAt,
  updatedAt: now,
);

/// Categories sorted by name; optionally only one [type].
final class WatchCategories {
  const WatchCategories(this._repo);
  final CategoryRepository _repo;

  Stream<List<TxCategory>> call({CategoryType? type}) =>
      _repo.watchAll(type: type);
}

final class WatchCategory {
  const WatchCategory(this._repo);
  final CategoryRepository _repo;

  Stream<TxCategory?> call(String id) => _repo.watchById(id);
}

final class CreateCategory {
  const CreateCategory(this._repo, this._clock);
  final CategoryRepository _repo;
  final Clock _clock;

  Future<Result<TxCategory>> call(CategoryInput input) => guard(() async {
    final now = _clock.now();
    final c = _build(newId(), input, now, now);
    await _repo.save(c);
    return c;
  });
}

final class UpdateCategory {
  const UpdateCategory(this._repo, this._clock);
  final CategoryRepository _repo;
  final Clock _clock;

  Future<Result<TxCategory>> call(String id, CategoryInput input) =>
      guard(() async {
        final existing = await _repo.getById(id);
        if (existing == null) {
          throw const NotFoundFailure('Kategori tidak ditemukan');
        }
        final c = _build(id, input, existing.createdAt, _clock.now());
        await _repo.save(c);
        return c;
      });
}

/// Deletes the category; its transactions become uncategorized and its budgets are removed.
final class DeleteCategory {
  const DeleteCategory(this._repo);
  final CategoryRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

/// Adds the default categories whose names (case-insensitive) don't exist yet.
/// Returns how many were created. Idempotent.
final class SeedDefaultCategories {
  const SeedDefaultCategories(this._repo, this._uow, this._clock);
  final CategoryRepository _repo;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<int>> call() => guard(
    () => _uow.run(() async {
      final taken = (await _repo.getAll())
          .map((c) => c.name.toLowerCase())
          .toSet();
      final now = _clock.now();
      var created = 0;
      for (final d in defaultCategories) {
        if (taken.contains(d.name.toLowerCase())) continue;
        await _repo.save(
          TxCategory(
            id: newId(),
            name: d.name,
            type: d.type,
            color: d.color,
            icon: d.icon,
            createdAt: now,
            updatedAt: now,
          ),
        );
        created++;
      }
      return created;
    }),
  );
}
