import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/entities.dart';

/// Type the next "new category" form starts with (set right before
/// `context.push('/categories/new')`, e.g. from the Pemasukan tab).
class CategoryTypePresetNotifier extends Notifier<CategoryType?> {
  @override
  CategoryType? build() => null;

  void set(CategoryType? type) => state = type;
}

final categoryTypePresetProvider =
    NotifierProvider<CategoryTypePresetNotifier, CategoryType?>(
      CategoryTypePresetNotifier.new,
    );
