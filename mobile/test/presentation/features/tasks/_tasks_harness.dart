/// Shared setup for the Tugas screen tests: real use cases over in-memory
/// repositories, a fixed clock, the game engine (for XP toasts) and fake
/// notification settings / scheduler.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/notifications/notifications.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/notifications/notification_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/fakes.dart';
import '../profile/_harness.dart'
    show FakeFoodRepository, FakeHealthRepository, FakePrayerRepository;

/// Wednesday 23 September 2026, 10:00 (inside Kerjaan's Mon–Fri 09–17 schedule).
final tasksNow = DateTime(2026, 9, 23, 10);

const tasksUser = AppUser(
  id: 'u1',
  name: 'Ghina Putri',
  email: 'ghina@contoh.id',
  currency: 'IDR',
  syncEpoch: 'e1',
);

class FakeSettingsStore implements NotificationSettingsStore {
  FakeSettingsStore([this.value = const NotificationSettings()]);
  NotificationSettings value;

  @override
  Future<NotificationSettings> load() async => value;
  @override
  Future<void> save(NotificationSettings settings) async => value = settings;
}

/// Scheduler with a controllable permission and tap stream.
class FakeScheduler implements DeviceReminderScheduler {
  FakeScheduler({this.status = NotificationPermissionStatus.granted});

  NotificationPermissionStatus status;
  bool grantOnRequest = true;
  int requests = 0;
  int settingsOpened = 0;
  final taps = StreamController<String>.broadcast();
  List<Reminder>? lastScheduled;

  @override
  Future<bool> ensurePermission() async {
    requests++;
    if (grantOnRequest) status = NotificationPermissionStatus.granted;
    return status == NotificationPermissionStatus.granted;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async =>
      lastScheduled = reminders;
  @override
  Future<void> cancelAll() async {}
  @override
  Stream<String> get openedRoutes => taps.stream;
  @override
  Future<NotificationPermissionStatus> permissionStatus() async => status;
  @override
  Future<bool> canScheduleExact() async => true;
  @override
  Future<bool> requestExactAlarms() async => true;
  @override
  Future<void> openSystemSettings() async => settingsOpened++;
  @override
  bool preferExact = false;
}

class FakeSyncService implements SyncService {
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async {}
  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.initial);
  @override
  Future<void> resetLocalData() async {}
}

TaskArea area(
  String id,
  String name,
  String code, {
  String color = '#1cb0f6',
  String icon = 'briefcase',
  AreaSchedule? schedule,
  int order = 0,
  bool archived = false,
}) => TaskArea(
  id: id,
  name: name,
  code: code,
  color: color,
  icon: icon,
  schedule: schedule,
  sortOrder: order,
  archived: archived,
  createdAt: tasksNow,
  updatedAt: tasksNow,
);

Task task(
  String id,
  String title, {
  String areaId = 'kerja',
  TaskBucket bucket = TaskBucket.want,
  String? dueDate,
  String? dueTime,
  int? remindBefore,
  Recurrence? recurrence,
  double sortOrder = 0,
  double? amount,
  String? walletId,
  String? categoryId,
  bool done = false,
}) => Task(
  id: id,
  areaId: areaId,
  title: title,
  bucket: bucket,
  dueDate: dueDate,
  dueTime: dueTime,
  remindBefore: remindBefore,
  recurrence: recurrence,
  seriesId: recurrence == null ? null : id,
  sortOrder: sortOrder,
  amount: amount,
  walletId: walletId,
  categoryId: categoryId,
  done: done,
  doneAt: done ? tasksNow : null,
  createdAt: tasksNow.subtract(const Duration(days: 1)),
  updatedAt: tasksNow,
);

Wallet wallet(String id, String name) => Wallet(
  id: id,
  name: name,
  type: WalletType.cash,
  balance: 500000,
  syncedBalance: 500000,
  currency: 'IDR',
  color: '#22c55e',
  icon: 'cash',
  archived: false,
  createdAt: tasksNow,
  updatedAt: tasksNow,
);

class TasksHarness {
  TasksHarness({NotificationPermissionStatus? permission})
    : scheduler = FakeScheduler(
        status: permission ?? NotificationPermissionStatus.granted,
      ) {
    areas.tasks = tasks;
  }

  final clock = FixedClock(tasksNow);
  final gameStore = InMemoryGameStore({
    GameLocalState.storageKey: const GameLocalState(
      onboardingDone: true,
    ).encode(),
  });
  final tasks = FakeTaskRepository();
  final areas = FakeTaskAreaRepository();
  final wallets = FakeWalletRepository();
  final categories = FakeCategoryRepository();
  final transactions = FakeTransactionRepository();
  final budgets = FakeBudgetRepository();
  final prayers = FakePrayerRepository();
  final health = FakeHealthRepository();
  final food = FakeFoodRepository();
  final settings = FakeSettingsStore();
  final FakeScheduler scheduler;

  /// Kerjaan (scheduled, focus now) + Keseharian (anytime).
  void seedAreas() {
    areas.s.put(
      area(
        'kerja',
        'Kerjaan',
        'KERJA',
        schedule: AreaSchedule.workHours,
        order: 0,
      ),
    );
    areas.s.put(
      area(
        'life',
        'Keseharian',
        'LIFE',
        color: '#58cc02',
        icon: 'home',
        order: 1,
      ),
    );
  }

  List<Override> get overrides => [
    ...buildGameOverrides(store: gameStore),
    gameTickProvider.overrideWith((ref) => const Stream.empty()),
    clockProvider.overrideWithValue(clock),
    tickSourceProvider.overrideWithValue(() => Stream.value(tasksNow)),
    taskRepositoryProvider.overrideWithValue(tasks),
    taskAreaRepositoryProvider.overrideWithValue(areas),
    walletRepositoryProvider.overrideWithValue(wallets),
    categoryRepositoryProvider.overrideWithValue(categories),
    transactionRepositoryProvider.overrideWithValue(transactions),
    // The rest of the game's sources, so XP toasts see a loaded summary.
    budgetRepositoryProvider.overrideWithValue(budgets),
    prayerRepositoryProvider.overrideWithValue(prayers),
    healthRepositoryProvider.overrideWithValue(health),
    foodRepositoryProvider.overrideWithValue(food),
    unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
    syncServiceProvider.overrideWithValue(FakeSyncService()),
    currentUserProvider.overrideWithValue(tasksUser),
    notificationSettingsStoreProvider.overrideWithValue(settings),
    reminderSchedulerProvider.overrideWithValue(scheduler),
    remindersSourceProvider.overrideWith((ref) => Stream.value(const [])),
  ];
}

bool _fontsLoaded = false;

/// Nunito + Material Icons for screenshots.
Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final nunito = File('assets/fonts/Nunito.ttf');
  if (nunito.existsSync()) {
    await (FontLoader('Nunito')..addFont(
          Future.value(ByteData.sublistView(nunito.readAsBytesSync())),
        ))
        .load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (f.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync()))))
          .load();
    }
  }
}

/// Pumps [location] inside a router with the task routes; other routes render
/// `route:<uri>`. `/` is a "HOME" stub so pushes can pop.
Future<GoRouter> pumpTasks(
  WidgetTester tester,
  TasksHarness h, {
  required String location,
  required List<RouteBase> routes,
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Key? boundaryKey,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
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
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
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
      ),
    ),
  );
  router.push(location);
  await settle(tester);
  return router;
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
