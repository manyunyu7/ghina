import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/repositories/content_repositories.dart';
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/life_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/notes_repositories.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/repositories/task_repositories.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fake_server.dart';

/// Real drift (in memory) + real repositories/use cases + [FakeServer].
class Harness {
  /// Pass [server] to simulate a second device on the same account.
  Harness({FakeServer? server}) : server = server ?? FakeServer() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  final db = AppDatabase.memory();
  late final outbox = Outbox(db);

  /// Client clock runs an hour ahead of the fake server so local edits win LWW.
  final clock = FixedClock(DateTime.utc(2026, 9, 23, 5).toLocal());
  late final store = LocalStore(db, outbox, clock);
  final FakeServer server;
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
  late final transactions = DriftTransactionRepository(store, photos);
  late final budgets = DriftBudgetRepository(store);
  late final subscriptions = DriftSubscriptionRepository(store);
  late final planned = DriftPlannedRepository(store);
  late final prayers = DriftPrayerRepository(store);
  late final health = DriftHealthRepository(store);
  late final food = DriftFoodRepository(store, photos);
  late final uow = DriftUnitOfWork(store);
  late final taskAreas = DriftTaskAreaRepository(store);
  late final tasks = DriftTaskRepository(store);

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
  late final createArea = CreateTaskArea(taskAreas, clock);
  late final deleteArea = DeleteTaskArea(taskAreas);
  late final createTask = CreateTask(
    tasks,
    taskAreas,
    wallets,
    categories,
    clock,
  );
  late final updateTask = UpdateTask(
    tasks,
    taskAreas,
    wallets,
    categories,
    clock,
  );
  late final completeTask = CompleteTask(tasks, createTx, uow, clock);
  late final uncompleteTask = UncompleteTask(tasks, clock);
  late final moveTask = MoveTask(tasks, taskAreas, clock);
  late final reorderTasks = ReorderTasks(tasks, uow, clock);
  late final addPhotos = AddTransactionPhotos(transactions, clock);

  // --- notes & content (docs/notes.md, docs/content.md)
  late final notes = DriftNoteRepository(store, photos);
  late final labels = DriftNoteLabelRepository(store);
  late final accounts = DriftSocialAccountRepository(store);
  late final items = DriftContentItemRepository(store, photos);
  late final posts = DriftContentPostRepository(store);
  late final pillars = DriftContentPillarRepository(store);
  late final seedState = DriftDefaultsSeedState(db);

  late final createNote = CreateNote(notes, clock);
  late final updateNote = UpdateNote(notes, clock);
  late final deleteNote = DeleteNote(notes);
  late final addNotePhotos = AddNotePhotos(notes, clock);
  late final addNoteAudio = AddNoteAudio(notes, clock);
  late final createLabel = CreateNoteLabel(labels, clock);
  late final deleteLabel = DeleteNoteLabel(labels);
  late final createAccount = CreateSocialAccount(accounts, clock);
  late final deleteAccount = DeleteSocialAccount(accounts);
  late final createPillar = CreateContentPillar(pillars, clock);
  late final updatePillar = UpdateContentPillar(pillars, clock);
  late final deletePillar = DeleteContentPillar(pillars);
  late final createItem = CreateContentItem(items, clock);
  late final updateItem = UpdateContentItem(items, clock);
  late final deleteItem = DeleteContentItem(items);
  late final moveStage = MoveContentStage(items, clock);
  late final addContentPhotos = AddContentPhotos(items, clock);
  late final createPost = CreateContentPost(posts, items, accounts, uow, clock);
  late final updatePost = UpdateContentPost(posts, items, uow, clock);
  late final schedulePost = ScheduleContentPost(posts, items, uow, clock);
  late final markPosted = MarkPostPosted(posts, items, uow, clock);
  late final markSkipped = MarkPostSkipped(posts, items, uow, clock);
  late final deletePost = DeleteContentPost(posts, items, uow, clock);
  late final setSponsor = SetContentSponsor(items, clock);
  late final markSponsorPaid = MarkSponsorPaid(
    items,
    categories,
    createTx,
    uow,
    clock,
  );
  late final noteToTask = ConvertNoteToTask(notes, createTask, uow, clock);
  late final noteToContent = ConvertNoteToContent(
    notes,
    items,
    createItem,
    uow,
    clock,
  );
  late final noteToTx = ConvertNoteToTransaction(notes, createTx, uow, clock);
  late final seedLabel = SeedDefaultNoteLabel(labels, seedState, clock);
  late final seedPillars = SeedDefaultContentPillars(
    pillars,
    seedState,
    uow,
    clock,
  );
  late final removePhoto = RemoveTransactionPhoto(transactions, clock);

  /// Emits the client clock once (tests drive time by re-subscribing).
  Stream<DateTime> ticks() => Stream.value(clock.now());

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
