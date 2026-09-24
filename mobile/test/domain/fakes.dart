import 'dart:async';

import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';

/// Minimal in-memory repositories for use-case tests.
class _Store<T> {
  _Store(this.idOf);
  final String Function(T) idOf;
  final items = <String, T>{};
  final _changes = StreamController<void>.broadcast();

  void put(T v) {
    items[idOf(v)] = v;
    _changes.add(null);
  }

  void remove(String id) {
    items.remove(id);
    _changes.add(null);
  }

  Stream<R> watch<R>(R Function() read) => Stream<R>.multi((c) {
    c.add(read());
    final sub = _changes.stream.listen((_) => c.add(read()));
    c.onCancel = sub.cancel;
  });
}

class FakeWalletRepository implements WalletRepository {
  final s = _Store<Wallet>((w) => w.id);

  List<Wallet> _all(bool archived) =>
      s.items.values.where((w) => archived || !w.archived).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Stream<List<Wallet>> watchAll({bool includeArchived = true}) =>
      s.watch(() => _all(includeArchived));
  @override
  Future<List<Wallet>> getAll({bool includeArchived = true}) async =>
      _all(includeArchived);
  @override
  Stream<Wallet?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<Wallet?> getById(String id) async => s.items[id];
  @override
  Future<void> save(Wallet wallet) async => s.put(wallet);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeCategoryRepository implements CategoryRepository {
  final s = _Store<TxCategory>((c) => c.id);

  List<TxCategory> _all(CategoryType? t) =>
      s.items.values.where((c) => t == null || c.type == t).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  @override
  Stream<List<TxCategory>> watchAll({CategoryType? type}) =>
      s.watch(() => _all(type));
  @override
  Future<List<TxCategory>> getAll({CategoryType? type}) async => _all(type);
  @override
  Stream<TxCategory?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<TxCategory?> getById(String id) async => s.items[id];
  @override
  Future<void> save(TxCategory category) async => s.put(category);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeTransactionRepository implements TransactionRepository {
  final s = _Store<Transaction>((t) => t.id);

  List<Transaction> _q({
    DateTime? from,
    DateTime? to,
    TxType? type,
    String? walletId,
    String? categoryId,
    int? limit,
  }) {
    final r =
        s.items.values
            .where(
              (t) =>
                  (from == null || !t.date.isBefore(from)) &&
                  (to == null || !t.date.isAfter(to)) &&
                  (type == null || t.type == type) &&
                  (walletId == null ||
                      t.walletId == walletId ||
                      t.toWalletId == walletId) &&
                  (categoryId == null || t.categoryId == categoryId),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return limit == null || r.length <= limit ? r : r.sublist(0, limit);
  }

  @override
  Stream<List<Transaction>> watch({
    DateTime? from,
    DateTime? to,
    TxType? type,
    String? walletId,
    String? categoryId,
    int? limit,
  }) => s.watch(
    () => _q(
      from: from,
      to: to,
      type: type,
      walletId: walletId,
      categoryId: categoryId,
      limit: limit,
    ),
  );
  @override
  Future<List<Transaction>> list({
    DateTime? from,
    DateTime? to,
    TxType? type,
  }) async => _q(from: from, to: to, type: type);
  @override
  Stream<Transaction?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<Transaction?> getById(String id) async => s.items[id];
  @override
  Future<void> save(Transaction t) async => s.put(t);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeSubscriptionRepository implements SubscriptionRepository {
  final s = _Store<Subscription>((x) => x.id);

  @override
  Stream<List<Subscription>> watchAll() =>
      s.watch(() => s.items.values.toList());
  @override
  Future<List<Subscription>> getAll() async => s.items.values.toList();
  @override
  Stream<Subscription?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<Subscription?> getById(String id) async => s.items[id];
  @override
  Future<void> save(Subscription x) async => s.put(x);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakePlannedRepository implements PlannedRepository {
  final s = _Store<PlannedTransaction>((x) => x.id);

  @override
  Stream<List<PlannedTransaction>> watchRange(DateTime from, DateTime to) =>
      s.watch(
        () => s.items.values
            .where((p) => !p.date.isBefore(from) && !p.date.isAfter(to))
            .toList(),
      );
  @override
  Stream<PlannedTransaction?> watchById(String id) =>
      s.watch(() => s.items[id]);
  @override
  Future<PlannedTransaction?> getById(String id) async => s.items[id];
  @override
  Future<void> save(PlannedTransaction x) async => s.put(x);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeBudgetRepository implements BudgetRepository {
  final s = _Store<Budget>((x) => x.id);

  @override
  Stream<List<Budget>> watchByMonth(YearMonth m) => s.watch(
    () => s.items.values
        .where((b) => b.month == m.month && b.year == m.year)
        .toList(),
  );
  @override
  Stream<List<Budget>> watchAll() => s.watch(() => s.items.values.toList());
  @override
  Stream<Budget?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<Budget?> getById(String id) async => s.items[id];
  @override
  Future<Budget?> findByKey(String categoryId, YearMonth m) async => s
      .items
      .values
      .where(
        (b) =>
            b.categoryId == categoryId &&
            b.month == m.month &&
            b.year == m.year,
      )
      .firstOrNull;
  @override
  Future<void> save(Budget x) async => s.put(x);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeUnitOfWork implements UnitOfWork {
  int runs = 0;
  @override
  Future<T> run<T>(Future<T> Function() action) {
    runs++;
    return action();
  }
}

class InMemoryPrayerRepository implements PrayerRepository {
  final s = _Store<PrayerEntry>((e) => e.id);
  int saves = 0;

  @override
  Stream<List<PrayerEntry>> watchRange(String fromKey, String toKey) => s.watch(
    () =>
        s.items.values
            .where(
              (e) =>
                  e.date.compareTo(fromKey) >= 0 &&
                  e.date.compareTo(toKey) <= 0,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date)),
  );
  @override
  Future<PrayerEntry?> findByKey(String dateKey, Prayer prayer) async => s
      .items
      .values
      .where((e) => e.date == dateKey && e.prayer == prayer)
      .firstOrNull;
  @override
  Future<void> save(PrayerEntry entry) async {
    saves++;
    s.put(entry);
  }

  @override
  Future<void> delete(String id) async => s.remove(id);
}

final t0 = DateTime(2026, 1, 1);

Wallet wallet(
  String id, {
  double balance = 0,
  bool archived = false,
  DateTime? createdAt,
}) => Wallet(
  id: id,
  name: id,
  type: WalletType.cash,
  balance: balance,
  syncedBalance: balance,
  currency: 'IDR',
  color: '#6366f1',
  icon: 'wallet',
  archived: archived,
  createdAt: createdAt ?? t0,
  updatedAt: createdAt ?? t0,
);

TxCategory category(String id, {CategoryType type = CategoryType.expense}) =>
    TxCategory(
      id: id,
      name: id,
      type: type,
      color: '#f97316',
      icon: 'circle',
      createdAt: t0,
      updatedAt: t0,
    );

Transaction txn(
  String id,
  TxType type,
  double amount,
  DateTime date, {
  String walletId = 'w1',
  String? toWalletId,
  String? categoryId,
}) => Transaction(
  id: id,
  walletId: walletId,
  toWalletId: toWalletId,
  categoryId: categoryId,
  type: type,
  amount: amount,
  date: date,
  createdAt: date,
  updatedAt: date,
);

Subscription subscription(
  String id,
  DateTime nextBilling, {
  BillingCycle cycle = BillingCycle.monthly,
  double amount = 50000,
  bool active = true,
  String? walletId,
  String? categoryId,
}) => Subscription(
  id: id,
  name: id,
  amount: amount,
  currency: 'IDR',
  cycle: cycle,
  nextBilling: nextBilling,
  walletId: walletId,
  categoryId: categoryId,
  color: '#6366f1',
  icon: 'credit-card',
  active: active,
  createdAt: t0,
  updatedAt: t0,
);
