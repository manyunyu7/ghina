// Shared test harness for the transactions / wallets / categories screens:
// the real data layer on an in-memory drift database, fake sync server, fake
// auth, in-memory game store and a fixed clock.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game_store.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/categories/pages/categories_page.dart';
import 'package:ghina/presentation/features/categories/pages/category_form_page.dart';
import 'package:ghina/presentation/features/transactions/pages/transaction_form_page.dart';
import 'package:ghina/presentation/features/transactions/pages/transactions_page.dart';
import 'package:ghina/presentation/features/wallets/pages/wallet_form_page.dart';
import 'package:ghina/presentation/features/wallets/pages/wallets_page.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../data/fake_server.dart';

final testNow = DateTime(2026, 9, 23, 12);

class _FakeAuth implements AuthRepository {
  static const user = AppUser(
    id: 'u1',
    name: 'Ghina Putri',
    email: 'g@x.id',
    currency: 'IDR',
    syncEpoch: 'epoch-1',
  );
  final _expired = StreamController<void>.broadcast();

  @override
  Future<AppUser?> restoreSession() async => null;
  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async => user;
  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async => user;
  @override
  Future<AppUser> signInWithGoogle(String idToken) async => user;
  @override
  Future<AppUser> refreshProfile() async => user;
  @override
  Future<AppUser> updateProfile({String? name, String? currency}) async => user;
  @override
  Future<void> signOut() async {}
  @override
  Stream<void> get sessionExpired => _expired.stream;
}

/// A container wired like the app, but everything in memory.
ProviderContainer makeContainer({DateTime? now}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return ProviderContainer(
    overrides: [
      ...buildGameOverrides(store: InMemoryGameStore()),
      gameTickProvider.overrideWith((ref) => const Stream.empty()),
      appDatabaseProvider.overrideWith((ref) {
        final db = AppDatabase.memory();
        ref.onDispose(db.close);
        return db;
      }),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      syncApiProvider.overrideWithValue(FakeServer()),
      photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
      syncTriggersProvider.overrideWithValue(null),
      clockProvider.overrideWithValue(FixedClock(now ?? testNow)),
      authRepositoryProvider.overrideWithValue(_FakeAuth()),
      currencyProvider.overrideWithValue('IDR'),
    ],
  );
}

/// Router with the pages of these three features (plus a stub home).
GoRouter makeRouter(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/home',
      builder: (_, _) => const Scaffold(body: Text('HOME')),
    ),
    GoRoute(path: '/transactions', builder: (_, _) => const TransactionsPage()),
    GoRoute(
      path: '/transactions/new',
      builder: (_, _) => const TransactionFormPage(),
    ),
    GoRoute(
      path: '/transactions/:id',
      builder: (_, s) => TransactionFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(path: '/wallets', builder: (_, _) => const WalletsPage()),
    GoRoute(path: '/wallets/new', builder: (_, _) => const WalletFormPage()),
    GoRoute(
      path: '/wallets/:id',
      builder: (_, s) => WalletFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(path: '/categories', builder: (_, _) => const CategoriesPage()),
    GoRoute(
      path: '/categories/new',
      builder: (_, _) => const CategoryFormPage(),
    ),
    GoRoute(
      path: '/categories/:id',
      builder: (_, s) => CategoryFormPage(id: s.pathParameters['id']),
    ),
  ],
);

/// Pumps the app at [location]. Returns the router so tests can inspect it.
Future<GoRouter> pumpApp(
  WidgetTester tester,
  ProviderContainer c,
  String location, {
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
  final router = makeRouter(location);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: UncontrolledProviderScope(
        container: c,
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
  return router;
}

/// Lets streams from the in-memory DB deliver, then advances frames. Never uses
/// pumpAndSettle (the mascot/caret animate forever).
Future<void> settle(WidgetTester tester, [int rounds = 4]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the tree and disposes the container, flushing timers.
Future<void> tearDownApp(WidgetTester tester, ProviderContainer c) async {
  await tester.pump(const Duration(seconds: 3)); // toasts
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump(const Duration(seconds: 1));
}

/// Runs an async data call outside the fake zone.
Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
    (await tester.runAsync(body)) as T;

// ---------------------------------------------------------------- screenshots

bool _fontsLoaded = false;

Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final nunito = File('assets/fonts/Nunito.ttf');
  if (nunito.existsSync()) {
    final loader = FontLoader('Nunito')
      ..addFont(Future.value(ByteData.sublistView(nunito.readAsBytesSync())));
    await loader.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (f.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
    }
  }
}

String? get shotsDir => Platform.environment['GHINA_SHOTS_DIR'];

Future<void> saveShot(WidgetTester tester, Key key, String name) async {
  final dir = shotsDir;
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$dir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Scrolls the page's main ListView until [finder] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView).first,
    const Offset(0, -250),
  );
  await tester.pump();
}
