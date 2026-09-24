import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/game/activity.dart';
import 'package:ghina/domain/game/game_store.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/di/notes_content_providers.dart';
import 'package:ghina/di/usecase_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:ghina/presentation/state/sync_status_provider.dart';

import '../data/fake_server.dart';

class FakeAuthRepository implements AuthRepository {
  AppUser? stored;
  final expired = StreamController<void>.broadcast();
  static const user = AppUser(
    id: 'u1',
    name: 'Ghina Putri',
    email: 'g@x.id',
    currency: 'IDR',
    syncEpoch: 'epoch-1',
  );

  @override
  Future<AppUser?> restoreSession() async => stored;
  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async => stored = user;
  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async => stored = user;
  @override
  Future<AppUser> signInWithGoogle(String idToken) async => stored = user;
  @override
  Future<AppUser> refreshProfile() async => stored ?? user;
  @override
  Future<AppUser> updateProfile({String? name, String? currency}) async =>
      stored = AppUser(
        id: user.id,
        name: name ?? user.name,
        email: user.email,
        currency: currency ?? user.currency,
        syncEpoch: user.syncEpoch,
      );
  @override
  Future<void> signOut() async => stored = null;
  @override
  Stream<void> get sessionExpired => expired.stream;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late ProviderContainer c;
  late FakeServer server;
  late FakeAuthRepository auth;

