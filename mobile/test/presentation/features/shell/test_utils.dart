import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/usecase_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:ghina/presentation/state/sync_status_provider.dart';
import 'package:go_router/go_router.dart';

/// Fixed "now" for page tests: Wednesday 23 September 2026, 12:00.
final testNow = DateTime(2026, 9, 23, 12);

const testUser = AppUser(
  id: 'u1',
  name: 'Ghina Putri',
  email: 'ghina@contoh.id',
  currency: 'IDR',
  syncEpoch: 'e1',
);

// ---------------------------------------------------------------- session

/// Session without network: records calls and returns [nextResult].
class FakeSession extends SessionController {
  FakeSession(this.initial);

  final SessionState initial;
  Result<AppUser>? nextResult;
  final calls = <String>[];

  @override
  SessionState build() => initial;

  Result<AppUser> _answer(String call, AppUser u) {
    calls.add(call);
    final r = nextResult ?? Ok(u);
    if (r case Ok(:final value)) state = SignedIn(value);
    return r;
  }

  @override
  Future<Result<AppUser>> signIn(String email, String password) async =>
      _answer('signIn:$email', testUser);

  @override
  Future<Result<AppUser>> register(
    String name,
    String email,
    String password,
  ) async => _answer('register:$name:$email', testUser);

  @override
  Future<Result<AppUser>> signInWithGoogle(String idToken) async =>
      _answer('google', testUser);

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    state = const SignedOut();
  }

  @override
  Future<Result<AppUser>> refreshProfile() async => Ok(testUser);

  @override
  Future<Result<AppUser>> updateProfile({
    String? name,
    String? currency,
  }) async {
    final current = (state as SignedIn).user;
    return _answer(
      'updateProfile:$name:$currency',
      AppUser(
        id: current.id,
        name: name ?? current.name,
        email: current.email,
        currency: currency ?? current.currency,
        syncEpoch: current.syncEpoch,
      ),
    );
  }
}

// ---------------------------------------------------------------- sync

