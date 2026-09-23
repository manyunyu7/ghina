import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/life_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fake_server.dart';

/// Real drift (in memory) + real repositories/use cases + [FakeServer].
class Harness {
  Harness() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  final db = AppDatabase.memory();
  late final outbox = Outbox(db);

  /// Client clock runs an hour ahead of the fake server so local edits win LWW.
  final clock = FixedClock(DateTime.utc(2026, 9, 23, 5).toLocal());
  late final store = LocalStore(db, outbox, clock);
  final server = FakeServer();
  final photos = InMemoryPhotoStore();
  late final engine = SyncEngine(
    db: db,
    outbox: outbox,
    api: server,
    photos: photos,
    clock: clock,
  );

  late final wallets = DriftWalletRepository(store);
  late final categories = DriftCategoryRepository(store);
  late final transactions = DriftTransactionRepository(store);
  late final budgets = DriftBudgetRepository(store);
  late final subscriptions = DriftSubscriptionRepository(store);
  late final planned = DriftPlannedRepository(store);
  late final prayers = DriftPrayerRepository(store);
  late final health = DriftHealthRepository(store);
  late final food = DriftFoodRepository(store, photos);
  late final uow = DriftUnitOfWork(store);

  late final createWallet = CreateWallet(wallets, clock);
  late final updateWallet = UpdateWallet(wallets, clock);
  late final deleteWallet = DeleteWallet(wallets);
  late final createCategory = CreateCategory(categories, clock);
  late final updateCategory = UpdateCategory(categories, clock);
  late final deleteCategory = DeleteCategory(categories);
  late final createTx = CreateTransaction(
    transactions,
    wallets,
    categories,
    clock,
  );
  late final updateTx = UpdateTransaction(
    transactions,
    wallets,
    categories,
    clock,
  );
  late final deleteTx = DeleteTransaction(transactions);
  late final togglePrayer = TogglePrayer(prayers, clock);
  late final createFood = CreateFoodLog(food, clock);

  /// Advance the client clock (each local edit gets a later timestamp).
  void tick() => clock.advance(const Duration(seconds: 1));

  Future<Wallet> wallet(String id) async => (await wallets.getById(id))!;

  Future<String> newWallet(String name, double balance) async {
    tick();
    return (await createWallet(
      WalletInput(name: name, initialBalance: balance),
    )).valueOrThrow.id;
  }

  Future<int> outboxCount() async => (await outbox.all()).length;

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}
