/// Widget-test harness for the learn / profile / prayers / health / food
/// screens: in-memory repositories bound at the provider level, a fixed
/// clock, in-memory game store and a tiny GoRouter.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/fakes.dart';

/// Wednesday noon.
final harnessNow = DateTime(2026, 9, 23, 12);

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

class FakePrayerRepository implements PrayerRepository {
  final s = _Store<PrayerEntry>((e) => e.id);

  @override
  Stream<List<PrayerEntry>> watchRange(String fromKey, String toKey) => s.watch(
    () => s.items.values
        .where(
          (e) => e.date.compareTo(fromKey) >= 0 && e.date.compareTo(toKey) <= 0,
        )
        .toList(),
  );
  @override
  Future<PrayerEntry?> findByKey(String dateKey, Prayer prayer) async => s
      .items
      .values
      .where((e) => e.date == dateKey && e.prayer == prayer)
      .firstOrNull;
  @override
  Future<void> save(PrayerEntry entry) async => s.put(entry);
  @override
  Future<void> delete(String id) async => s.remove(id);

  /// Rows with explicit statuses (fardhu) or `done` (sunnah).
  void seedStatuses(
    DateTime day,
    Map<Prayer, PrayerStatus> statuses, {
    Set<Prayer> qobliyah = const {},
    Set<Prayer> badiyah = const {},
  }) {
    statuses.forEach((p, st) {
      s.put(
        PrayerEntry(
          id: '${dateKey(day)}-${p.wire}',
          date: dateKey(day),
          prayer: p,
          status: st,
          qobliyah: qobliyah.contains(p),
          badiyah: badiyah.contains(p),
          createdAt: day,
          updatedAt: day,
        ),
      );
    });
  }

  void seed(DateTime day, Iterable<Prayer> prayers) {
    for (final p in prayers) {
      s.put(
        PrayerEntry(
          id: '${dateKey(day)}-${p.wire}',
          date: dateKey(day),
          prayer: p,
          createdAt: day,
          updatedAt: day,
        ),
      );
    }
  }
}

class FakeHealthRepository implements HealthRepository {
  final s = _Store<HealthEntry>((e) => e.id);

  List<HealthEntry> get _sorted =>
      s.items.values.toList()..sort((a, b) => b.date.compareTo(a.date));

  @override
  Stream<List<HealthEntry>> watchAll({DateTime? from, DateTime? to}) =>
      s.watch(() => _sorted);
  @override
  Stream<HealthEntry?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<HealthEntry?> getById(String id) async => s.items[id];
  @override
  Future<void> save(HealthEntry entry) async => s.put(entry);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeFoodRepository implements FoodRepository {
  final s = _Store<FoodLog>((e) => e.id);
  final savedPhotos = <String?>[];

  List<FoodLog> get _sorted =>
      s.items.values.toList()..sort((a, b) => b.date.compareTo(a.date));

  @override
  Stream<List<FoodLog>> watchAll({DateTime? from, DateTime? to}) =>
      s.watch(() => _sorted);
  @override
  Stream<FoodLog?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<FoodLog?> getById(String id) async => s.items[id];
  @override
  Future<void> save(FoodLog log, {String? newPhotoPath}) async {
    savedPhotos.add(newPhotoPath);
    s.put(log);
  }

  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeSyncService implements SyncService {
  int syncs = 0;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async => syncs++;
  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.initial);
  @override
  Future<void> resetLocalData() async {}
}

const harnessUser = AppUser(
  id: 'u1',
  name: 'Ghina Putri',
  email: 'ghina@contoh.id',
  currency: 'IDR',
  syncEpoch: 'e1',
);

/// Everything a screen test can seed or inspect.
class Harness {
  final clock = FixedClock(harnessNow);
  final gameStore = InMemoryGameStore();
  final transactions = FakeTransactionRepository();
  final budgets = FakeBudgetRepository();
  final categories = FakeCategoryRepository();
  final prayers = FakePrayerRepository();
  final health = FakeHealthRepository();
  final food = FakeFoodRepository();
  final tasks = FakeTaskRepository();
  final sync = FakeSyncService();

  /// Seeds a local game state (lesson completions, seen badges, …).
  void seedGame(GameLocalState state) {
    gameStore.values[GameLocalState.storageKey] = state.encode();
  }

  /// One expense per day for the [days] days before today (a streak).
  void seedStreak(int days, {bool today = true}) {
    for (var i = today ? 0 : 1; i <= days - (today ? 1 : 0); i++) {
      final d = addDays(harnessNow, -i).subtract(const Duration(hours: 2));
      transactions.s.put(txn('t$i', TxType.expense, 15000, d));
    }
  }

  List<Override> get overrides => [
    ...buildGameOverrides(store: gameStore),
    gameTickProvider.overrideWith((ref) => const Stream.empty()),
    clockProvider.overrideWithValue(clock),
    transactionRepositoryProvider.overrideWithValue(transactions),
    budgetRepositoryProvider.overrideWithValue(budgets),
    categoryRepositoryProvider.overrideWithValue(categories),
    prayerRepositoryProvider.overrideWithValue(prayers),
    healthRepositoryProvider.overrideWithValue(health),
    foodRepositoryProvider.overrideWithValue(food),
    taskRepositoryProvider.overrideWithValue(tasks),
    // Notes/content sources (game events, merged reminders) in memory.
    contentItemRepositoryProvider.overrideWithValue(
      FakeContentItemRepository(),
    ),
    contentPostRepositoryProvider.overrideWithValue(
      FakeContentPostRepository(),
    ),
    socialAccountRepositoryProvider.overrideWithValue(
      FakeSocialAccountRepository(),
    ),
    syncServiceProvider.overrideWithValue(sync),
    currentUserProvider.overrideWithValue(harnessUser),
  ];
}

/// Pumps [location] (pushed on top of a "HOME" stub so `pop` works) inside a
/// ProviderScope with the harness overrides. Unknown routes render
/// `route:<uri>` so navigation can be asserted.
Future<GoRouter> pumpScreen(
  WidgetTester tester,
  Harness h, {
  required String location,
  required List<RouteBase> routes,
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Key? boundaryKey,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
      ...routes,
    ],
    errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
  );
  addTearDown(router.dispose);
  Widget app = ProviderScope(
    overrides: [...h.overrides, ...extra],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: GhinaTheme.light(),
      darkTheme: GhinaTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  if (boundaryKey != null) app = RepaintBoundary(key: boundaryKey, child: app);
  await tester.pumpWidget(app);
  router.push(location);
  await settle(tester);
  return router;
}

/// Lets streams, futures and entrance animations run (never pumpAndSettle:
/// the mascot animates forever).
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Flushes toasts/timers so the test ends cleanly.
Future<void> drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 1));
}

/// Scrolls the page's main (outermost) scrollable until [finder] is built
/// and fully on screen.
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
}