class FakeSyncService implements SyncService {
  int syncCalls = 0;
  int resetCalls = 0;
  Failure? failWith;

  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async {
    syncCalls++;
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<SyncStatus> watchStatus() => const Stream.empty();
  @override
  Future<void> resetLocalData() async => resetCalls++;
}

// ---------------------------------------------------------------- fixtures

TxCategory cat(
  String id,
  String name, {
  String color = '#f97316',
  String icon = 'utensils',
}) => TxCategory(
  id: id,
  name: name,
  type: CategoryType.expense,
  color: color,
  icon: icon,
  createdAt: testNow,
  updatedAt: testNow,
);

Wallet wallet(String id, String name, double balance) => Wallet(
  id: id,
  name: name,
  type: WalletType.cash,
  balance: balance,
  syncedBalance: balance,
  currency: 'IDR',
  color: '#22c55e',
  icon: 'cash',
  archived: false,
  createdAt: testNow,
  updatedAt: testNow,
);

TransactionView txView(
  String id,
  double amount, {
  TxType type = TxType.expense,
  TxCategory? category,
  String? note,
  Wallet? w,
}) => TransactionView(
  transaction: Transaction(
    id: id,
    walletId: (w ?? wallet('w1', 'Tunai', 0)).id,
    categoryId: category?.id,
    type: type,
    amount: amount,
    note: note,
    date: testNow,
    createdAt: testNow,
    updatedAt: testNow,
  ),
  wallet: w ?? wallet('w1', 'Tunai', 0),
  category: category,
);

final food = cat('c1', 'Makan', color: '#f97316', icon: 'utensils');
final transport = cat('c2', 'Transportasi', color: '#3b82f6', icon: 'car');
final fun = cat('c3', 'Hiburan', color: '#ec4899', icon: 'gamepad-2');

DashboardSummary sampleDashboard({bool empty = false}) {
  final wallets = empty
      ? <Wallet>[]
      : [wallet('w1', 'Tunai', 350000), wallet('w2', 'BCA', 4200000)];
  return DashboardSummary(
    month: const YearMonth(2026, 9),
    totalBalance: empty ? 0 : 4550000,
    wallets: wallets,
    monthIncome: empty ? 0 : 8500000,
    monthExpense: empty ? 0 : 2150000,
    todayExpense: empty ? 0 : 45000,
    todayIncome: 0,
    monthBudgeted: empty ? 0 : 3000000,
    spendingByCategory: empty
        ? const []
        : [
            CategoryTotal(category: food, total: 1200000, pct: 55.8),
            CategoryTotal(category: transport, total: 550000, pct: 25.6),
            CategoryTotal(category: fun, total: 400000, pct: 18.6),
          ],
    trend: const [],
    recent: empty
        ? const []
        : [
            txView('t1', 25000, category: food, note: 'Kopi susu'),
            txView('t2', 8500000, type: TxType.income, note: 'Gaji September'),
            txView('t3', 120000, category: transport),
          ],
  );
}

BudgetMonth sampleBudgets({bool empty = false}) => BudgetMonth(
  month: const YearMonth(2026, 9),
  unbudgetedCategories: const [],
  items: empty
      ? const []
      : [
          BudgetView(
            budget: Budget(
              id: 'b1',
              categoryId: 'c1',
              amount: 1000000,
              month: 9,
              year: 2026,
              createdAt: testNow,
              updatedAt: testNow,
            ),
            category: food,
            spent: 1200000,
            transactions: const [],
          ),
          BudgetView(
            budget: Budget(
              id: 'b2',
              categoryId: 'c2',
              amount: 700000,
              month: 9,
              year: 2026,
              createdAt: testNow,
              updatedAt: testNow,
            ),
            category: transport,
            spent: 550000,
            transactions: const [],
          ),
        ],
);

SubscriptionSummary sampleSubs() => SubscriptionSummary(
  items: [
    Subscription(
      id: 's1',
      name: 'Netflix',
      amount: 186000,
      currency: 'IDR',
      cycle: BillingCycle.monthly,
      nextBilling: testNow.add(const Duration(days: 2)),
      color: '#ef4444',
      icon: 'tv',
      active: true,
      createdAt: testNow,
      updatedAt: testNow,
    ),
  ],
);

/// Transactions logged on each of the last [days] days (today included) → streak.
List<ActivityEvent> streakEvents(int days, {int today = 1}) => [
  for (var i = 1; i < days; i++)
    ActivityEvent.transaction(
      id: 'p$i',
      createdAt: testNow.subtract(Duration(days: i)),
    ),
  for (var j = 0; j < today; j++)
    ActivityEvent.transaction(
      id: 't$j',
      createdAt: testNow.subtract(Duration(minutes: j + 1)),
    ),
];

// ---------------------------------------------------------------- scope

/// Overrides for a signed-in user with the given data.
List<Override> pageOverrides({
  SessionState? session,
  FakeSession? fakeSession,
  List<ActivityEvent> events = const [],
  List<BudgetStatus> budgetStatus = const [],
  GameLocalState local = const GameLocalState(onboardingDone: true),
  InMemoryGameStore? store,
  DashboardSummary? dashboard,
  Stream<DashboardSummary>? dashboardStream,
  BudgetMonth? budgets,
  SubscriptionSummary? subs,
  SyncStatus sync = const SyncStatus(phase: SyncPhase.idle),
  FakeSyncService? syncService,
  List<Override> extra = const [],
}) {
  final gameStore =
      store ?? InMemoryGameStore({GameLocalState.storageKey: local.encode()});
  final svc = syncService ?? FakeSyncService();
  return [
    sessionControllerProvider.overrideWith(
      () => fakeSession ?? FakeSession(session ?? const SignedIn(testUser)),
    ),
    clockProvider.overrideWithValue(FixedClock(testNow)),
    gameClockProvider.overrideWithValue(FixedClock(testNow)),
    gameTickProvider.overrideWith((ref) => const Stream.empty()),
    gameStoreProvider.overrideWithValue(gameStore),
    gameUserNameProvider.overrideWithValue('Ghina'),
    activityEventsSourceProvider.overrideWith((ref) => Stream.value(events)),
    budgetStatusSourceProvider.overrideWith(
      (ref) => Stream.value(budgetStatus),
    ),
    watchDashboardProvider.overrideWith(
      (ref) => dashboardStream ?? Stream.value(dashboard ?? sampleDashboard()),
    ),
    watchBudgetMonthProvider.overrideWith(
      (ref, _) => Stream.value(budgets ?? sampleBudgets()),
    ),
    watchSubscriptionsProvider.overrideWith(
      (ref) => Stream.value(subs ?? sampleSubs()),
    ),
    syncStatusProvider.overrideWith((ref) => Stream.value(sync)),
    syncNowProvider.overrideWithValue(SyncNow(svc)),
    resetLocalDataProvider.overrideWithValue(ResetLocalData(svc)),
    ...extra,
  ];
}

/// Pumps [page] at `/` inside a router; every other path renders `ROUTE:<path>`.
Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  required List<Override> overrides,
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Key? boundaryKey,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => page),
      GoRoute(
        path: '/:a/:b/:c',
        builder: (_, s) => Scaffold(body: Text('ROUTE:${s.uri.path}')),
      ),
      GoRoute(
        path: '/:a/:b',
        builder: (_, s) => Scaffold(body: Text('ROUTE:${s.uri.path}')),
      ),
      GoRoute(
        path: '/:a',
        builder: (_, s) => Scaffold(body: Text('ROUTE:${s.uri.path}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: GhinaTheme.light(),
          darkTheme: GhinaTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await settle(tester);
}

/// Pumps enough frames for streams, count-ups and pop-ins (animations loop forever).
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the page's main (first) scrollable until [finder] is built and fully on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await settle(tester, 3);
}