  setUp(() {
    server = FakeServer();
    auth = FakeAuthRepository();
    c = ProviderContainer(
      overrides: [
        ...buildGameOverrides(store: InMemoryGameStore()),
        gameTickProvider.overrideWith((ref) => const Stream.empty()),
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase.memory();
          ref.onDispose(db.close);
          return db;
        }),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        syncApiProvider.overrideWithValue(server),
        photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
        syncTriggersProvider.overrideWithValue(null),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 9, 23, 12))),
        authRepositoryProvider.overrideWithValue(auth),
        tickSourceProvider.overrideWithValue(
          () => Stream.value(DateTime(2026, 9, 24, 10)), // Thu 10:00
        ),
      ],
    );
  });
  tearDown(() => c.dispose());

  Future<T> next<T>(StreamProvider<T> p, bool Function(T) until) async {
    final done = Completer<T>();
    final sub = c.listen<AsyncValue<T>>(p, (_, v) {
      final value = v.value;
      if (value != null && until(value) && !done.isCompleted) {
        done.complete(value);
      }
    }, fireImmediately: true);
    try {
      return await done.future.timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
  }

  test('use cases and reactive providers are wired end to end', () async {
    final w = (await c.read(createWalletProvider)(
      const WalletInput(name: 'Tunai', initialBalance: 100000),
    )).valueOrThrow;
    await c.read(seedDefaultCategoriesProvider)();
    final r = await c.read(createTransactionProvider)(
      TransactionInput(
        type: TxType.expense,
        amount: 25000,
        walletId: w.id,
        date: DateTime(2026, 9, 23, 9),
      ),
    );
    expect(r, isA<Ok<Transaction>>());

    final wallets = await next(
      watchWalletsProvider,
      (l) => l.isNotEmpty && l.first.balance == 75000,
    );
    expect(wallets.single.name, 'Tunai');

    final dash = await next(
      watchDashboardProvider,
      (d) => d.monthExpense == 25000,
    );
    expect(dash.totalBalance, 75000);
    expect(dash.todayExpense, 25000);

    final days = await next(
      watchTransactionsByDayProvider(
        TransactionFilter(month: const YearMonth(2026, 9)),
      ),
      (d) => d.isNotEmpty,
    );
    expect(days.single.items.single.wallet?.name, 'Tunai');

    final status = await next(syncStatusProvider, (s) => s.pendingCount > 0);
    expect(status.pendingCount, 2 + defaultCategories.length);

    expect(await c.read(syncNowProvider)(), isA<Ok<void>>());
    expect(server.balanceOf(w.id), 75000);
    expect(
      server.rows[SyncEntity.categories],
      hasLength(defaultCategories.length),
    );
    final synced = await next(syncStatusProvider, (s) => s.pendingCount == 0);
    expect(synced.phase, SyncPhase.idle);
  });

  test('game sources are wired to the local data', () async {
    final w = (await c.read(createWalletProvider)(
      const WalletInput(name: 'Tunai'),
    )).valueOrThrow;
    await c.read(createTransactionProvider)(
      TransactionInput(
        type: TxType.expense,
        amount: 1000,
        walletId: w.id,
        date: DateTime(2026, 9, 23, 9),
      ),
    );
    await c.read(togglePrayerProvider)(DateTime(2026, 9, 23), Prayer.subuh);
    final sub = c.listen(gameSummaryProvider, (_, _) {});
    final summary = await c.read(gameSummaryProvider.future);
    sub.close();
    expect(summary.totalXp, greaterThan(0));
  });

  test('tasks & photos providers are wired end to end', () async {
    final seeded = await c.read(seedDefaultTaskAreasProvider)('u1');
    expect(seeded.valueOrThrow, 2);
    final areas = await next(watchTaskAreasProvider, (l) => l.length == 2);
    expect(areas.map((a) => a.code), ['KERJA', 'LIFE']);
    final kerja = areas.first.id;

    final t = (await c.read(createTaskProvider)(
      TaskInput(
        areaId: kerja,
        title: 'Kirim revisi',
        bucket: TaskBucket.fire,
        dueDate: DateTime(2026, 9, 24),
        dueTime: '14:00',
        remindBefore: 30,
        recurrence: const Recurrence.daily(),
      ),
    )).valueOrThrow;

    final focus = await next(
      watchFocusAreasProvider,
      (f) => f.areas.isNotEmpty,
    );
    expect(focus.ids, [kerja]);
    final board = await next(
      watchTaskBoardProvider(TaskFilter.focus),
      (b) => !b.isEmpty,
    );
    expect(board.section(TaskBucket.fire).tasks.single.id, t.id);
    final home = await next(
      watchTaskHomeProvider,
      (h) => h.fireTasks.isNotEmpty,
    );
    expect(home.fireTasks.single.tag, '[KERJA-FIRE]');
    final reminders = await next(watchRemindersProvider, (r) => r.isNotEmpty);
    expect(reminders.single.title, '[KERJA-FIRE] Kirim revisi');

    final done = (await c.read(completeTaskProvider)(t.id)).valueOrThrow;
    expect(done.next!.dueDate, '2026-09-25');
    final doneList = await next(
      watchTasksProvider(const TaskFilter(status: TaskStatusFilter.done)),
      (l) => l.isNotEmpty,
    );
    expect(doneList.single.id, t.id);

    // Completed tasks reach the game engine as task events.
    final events = await next(
      activityEventsSourceProvider,
      (l) => l.any((e) => e.kind == ActivityKind.task),
    );
    final taskEvents = events.where((e) => e.kind == ActivityKind.task);
    expect(taskEvents.single.taskBucket, 'fire');
    expect(taskEvents.single.taskSeriesId, t.id);

    final w = (await c.read(createWalletProvider)(
      const WalletInput(name: 'Tunai'),
    )).valueOrThrow;
    final tx = (await c.read(createTransactionProvider)(
      TransactionInput(
        type: TxType.expense,
        amount: 1000,
        walletId: w.id,
        date: DateTime(2026, 9, 23, 9),
        photos: const [TransactionPhoto.local('/tmp/nota.jpg')],
      ),
    )).valueOrThrow;
    expect(tx.photos.single.isPending, isTrue);
    await c.read(addTransactionPhotosProvider)(tx.id, ['/tmp/nota2.jpg']);
    expect(await c.read(syncNowProvider)(), isA<Ok<void>>());
    expect(
      server.rows[SyncEntity.transactions]![tx.id]!['photos'],
      hasLength(2),
    );
    expect(server.rows[SyncEntity.tasks], hasLength(2));
  });

  test('session controller: restore → sign in → sign out', () async {
    expect(c.read(sessionControllerProvider), isA<SessionLoading>());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(sessionControllerProvider), isA<SignedOut>());

    final r = await c
        .read(sessionControllerProvider.notifier)
        .signIn('g@x.id', 'rahasia123');
    expect(r.isOk, isTrue);
    expect(c.read(currentUserProvider)?.displayName, 'Ghina');
    expect(c.read(syncEngineProvider).isStarted, isTrue);

    await c
        .read(sessionControllerProvider.notifier)
        .updateProfile(currency: 'USD');
    expect(c.read(currencyProvider), 'USD');

    auth.expired.add(null);
    await Future<void>.delayed(Duration.zero);
    final s = c.read(sessionControllerProvider);
    expect(s, isA<SignedOut>());
    expect((s as SignedOut).expired, isTrue);
    expect(c.read(syncEngineProvider).isStarted, isFalse);

    final bad = await c
        .read(sessionControllerProvider.notifier)
        .signIn('not-an-email', 'x');
    expect(bad.isOk, isFalse);
  });

  test('notes & content providers are wired end to end', () async {
    final l = (await c.read(createNoteLabelProvider)(
      const NoteLabelInput(name: 'Ide Konten', pinnedTab: true),
    )).valueOrThrow;
    final n = (await c.read(createNoteProvider)(
      NoteInput(title: 'Ide', body: 'Rp 25.000 https://x.id', labelIds: [l.id]),
    )).valueOrThrow;
    expect(
      (await next(
        watchNotesProvider(NoteFilter.all),
        (v) => v.isNotEmpty,
      )).single.labels.single.id,
      l.id,
    );
    expect(
      (await next(watchNoteTabsProvider, (v) => v.isNotEmpty)).single.name,
      'Ide Konten',
    );
    expect(
      (await next(watchIdeaInboxProvider, (v) => v.isNotEmpty)).single.id,
      n.id,
    );
    expect(
      (await next(
        watchNoteProvider(n.id),
        (v) => v != null,
      ))!.note.links.single.url,
      'https://x.id',
    );

    final a = (await c.read(createSocialAccountProvider)(
      const SocialAccountInput(
        platform: SocialPlatform.instagram,
        handle: '@ghina',
        targetPerWeek: 2,
      ),
    )).valueOrThrow;
    final conv = (await c.read(convertNoteToContentProvider)(
      n.id,
    )).valueOrThrow;
    final post = (await c.read(createContentPostProvider)(
      conv.item.id,
      ContentPostInput(
        accountId: a.id,
        scheduledAt: DateTime(2026, 9, 24, 19),
        remindBefore: 30,
      ),
    )).valueOrThrow;
    final board = await next(
      watchContentBoardProvider(ContentFilter.all),
      (b) => b.column(ContentStage.terjadwal).items.isNotEmpty,
    );
    expect(board.total, 1);
    expect((await next(watchIdeaInboxProvider, (v) => v.isEmpty)), isEmpty);
    final today = await next(watchTodayPostsProvider, (t) => !t.isEmpty);
    expect(today.posts.single.id, post.id);
    final reminders = await next(watchRemindersProvider, (r) => r.isNotEmpty);
    expect(reminders.single.title, '[IG-TAYANG] Ide');
    final cal = await next(
      watchContentCalendarProvider(weekRange(DateTime(2026, 9, 24))),
      (x) => x.days.isNotEmpty,
    );
    expect(cal.weeks.single.accounts.single.label, 'IG: 1/2');
    await c.read(markPostPostedProvider)(post.id);
    final report = await next(
      watchContentReportProvider((
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      )),
      (r) => r.totals.posted == 1,
    );
    expect(report.accounts.single.posted, 1);
    expect(
      (await next(
        watchContentItemProvider(conv.item.id),
        (v) => v?.stage == ContentStage.tayang,
      ))!.note!.id,
      n.id,
    );
    expect(await next(watchContentPillarsProvider, (_) => true), isEmpty);
    expect(
      (await c.read(seedDefaultContentPillarsProvider)('u1')).valueOrThrow,
      5,
    );
    expect(
      (await next(watchContentPillarsProvider, (v) => v.isNotEmpty)),
      hasLength(5),
    );
    expect(await next(watchMetricsDueProvider, (_) => true), isEmpty);
    expect(
      (await next(
        watchSocialAccountsProvider,
        (v) => v.isNotEmpty,
      )).single.code,
      'IG',
    );
    expect(
      (await next(watchAllSocialAccountsProvider, (v) => v.isNotEmpty)),
      hasLength(1),
    );
    expect(
      await next(
        watchContentPostProvider(post.id),
        (v) => v?.post.isPosted ?? false,
      ),
      isNotNull,
    );
    expect(
      await next(watchNoteLabelsProvider, (v) => v.isNotEmpty),
      hasLength(1),
    );
  });
}
