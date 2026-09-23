// Shared test harness for the budgets / subscriptions / forecast / reports
// screens: in-memory repositories (test/domain/fakes.dart) behind the real use
// cases and watch providers, a fake sync service, the real game engine with an
// in-memory store, and a GoRouter so push/pop work.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart' show activityEventsFrom;
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart'
    show BudgetStatus, InMemoryGameStore;
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/budgets/pages/budget_form_page.dart';
import 'package:ghina/presentation/features/budgets/pages/budgets_page.dart';
import 'package:ghina/presentation/features/forecast/pages/forecast_page.dart';
import 'package:ghina/presentation/features/forecast/pages/planned_form_page.dart';
import 'package:ghina/presentation/features/reports/pages/reports_page.dart';
import 'package:ghina/presentation/features/subscriptions/pages/subscription_form_page.dart';
import 'package:ghina/presentation/features/subscriptions/pages/subscriptions_page.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/fakes.dart';
import '../../design_system/_helpers.dart';

export '../../../domain/fakes.dart';
export '../../design_system/_helpers.dart'
    show loadGhinaFonts, saveShot, shotsDir;

class FakeSyncService implements SyncService {
  int syncs = 0;
  bool fail = false;

  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async {
    syncs++;
    if (fail) throw Exception('offline');
  }

  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.initial);
  @override
  Future<void> resetLocalData() async {}
}

/// "Today" for every screen test: Wed 23 Sep 2026, noon.
final testNow = DateTime(2026, 9, 23, 12);

class FinanceHarness {
  final wallets = FakeWalletRepository();
  final categories = FakeCategoryRepository();
  final transactions = FakeTransactionRepository();
  final budgets = FakeBudgetRepository();
  final subscriptions = FakeSubscriptionRepository();
  final planned = FakePlannedRepository();
  final sync = FakeSyncService();
  final clock = FixedClock(testNow);

  List<Override> get overrides => [
    walletRepositoryProvider.overrideWithValue(wallets),
    categoryRepositoryProvider.overrideWithValue(categories),
    transactionRepositoryProvider.overrideWithValue(transactions),
    budgetRepositoryProvider.overrideWithValue(budgets),
    subscriptionRepositoryProvider.overrideWithValue(subscriptions),
    plannedRepositoryProvider.overrideWithValue(planned),
    unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
    clockProvider.overrideWithValue(clock),
    syncServiceProvider.overrideWithValue(sync),
    currencyProvider.overrideWithValue('IDR'),
    gameStoreProvider.overrideWithValue(InMemoryGameStore()),
    gameClockProvider.overrideWithValue(clock),
    gameTickProvider.overrideWith((ref) => const Stream.empty()),
    activityEventsSourceProvider.overrideWith(
      (ref) => transactions.watch().map(
        (t) => activityEventsFrom(t, const [], const [], const []),
      ),
    ),
    budgetStatusSourceProvider.overrideWith(
      (ref) => WatchBudgetUsage(budgets, transactions, categories)().map(
        (rows) => [
          for (final r in rows)
            BudgetStatus(
              categoryId: r.budget.categoryId,
              categoryName: r.category?.name,
              year: r.budget.year,
              month: r.budget.month,
              budget: r.budget.amount,
              spent: r.spent,
            ),
        ],
      ),
    ),
  ];

  // ---------------------------------------------------------------- seed

  TxCategory cat(
    String id,
    String name,
    String color,
    String icon, {
    CategoryType type = CategoryType.expense,
  }) {
    final c = TxCategory(
      id: id,
      name: name,
      type: type,
      color: color,
      icon: icon,
      createdAt: t0,
      updatedAt: t0,
    );
    categories.s.put(c);
    return c;
  }

  Wallet addWallet(
    String id,
    String name,
    double balance, {
    String color = '#3b82f6',
    String icon = 'wallet',
    WalletType type = WalletType.bank,
  }) {
    final w = Wallet(
      id: id,
      name: name,
      type: type,
      balance: balance,
      syncedBalance: balance,
      currency: 'IDR',
      color: color,
      icon: icon,
      archived: false,
      createdAt: t0.add(Duration(minutes: wallets.s.items.length)),
      updatedAt: t0,
    );
    wallets.s.put(w);
    return w;
  }

