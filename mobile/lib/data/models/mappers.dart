/// Drift row ⇄ domain entity mappers.
library;

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../datasources/local/app_database.dart';

extension WalletRowX on WalletRow {
  /// [pendingDelta] = effect of unsynced transaction mutations on this wallet.
  Wallet toEntity({double pendingDelta = 0}) => Wallet(
    id: id,
    name: name,
    type: WalletType.fromWire(type),
    balance: balance + pendingDelta,
    syncedBalance: balance,
    currency: currency,
    color: color,
    icon: icon,
    archived: archived,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension WalletX on Wallet {
  /// Row with [Wallet.syncedBalance] as the stored (server) balance.
  WalletsCompanion toCompanion() => WalletsCompanion.insert(
    id: id,
    name: name,
    type: Value(type.wire),
    balance: Value(syncedBalance),
    currency: Value(currency),
    color: Value(color),
    icon: Value(icon),
    archived: Value(archived),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension CategoryRowX on CategoryRow {
  TxCategory toEntity() => TxCategory(
    id: id,
    name: name,
    type: CategoryType.fromWire(type),
    color: color,
    icon: icon,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension CategoryX on TxCategory {
  CategoriesCompanion toCompanion() => CategoriesCompanion.insert(
    id: id,
    name: name,
    type: Value(type.wire),
    color: Value(color),
    icon: Value(icon),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension TransactionRowX on TransactionRow {
  /// Null when the stored type is unknown to this app version (a newer server):
  /// such rows stay in the database (their balance effect is already in the
  /// server balance) but are hidden from every list and aggregate.
  Transaction? toEntityOrNull() {
    final t = TxType.tryFromWire(type);
    if (t == null) return null;
    return Transaction(
      id: id,
      walletId: walletId,
      toWalletId: toWalletId,
      categoryId: categoryId,
      type: t,
      amount: amount,
      note: note,
      date: date,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension TransactionRowsX on Iterable<TransactionRow> {
  /// Entities of the rows with a known type.
  List<Transaction> toEntities() => [for (final r in this) ?r.toEntityOrNull()];
}

extension TransactionX on Transaction {
  TransactionsCompanion toCompanion() => TransactionsCompanion.insert(
    id: id,
    walletId: walletId,
    toWalletId: Value(toWalletId),
    categoryId: Value(categoryId),
    type: Value(type.wire),
    amount: amount,
    note: Value(note),
    date: date,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension BudgetRowX on BudgetRow {
  Budget toEntity() => Budget(
    id: id,
    categoryId: categoryId,
    amount: amount,
    month: month,
    year: year,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension BudgetX on Budget {
  BudgetsCompanion toCompanion() => BudgetsCompanion.insert(
    id: id,
    categoryId: categoryId,
    amount: amount,
    month: month,
    year: year,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension SubscriptionRowX on SubscriptionRow {
  Subscription toEntity() => Subscription(
    id: id,
    name: name,
    amount: amount,
    currency: currency,
    cycle: BillingCycle.fromWire(cycle),
    nextBilling: nextBilling,
    categoryId: categoryId,
    walletId: walletId,
    color: color,
    icon: icon,
    note: note,
    active: active,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension SubscriptionX on Subscription {
  SubscriptionsCompanion toCompanion() => SubscriptionsCompanion.insert(
    id: id,
    name: name,
    amount: amount,
    currency: Value(currency),
    cycle: Value(cycle.wire),
    nextBilling: nextBilling,
    categoryId: Value(categoryId),
    walletId: Value(walletId),
    color: Value(color),
    icon: Value(icon),
    note: Value(note),
    active: Value(active),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension PlannedRowX on PlannedRow {
  PlannedTransaction toEntity() => PlannedTransaction(
    id: id,
    type: TxType.fromWire(type),
    amount: amount,
    note: note,
    categoryId: categoryId,
    walletId: walletId,
    date: date,
    done: done,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension PlannedX on PlannedTransaction {
  PlannedCompanion toCompanion() => PlannedCompanion.insert(
    id: id,
    type: Value(type.wire),
    amount: amount,
    note: Value(note),
    categoryId: Value(categoryId),
    walletId: Value(walletId),
    date: date,
    done: Value(done),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension PrayerRowX on PrayerRow {
  /// Null when the stored prayer id is unknown.
  PrayerEntry? toEntity() {
    final p = Prayer.fromWire(prayer);
    if (p == null) return null;
    return PrayerEntry(
      id: id,
      date: date,
      prayer: p,
      status: PrayerStatus.forPrayer(p, status),
      qobliyah: p.isFardhu && p.hasQobliyah && qobliyah,
      badiyah: p.isFardhu && p.hasBadiyah && badiyah,
      rakaat: p.isSunnah ? rakaat : null,
      prayedAt: prayedAt,
      note: note,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension PrayerX on PrayerEntry {
  PrayersCompanion toCompanion() => PrayersCompanion.insert(
    id: id,
    date: date,
    prayer: prayer.wire,
    status: Value(status.wire),
    qobliyah: Value(qobliyah),
    badiyah: Value(badiyah),
    rakaat: Value(rakaat),
    prayedAt: Value(prayedAt),
    note: Value(note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension HealthRowX on HealthRow {
  HealthEntry toEntity() => HealthEntry(
    id: id,
    date: date,
    weight: weight,
    systolic: systolic,
    diastolic: diastolic,
    pulse: pulse,
    note: note,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension HealthX on HealthEntry {
  HealthCompanion toCompanion() => HealthCompanion.insert(
    id: id,
    date: date,
    weight: Value(weight),
    systolic: Value(systolic),
    diastolic: Value(diastolic),
    pulse: Value(pulse),
    note: Value(note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension FoodRowX on FoodRow {
  FoodLog toEntity() => FoodLog(
    id: id,
    date: date,
    name: name,
    meal: MealType.fromWire(meal),
    calories: calories,
    photoUrl: photoUrl,
    localPhotoPath: localPhotoPath,
    note: note,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension FoodX on FoodLog {
  FoodCompanion toCompanion() => FoodCompanion.insert(
    id: id,
    date: date,
    name: name,
    meal: Value(meal?.wire),
    calories: Value(calories),
    photoUrl: Value(photoUrl),
    localPhotoPath: Value(localPhotoPath),
    note: Value(note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
