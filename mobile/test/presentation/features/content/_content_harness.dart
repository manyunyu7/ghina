/// Shared setup for the Konten screen tests: real use cases over in-memory
/// repositories, a fixed clock and the game engine (for XP toasts).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/content/content_actions.dart';
import 'package:ghina/presentation/features/content/pages/content_accounts_page.dart';
import 'package:ghina/presentation/features/content/pages/content_item_page.dart';
import 'package:ghina/presentation/features/content/pages/content_page.dart';
import 'package:ghina/presentation/features/content/pages/content_post_page.dart';
import 'package:ghina/presentation/features/content/pages/content_report_page.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/notifications/notification_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/fakes.dart';
import '../profile/_harness.dart'
    show FakeFoodRepository, FakeHealthRepository, FakePrayerRepository;
import '../tasks/_tasks_harness.dart' show FakeSyncService;

export '../tasks/_tasks_harness.dart' show loadFonts;

/// Thursday 24 September 2026, 10:00.
final contentNow = DateTime(2026, 9, 24, 10);

const contentUser = AppUser(
  id: 'u1',
  name: 'Ghina Putri',
  email: 'ghina@contoh.id',
  currency: 'IDR',
  syncEpoch: 'e1',
);

class FakeSeedState implements DefaultsSeedState {
  FakeSeedState({this.contentSeeded = true});
  bool contentSeeded;
  @override
  Future<bool> contentServerSeeded() async => contentSeeded;
  @override
  Future<bool> notesServerSeeded() async => true;
}