  var _n = 0;
  void tx(
    TxType type,
    double amount,
    DateTime date, {
    String? categoryId,
    String walletId = 'bca',
    String? note,
  }) {
    final id = 't${_n++}';
    transactions.s.put(
      Transaction(
        id: id,
        walletId: walletId,
        categoryId: categoryId,
        type: type,
        amount: amount,
        note: note,
        date: date,
        // Old history: created long ago so it doesn't count as today's XP.
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  void budget(
    String id,
    String categoryId,
    double amount, {
    int year = 2026,
    int month = 9,
  }) => budgets.s.put(
    Budget(
      id: id,
      categoryId: categoryId,
      amount: amount,
      month: month,
      year: year,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  void sub(
    String id,
    String name,
    double amount,
    DateTime next, {
    BillingCycle cycle = BillingCycle.monthly,
    String color = '#E50914',
    String icon = 'tv',
    bool active = true,
    String? walletId = 'bca',
    String? categoryId,
  }) => subscriptions.s.put(
    Subscription(
      id: id,
      name: name,
      amount: amount,
      currency: 'IDR',
      cycle: cycle,
      nextBilling: next,
      categoryId: categoryId,
      walletId: walletId,
      color: color,
      icon: icon,
      active: active,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  void plan(
    String id,
    TxType type,
    double amount,
    DateTime date, {
    String? note,
    String? categoryId,
    bool done = false,
    String? walletId,
  }) => planned.s.put(
    PlannedTransaction(
      id: id,
      type: type,
      amount: amount,
      note: note,
      categoryId: categoryId,
      walletId: walletId,
      date: date,
      done: done,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  /// A realistic data set for screenshots and list tests.
  void seedRich() {
    addWallet('bca', 'BCA', 8250000, color: '#3b82f6', icon: 'landmark');
    addWallet(
      'gopay',
      'GoPay',
      420000,
      color: '#10b981',
      icon: 'smartphone',
      type: WalletType.ewallet,
    );
    addWallet(
      'cash',
      'Tunai',
      150000,
      color: '#f59e0b',
      icon: 'banknote',
      type: WalletType.cash,
    );
    cat('food', 'Makan & Minum', '#f97316', 'utensils');
    cat('transport', 'Transportasi', '#3b82f6', 'car');
    cat('shop', 'Belanja', '#ec4899', 'shopping-bag');
    cat('fun', 'Hiburan', '#8b5cf6', 'gamepad-2');
    cat('bills', 'Tagihan', '#64748b', 'receipt');
    cat('health', 'Kesehatan', '#ef4444', 'heart-pulse');
    cat('salary', 'Gaji', '#22c55e', 'briefcase', type: CategoryType.income);
    cat('side', 'Freelance', '#14b8a6', 'laptop', type: CategoryType.income);

    // History: Apr–Sep 2026.
    for (var m = 4; m <= 9; m++) {
      tx(
        TxType.income,
        9500000,
        DateTime(2026, m, 1, 9),
        categoryId: 'salary',
        note: 'Gajian',
      );
      if (m.isEven) {
        tx(
          TxType.income,
          1500000 + m * 100000,
          DateTime(2026, m, 14),
          categoryId: 'side',
        );
      }
      tx(
        TxType.expense,
        1800000 + m * 90000,
        DateTime(2026, m, 5),
        categoryId: 'food',
      );
      tx(
        TxType.expense,
        600000 + (m % 3) * 150000,
        DateTime(2026, m, 8),
        categoryId: 'transport',
      );
      tx(
        TxType.expense,
        900000 + (m % 2) * 700000,
        DateTime(2026, m, 12),
        categoryId: 'shop',
      );
      tx(TxType.expense, 450000, DateTime(2026, m, 20), categoryId: 'bills');
      if (m != 9) {
        tx(TxType.expense, 350000, DateTime(2026, m, 18), categoryId: 'fun');
      }
    }
    // This month details.
    tx(
      TxType.expense,
      85000,
      DateTime(2026, 9, 21, 12),
      categoryId: 'food',
      note: 'Makan siang tim',
    );
    tx(
      TxType.expense,
      42000,
      DateTime(2026, 9, 22, 19),
      categoryId: 'food',
      note: 'Kopi susu',
    );
    tx(
      TxType.expense,
      250000,
      DateTime(2026, 9, 15),
      categoryId: 'health',
      note: 'Vitamin',
    );

    budget('b-food', 'food', 2500000);
    budget('b-transport', 'transport', 800000);
    budget('b-shop', 'shop', 1500000);
    budget('b-bills', 'bills', 500000);

    sub('netflix', 'Netflix', 186000, DateTime(2026, 9, 25), categoryId: 'fun');
    sub(
      'spotify',
      'Spotify',
      54990,
      DateTime(2026, 10, 2),
      color: '#1DB954',
      icon: 'music',
      categoryId: 'fun',
    );
    sub(
      'icloud',
      'Apple iCloud',
      15000,
      DateTime(2026, 9, 23),
      color: '#555555',
      icon: 'cloud',
      walletId: 'gopay',
    );
    sub(
      'gym',
      'Gym Membership',
      350000,
      DateTime(2026, 10, 10),
      color: '#f97316',
      icon: 'dumbbell',
    );
    sub(
      'm365',
      'Microsoft 365',
      1199000,
      DateTime(2027, 1, 15),
      cycle: BillingCycle.yearly,
      color: '#D83B01',
      icon: 'briefcase',
    );
    sub(
      'yt',
      'YouTube Premium',
      59000,
      DateTime(2026, 10, 5),
      color: '#FF0000',
      icon: 'tv',
      active: false,
    );

    plan(
      'p-salary',
      TxType.income,
      9500000,
      DateTime(2026, 10, 1),
      note: 'Gajian',
      categoryId: 'salary',
    );
    plan(
      'p-tax',
      TxType.expense,
      650000,
      DateTime(2026, 10, 12),
      note: 'Pajak motor',
      categoryId: 'transport',
    );
    plan(
      'p-gift',
      TxType.expense,
      400000,
      DateTime(2026, 10, 20),
      note: 'Kado nikahan Rani',
      categoryId: 'shop',
    );
    plan(
      'p-bonus',
      TxType.income,
      2000000,
      DateTime(2026, 10, 25),
      note: 'Bonus proyek',
      categoryId: 'side',
      done: true,
    );
  }
}

/// Every screen of these features + stubs for links out of them.
GoRouter buildTestRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Center(child: Text('HOME'))),
    ),
    GoRoute(path: '/budgets', builder: (_, _) => const BudgetsPage()),
    GoRoute(path: '/budgets/new', builder: (_, _) => const BudgetFormPage()),
    GoRoute(
      path: '/budgets/:id',
      builder: (_, s) => BudgetFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(
      path: '/subscriptions',
      builder: (_, _) => const SubscriptionsPage(),
    ),
    GoRoute(
      path: '/subscriptions/new',
      builder: (_, _) => const SubscriptionFormPage(),
    ),
    GoRoute(
      path: '/subscriptions/:id',
      builder: (_, s) => SubscriptionFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(path: '/forecast', builder: (_, _) => const ForecastPage()),
    GoRoute(path: '/forecast/new', builder: (_, _) => const PlannedFormPage()),
    GoRoute(
      path: '/forecast/:id',
      builder: (_, s) => PlannedFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
    GoRoute(
      path: '/:a/:b',
      builder: (_, s) => Scaffold(body: Text('STUB ${s.uri}')),
    ),
    GoRoute(
      path: '/:a',
      builder: (_, s) => Scaffold(body: Text('STUB ${s.uri}')),
    ),
  ],
);

const shotKey = ValueKey('screen-shot');

/// Pumps the app at [location] (pushed on top of a home route so `pop` works).
Future<GoRouter> pumpScreen(
  WidgetTester tester,
  FinanceHarness h,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = buildTestRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: RepaintBoundary(
        key: shotKey,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 2,
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: dark ? GhinaTheme.dark() : GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  unawaited(router.push(location));
  await settle(tester);
  return router;
}

/// Pumps enough frames for streams, pop-ins and progress bars (never
/// `pumpAndSettle`: the mascot animates forever).
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Saves `<shotsDir>/<name>.png` of the whole app when `GHINA_SHOTS_DIR` is set.
Future<void> shot(WidgetTester tester, String name) async {
  if (shotsDir == null) return;
  await settle(tester, 10);
  await saveShot(tester, shotKey, name);
}
