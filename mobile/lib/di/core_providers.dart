/// Composition root, part 1: infrastructure and repository bindings.
///
/// Screens should not need these directly — use the use-case providers in
/// `usecase_providers.dart`. Tests override [appDatabaseProvider],
/// [tokenStoreProvider], [syncApiProvider], [photoStoreProvider], [clockProvider] and
/// [syncTriggersProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/clock.dart';
import '../core/config.dart';
import '../data/datasources/local/app_database.dart';
import '../data/datasources/remote/api_client.dart';
import '../data/datasources/remote/auth_api.dart';
import '../data/datasources/remote/sync_api.dart';
import '../data/datasources/remote/token_store.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/content_repositories.dart';
import '../data/repositories/finance_repositories.dart';
import '../data/repositories/life_repositories.dart';
import '../data/repositories/local_store.dart';
import '../data/repositories/notes_repositories.dart';
import '../data/repositories/photo_store.dart';
import '../data/repositories/task_repositories.dart';
import '../data/sync/outbox.dart';
import '../data/sync/sync_engine.dart';
import '../data/sync/sync_triggers.dart';
import '../domain/repositories/repositories.dart';
import '../domain/usecases/task_usecases.dart' show TickSource;

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// "Now" right away and at every minute boundary — drives focus mode, overdue
/// flags and reminders. Tests override it with a controllable stream.
final tickSourceProvider = Provider<TickSource>((ref) {
  final clock = ref.watch(clockProvider);
  return () => minuteTicks(clock);
});

final apiBaseUrlProvider = Provider<String>((ref) => AppConfig.apiBaseUrl);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final photoStoreProvider = Provider<PhotoStore>((ref) => FilePhotoStore());

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokens: ref.watch(tokenStoreProvider),
    onUnauthorized: () => ref.read(authRepositoryImplProvider).onUnauthorized(),
  ),
);

final Provider<AuthApi> authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

final syncApiProvider = Provider<SyncApi>(
  (ref) => DioSyncApi(ref.watch(apiClientProvider)),
);

final outboxProvider = Provider<Outbox>((ref) {
  final o = Outbox(ref.watch(appDatabaseProvider));
  ref.onDispose(o.dispose);
  return o;
});

final localStoreProvider = Provider<LocalStore>(
  (ref) => LocalStore(
    ref.watch(appDatabaseProvider),
    ref.watch(outboxProvider),
    ref.watch(clockProvider),
  ),
);

/// Null disables automatic lifecycle/connectivity/timer triggers (tests).
final syncTriggersProvider = Provider<SyncTriggerSource?>(
  (ref) => FlutterSyncTriggers(),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final e = SyncEngine(
    db: ref.watch(appDatabaseProvider),
    outbox: ref.watch(outboxProvider),
    api: ref.watch(syncApiProvider),
    photos: ref.watch(photoStoreProvider),
    clock: ref.watch(clockProvider),
    triggers: ref.watch(syncTriggersProvider),
  );
  ref.onDispose(e.dispose);
  return e;
});

final Provider<AuthRepositoryImpl> authRepositoryImplProvider =
    Provider<AuthRepositoryImpl>(
      (ref) => AuthRepositoryImpl(
        api: ref.watch(authApiProvider),
        tokens: ref.watch(tokenStoreProvider),
        db: ref.watch(appDatabaseProvider),
      ),
    );

// ---------------------------------------------------------------- domain bindings

final syncServiceProvider = Provider<SyncService>(
  (ref) => ref.watch(syncEngineProvider),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(authRepositoryImplProvider),
);
final unitOfWorkProvider = Provider<UnitOfWork>(
  (ref) => DriftUnitOfWork(ref.watch(localStoreProvider)),
);
final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => DriftWalletRepository(ref.watch(localStoreProvider)),
);
final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => DriftCategoryRepository(ref.watch(localStoreProvider)),
);
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => DriftTransactionRepository(
    ref.watch(localStoreProvider),
    ref.watch(photoStoreProvider),
  ),
);
final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => DriftBudgetRepository(ref.watch(localStoreProvider)),
);
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => DriftSubscriptionRepository(ref.watch(localStoreProvider)),
);
final plannedRepositoryProvider = Provider<PlannedRepository>(
  (ref) => DriftPlannedRepository(ref.watch(localStoreProvider)),
);
final prayerRepositoryProvider = Provider<PrayerRepository>(
  (ref) => DriftPrayerRepository(ref.watch(localStoreProvider)),
);
final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => DriftHealthRepository(ref.watch(localStoreProvider)),
);
final foodRepositoryProvider = Provider<FoodRepository>(
  (ref) => DriftFoodRepository(
    ref.watch(localStoreProvider),
    ref.watch(photoStoreProvider),
  ),
);
final taskAreaRepositoryProvider = Provider<TaskAreaRepository>(
  (ref) => DriftTaskAreaRepository(ref.watch(localStoreProvider)),
);
final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => DriftTaskRepository(ref.watch(localStoreProvider)),
);
final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => DriftNoteRepository(
    ref.watch(localStoreProvider),
    ref.watch(photoStoreProvider),
  ),
);
final noteLabelRepositoryProvider = Provider<NoteLabelRepository>(
  (ref) => DriftNoteLabelRepository(ref.watch(localStoreProvider)),
);
final socialAccountRepositoryProvider = Provider<SocialAccountRepository>(
  (ref) => DriftSocialAccountRepository(ref.watch(localStoreProvider)),
);
final contentItemRepositoryProvider = Provider<ContentItemRepository>(
  (ref) => DriftContentItemRepository(
    ref.watch(localStoreProvider),
    ref.watch(photoStoreProvider),
  ),
);
final contentPostRepositoryProvider = Provider<ContentPostRepository>(
  (ref) => DriftContentPostRepository(ref.watch(localStoreProvider)),
);
final contentPillarRepositoryProvider = Provider<ContentPillarRepository>(
  (ref) => DriftContentPillarRepository(ref.watch(localStoreProvider)),
);
final defaultsSeedStateProvider = Provider<DefaultsSeedState>(
  (ref) => DriftDefaultsSeedState(ref.watch(appDatabaseProvider)),
);