List<RouteBase> get contentRoutes => [
  GoRoute(path: '/content', builder: (_, _) => const ContentPage()),
  GoRoute(
    path: '/content/accounts',
    builder: (_, _) => const ContentAccountsPage(),
  ),
  GoRoute(
    path: '/content/report',
    builder: (_, _) => const ContentReportPage(),
  ),
  GoRoute(path: '/content/new', builder: (_, _) => const ContentItemPage()),
  GoRoute(
    path: '/content/posts/:id',
    builder: (_, s) => ContentPostPage(id: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/content/:id',
    builder: (_, s) => ContentItemPage(id: s.pathParameters['id']),
  ),
];

SocialAccount account(
  String id, {
  SocialPlatform platform = SocialPlatform.instagram,
  String handle = '@ghina.hemat',
  int? target,
  int order = 0,
}) => SocialAccount(
  id: id,
  platform: platform,
  handle: handle,
  color: platform.color,
  targetPerWeek: target,
  sortOrder: order,
  createdAt: contentNow,
  updatedAt: contentNow,
);

ContentItem item(
  String id,
  String title, {
  ContentStage stage = ContentStage.ide,
  ContentFormat? format,
  String? pillar,
  Sponsor? sponsor,
  List<ChecklistItem> checklist = const [],
  Map<ContentStage, DateTime> reached = const {},
}) => ContentItem(
  id: id,
  title: title,
  stage: stage,
  format: format,
  pillar: pillar,
  sponsor: sponsor,
  checklist: checklist,
  stageReachedAt: reached,
  createdAt: contentNow.subtract(const Duration(days: 5)),
  updatedAt: contentNow.subtract(const Duration(days: 5)),
);

ContentPost post(
  String id,
  String itemId,
  String accountId, {
  PostStatus status = PostStatus.draft,
  DateTime? scheduledAt,
  DateTime? postedAt,
  String caption = '',
  String hashtags = '',
  PostMetrics metrics = PostMetrics.empty,
  int? remindBefore,
}) => ContentPost(
  id: id,
  contentId: itemId,
  accountId: accountId,
  status: status,
  scheduledAt: scheduledAt,
  postedAt: postedAt,
  caption: caption,
  hashtags: hashtags,
  metrics: metrics,
  metricsAt: metrics.isEmpty ? null : postedAt,
  remindBefore: remindBefore,
  createdAt: contentNow.subtract(const Duration(days: 5)),
  updatedAt: contentNow.subtract(const Duration(days: 5)),
);

ContentPillar pillar(String id, String name, String color, int order) =>
    ContentPillar(
      id: id,
      name: name,
      color: color,
      sortOrder: order,
      createdAt: contentNow,
      updatedAt: contentNow,
    );

Wallet wallet(String id, String name) => Wallet(
  id: id,
  name: name,
  type: WalletType.bank,
  balance: 1000000,
  syncedBalance: 1000000,
  currency: 'IDR',
  color: '#1cb0f6',
  icon: 'bank',
  archived: false,
  createdAt: contentNow,
  updatedAt: contentNow,
);

class ContentHarness {
  final clock = FixedClock(contentNow);
  final gameStore = InMemoryGameStore({
    // Intens goal + content badges seen: no full-screen celebration covers
    // the page mid-test.
    GameLocalState.storageKey: GameLocalState(
      onboardingDone: true,
      lastSeenLevel: 1,
      dailyGoalHistory: [
        DailyGoalChange(GameDate(2026, 1, 1), DailyGoalLevel.intens),
      ],
      seenAchievements: const {
        'first_content_post',
        'first_sponsor',
        'content_consistency_4',
        'content_posts_50',
        'first_transaction',
      },
    ).encode(),
  });
  final items = FakeContentItemRepository();
  final posts = FakeContentPostRepository();
  final accounts = FakeSocialAccountRepository();
  final pillars = FakeContentPillarRepository();
  final notes = FakeNoteRepository();
  final labels = FakeNoteLabelRepository();
  final seed = FakeSeedState();
  final wallets = FakeWalletRepository();
  final categories = FakeCategoryRepository();
  final transactions = FakeTransactionRepository();
  final opened = <String>[];
  bool openResult = true;

  void seedBasics() {
    accounts.s
      ..put(account('ig', target: 3))
      ..put(
        account(
          'tt',
          platform: SocialPlatform.tiktok,
          handle: 'ghinahemat',
          target: 2,
          order: 1,
        ),
      );
    pillars.s
      ..put(pillar('p1', 'Edukasi', '#1CB0F6', 0))
      ..put(pillar('p2', 'Hiburan', '#FF9600', 1));
  }

  List<Override> get overrides => [
    ...buildGameOverrides(store: gameStore),
    gameTickProvider.overrideWith((ref) => const Stream.empty()),
    clockProvider.overrideWithValue(clock),
    tickSourceProvider.overrideWithValue(() => Stream.value(contentNow)),
    contentItemRepositoryProvider.overrideWithValue(items),
    contentPostRepositoryProvider.overrideWithValue(posts),
    socialAccountRepositoryProvider.overrideWithValue(accounts),
    contentPillarRepositoryProvider.overrideWithValue(pillars),
    noteRepositoryProvider.overrideWithValue(notes),
    noteLabelRepositoryProvider.overrideWithValue(labels),
    defaultsSeedStateProvider.overrideWithValue(seed),
    taskRepositoryProvider.overrideWithValue(FakeTaskRepository()),
    taskAreaRepositoryProvider.overrideWithValue(FakeTaskAreaRepository()),
    walletRepositoryProvider.overrideWithValue(wallets),
    categoryRepositoryProvider.overrideWithValue(categories),
    transactionRepositoryProvider.overrideWithValue(transactions),
    budgetRepositoryProvider.overrideWithValue(FakeBudgetRepository()),
    prayerRepositoryProvider.overrideWithValue(FakePrayerRepository()),
    healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
    foodRepositoryProvider.overrideWithValue(FakeFoodRepository()),
    unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
    syncServiceProvider.overrideWithValue(FakeSyncService()),
    currentUserProvider.overrideWithValue(contentUser),
    remindersSourceProvider.overrideWith((ref) => Stream.value(const [])),
    contentUrlOpenerProvider.overrideWithValue((url) async {
      opened.add(url);
      return openResult;
    }),
  ];
}

/// Pumps [location] inside a router with the content routes; other routes
/// render `route:<uri>`. `/` is a "HOME" stub so pushes can pop.
Future<GoRouter> pumpContent(
  WidgetTester tester,
  ContentHarness h, {
  required String location,
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Key? boundaryKey,
  Widget? home,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            home ?? const Scaffold(body: Center(child: Text('HOME'))),
      ),
      ...contentRoutes,
    ],
    errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: h.overrides,
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
  if (location != '/') router.push(location);
  await settle(tester);
  return router;
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets the reward tracker time out and toasts disappear.
Future<void> settleLong(WidgetTester tester) => settle(tester, 40);

/// The page's vertical scrollable (not a horizontal chip row).
final vertical = find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;
