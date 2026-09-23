// End-to-end check against a real server. Skipped unless GHINA_E2E_BASE_URL is set:
//   (cd .. && npx next dev -p 3100)
//   GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_sync_test.dart
// Creates a throwaway user mobile-test-dart-*@example.test (delete it afterwards).
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/auth_api.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/repositories/auth_repository_impl.dart';
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/life_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

class Client {
  Client(String baseUrl, this.tokens) {
    api = ApiClient(baseUrl: baseUrl, tokens: tokens);
    auth = AuthRepositoryImpl(api: AuthApi(api), tokens: tokens, db: db);
    engine = SyncEngine(
      db: db,
      outbox: outbox,
      api: DioSyncApi(api),
      photos: InMemoryPhotoStore(),
      clock: clock,
    );
  }

  final MemoryTokenStore tokens;
  late final ApiClient api;
  late final AuthRepositoryImpl auth;
  late final SyncEngine engine;
  final db = AppDatabase.memory();
  late final outbox = Outbox(db);
  final clock = const SystemClock();
  late final store = LocalStore(db, outbox, clock);
  late final wallets = DriftWalletRepository(store);
  late final categories = DriftCategoryRepository(store);
  late final txs = DriftTransactionRepository(store);
  late final budgets = DriftBudgetRepository(store);
  late final subs = DriftSubscriptionRepository(store);
  late final planned = DriftPlannedRepository(store);
  late final prayers = DriftPrayerRepository(store);
  late final health = DriftHealthRepository(store);
  late final food = DriftFoodRepository(store, InMemoryPhotoStore());
  late final uow = DriftUnitOfWork(store);
}

void main() {
  final base = Platform.environment['GHINA_E2E_BASE_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'full round trip against the real server',
    () async {
      final email =
          'mobile-test-dart-${DateTime.now().millisecondsSinceEpoch}@example.test';
      final a = Client(base!, MemoryTokenStore());
      final user = await a.auth.register(
        name: 'Dart E2E',
        email: email,
        password: 'rahasia123',
      );
      expect(user.syncEpoch, isNotEmpty);

      await a.engine.syncNow();
      final starter = await a.wallets.getAll();
      expect(starter, isNotEmpty, reason: 'server seeds a starter wallet');
      final cats = await a.categories.getAll();
      expect(cats, isNotEmpty, reason: 'server seeds default categories');
      final food0 = cats.firstWhere((c) => c.type == CategoryType.expense);

      final clock = a.clock;
      final w1 = (await CreateWallet(a.wallets, clock)(
        const WalletInput(
          name: 'Bank',
          type: WalletType.bank,
          initialBalance: 1000000,
        ),
      )).valueOrThrow;
      final create = CreateTransaction(a.txs, a.wallets, a.categories, clock);
      final t1 = (await create(
        TransactionInput(
          type: TxType.expense,
          amount: 25000,
          walletId: w1.id,
          categoryId: food0.id,
          note: 'Soto',
          date: DateTime.now(),
        ),
      )).valueOrThrow;
      await TransferBetweenWallets(create)(
        fromWalletId: w1.id,
        toWalletId: starter.first.id,
        amount: 100000,
        date: DateTime.now(),
      );
      final month = YearMonth.of(DateTime.now());
      await SetBudget(a.budgets, a.categories, clock)(
        categoryId: food0.id,
        amount: 500000,
        month: month,
      );
      final sub =
          (await CreateSubscription(a.subs, a.wallets, a.categories, clock)(
            SubscriptionInput(
              name: 'Netflix',
              amount: 54000,
              nextBilling: DateTime.now(),
              walletId: w1.id,
            ),
          )).valueOrThrow;
      await PaySubscription(a.subs, a.txs, a.wallets, a.uow, clock)(sub.id);
      await CreatePlanned(a.planned, a.wallets, a.categories, clock)(
        PlannedInput(
          amount: 75000,
          date: DateTime.now().add(const Duration(days: 20)),
        ),
      );
      await TogglePrayer(a.prayers, clock)(DateTime.now(), Prayer.subuh);
      await CreateHealthEntry(a.health, clock)(
        HealthInput(
          date: DateTime.now(),
          weight: 60.5,
          systolic: 118,
          diastolic: 76,
        ),
      );
      final photo = File('${Directory.systemTemp.path}/ghina_e2e.jpg')
        ..writeAsBytesSync(const [
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          0,
          0x10,
          0x4A,
          0x46,
          0x49,
          0x46,
          0,
          1,
          0xFF,
          0xD9,
        ]);
      await CreateFoodLog(a.food, clock)(
        FoodInput(
          date: DateTime.now(),
          name: 'Nasi uduk',
          meal: MealType.breakfast,
          calories: 450,
        ),
        photoPath: photo.path,
      );

      await a.engine.syncNow();
      expect(await a.outbox.all(), isEmpty);
      expect((await a.db.getMeta()).lastError, isNull);
      final foodRow = (await a.food.watchAll().first).single;
      expect(foodRow.photoUrl, startsWith('/uploads/'));
      expect(foodRow.localPhotoPath, isNull);

      // Second device (same token) pulls everything and agrees on balances.
      final b = Client(base, MemoryTokenStore()..token = a.tokens.token);
      await b.engine.syncNow();
      Future<Map<String, double>> balances(Client c) async => {
        for (final w in await c.wallets.getAll()) w.id: w.balance,
      };
      expect(await balances(b), await balances(a));
      expect(
        (await b.wallets.getById(w1.id))!.balance,
        1000000 - 25000 - 100000 - 54000,
      );
      expect((await b.txs.list()).length, (await a.txs.list()).length);
      expect(
        (await b.subs.getById(sub.id))!.nextBilling,
        (await a.subs.getById(sub.id))!.nextBilling,
      );

      // Edit + delete on B, then A pulls.
      await UpdateTransaction(b.txs, b.wallets, b.categories, clock)(
        t1.id,
        TransactionInput(
          type: TxType.expense,
          amount: 30000,
          walletId: w1.id,
          categoryId: food0.id,
          date: t1.date,
        ),
      );
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(
        (await a.wallets.getById(w1.id))!.balance,
        1000000 - 30000 - 100000 - 54000,
      );

      await DeleteTransaction(a.txs)(t1.id);
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(await b.txs.getById(t1.id), isNull);
      expect(await balances(b), await balances(a));

      // Both devices tick the same prayer offline → duplicate resolves to one row.
      final today = DateTime.now();
      await TogglePrayer(a.prayers, clock)(today, Prayer.isya);
      await TogglePrayer(b.prayers, clock)(today, Prayer.isya);
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.engine.syncNow();
      final key = dateKey(today);
      final pa = await a.prayers.watchRange(key, key).first;
      final pb = await b.prayers.watchRange(key, key).first;
      expect(pa.map((p) => p.id).toSet(), pb.map((p) => p.id).toSet());
      expect(pb.where((p) => p.prayer == Prayer.isya), hasLength(1));

      // Category delete cascades on the other device.
      await DeleteCategory(b.categories)(food0.id);
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(await a.categories.getById(food0.id), isNull);
      expect(await a.budgets.findByKey(food0.id, month), isNull);

      // ignore: avoid_print
      print('E2E OK for $email');
    },
    skip: base == null ? 'set GHINA_E2E_BASE_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
