/// Abstract repository interfaces. Implementations (drift + outbox) live in
/// `lib/data/repositories/`. Every mutation writes locally and queues the change
/// for sync; all methods may throw a `Failure`.
library;

import '../../core/dates.dart';
import '../entities/entities.dart';

/// Runs several repository calls atomically (one local DB transaction).
abstract interface class UnitOfWork {
  Future<T> run<T>(Future<T> Function() action);
}

abstract interface class WalletRepository {
  /// Sorted by `createdAt` ascending. Balances include pending local transactions.
  Stream<List<Wallet>> watchAll({bool includeArchived = true});
  Future<List<Wallet>> getAll({bool includeArchived = true});
  Stream<Wallet?> watchById(String id);
  Future<Wallet?> getById(String id);

  /// Insert or update. On update the balance is ignored (server-authoritative);
  /// on insert `syncedBalance` is the initial balance.
  Future<void> save(Wallet wallet);

  /// Deletes the wallet and applies the contract cascade locally: its transactions
  /// (either side of a transfer) are deleted; subscriptions/planned get `walletId = null`.
  Future<void> delete(String id);
}

abstract interface class CategoryRepository {
  /// Sorted by name (case-insensitive).
  Stream<List<TxCategory>> watchAll({CategoryType? type});
  Future<List<TxCategory>> getAll({CategoryType? type});
  Stream<TxCategory?> watchById(String id);
  Future<TxCategory?> getById(String id);
  Future<void> save(TxCategory category);

  /// Cascade: transactions/subscriptions/planned get `categoryId = null`; its budgets
  /// are deleted.
  Future<void> delete(String id);
}

abstract interface class TransactionRepository {
  /// Newest first (`date` desc, then `createdAt` desc). Range bounds are inclusive.
  Stream<List<Transaction>> watch({
    DateTime? from,
    DateTime? to,
    TxType? type,
    String? walletId,
    String? categoryId,
    int? limit,
  });
  Future<List<Transaction>> list({DateTime? from, DateTime? to, TxType? type});
  Stream<Transaction?> watchById(String id);
  Future<Transaction?> getById(String id);

  /// Insert or update. Pending photos (`TransactionPhoto.local`) whose file isn't
  /// in app storage yet are copied there first; local files dropped from the list
  /// are deleted. They are uploaded by the sync engine before the row is pushed.
  Future<void> save(Transaction transaction);

  /// Deletes the row (and its pending local photo files). Tasks referencing it get
  /// `transactionId = null`.
  Future<void> delete(String id);
}

abstract interface class BudgetRepository {
  Stream<List<Budget>> watchByMonth(YearMonth month);

  /// Every budget of every month.
  Stream<List<Budget>> watchAll();
  Stream<Budget?> watchById(String id);
  Future<Budget?> getById(String id);
  Future<Budget?> findByKey(String categoryId, YearMonth month);
  Future<void> save(Budget budget);
  Future<void> delete(String id);
}

abstract interface class SubscriptionRepository {
  Stream<List<Subscription>> watchAll();
  Future<List<Subscription>> getAll();
  Stream<Subscription?> watchById(String id);
  Future<Subscription?> getById(String id);
  Future<void> save(Subscription subscription);
  Future<void> delete(String id);
}

abstract interface class PlannedRepository {
  /// Planned items with `date` in [from, to] (inclusive), sorted by date.
  Stream<List<PlannedTransaction>> watchRange(DateTime from, DateTime to);
  Stream<PlannedTransaction?> watchById(String id);
  Future<PlannedTransaction?> getById(String id);
  Future<void> save(PlannedTransaction item);
  Future<void> delete(String id);
}

abstract interface class PrayerRepository {
  /// Entries with `date` key in [fromKey, toKey] (`YYYY-MM-DD`, inclusive).
  Stream<List<PrayerEntry>> watchRange(String fromKey, String toKey);
  Future<PrayerEntry?> findByKey(String dateKey, Prayer prayer);
  Future<void> save(PrayerEntry entry);
  Future<void> delete(String id);
}

abstract interface class HealthRepository {
  /// Newest first; optional inclusive range.
  Stream<List<HealthEntry>> watchAll({DateTime? from, DateTime? to});
  Stream<HealthEntry?> watchById(String id);
  Future<HealthEntry?> getById(String id);
  Future<void> save(HealthEntry entry);
  Future<void> delete(String id);
}

abstract interface class FoodRepository {
  /// Newest first; optional inclusive range.
  Stream<List<FoodLog>> watchAll({DateTime? from, DateTime? to});
  Stream<FoodLog?> watchById(String id);
  Future<FoodLog?> getById(String id);

  /// Saves the log. When [newPhotoPath] is given, the file is copied into app
  /// storage, stored as `localPhotoPath`, and uploaded before the row is synced.
  Future<void> save(FoodLog log, {String? newPhotoPath});
  Future<void> delete(String id);
}

abstract interface class TaskAreaRepository {
  /// Every area incl. archived, sorted by `sortOrder` then name.
  Stream<List<TaskArea>> watchAll();
  Future<List<TaskArea>> getAll();
  Stream<TaskArea?> watchById(String id);
  Future<TaskArea?> getById(String id);
  Future<void> save(TaskArea area);

  /// Deletes the area and (cascade, like the server) its tasks.
  Future<void> delete(String id);
}

abstract interface class TaskRepository {
  /// Every task (done or not), unsorted.
  Stream<List<Task>> watchAll();
  Future<List<Task>> getAll({String? areaId});
  Stream<Task?> watchById(String id);
  Future<Task?> getById(String id);
  Future<void> save(Task task);
  Future<void> delete(String id);
}

// ---------------------------------------------------------------- notes & content

abstract interface class NoteRepository {
  /// Filtered in SQL: [archived] (null = both), [labelId], [search]
  /// (title/body/checklist/transcripts, case-insensitive). Pinned first, then
  /// most recently updated.
  Stream<List<Note>> watch({bool? archived, String? labelId, String? search});

  /// Every note, same order.
  Stream<List<Note>> watchAll();
  Future<List<Note>> getAll();
  Stream<Note?> watchById(String id);
  Future<Note?> getById(String id);

  /// Insert or update. Pending photos/clips whose file isn't in app storage yet
  /// are copied there first; pending files dropped from the lists are deleted.
  /// They are uploaded by the sync engine before the row is pushed.
  Future<void> save(Note note);

  /// Deletes the row and its pending files. Content items with this `noteId`
  /// get `noteId = null`.
  Future<void> delete(String id);
}

abstract interface class NoteLabelRepository {
  /// Sorted by `sortOrder`, then name.
  Stream<List<NoteLabel>> watchAll();
  Future<List<NoteLabel>> getAll();
  Future<NoteLabel?> getById(String id);
  Future<void> save(NoteLabel label);

  /// Deletes the label and removes its id from every note (like the server).
  Future<void> delete(String id);
}

abstract interface class SocialAccountRepository {
  /// Every account incl. archived, sorted by `sortOrder`, platform, handle.
  Stream<List<SocialAccount>> watchAll();
  Future<List<SocialAccount>> getAll();
  Stream<SocialAccount?> watchById(String id);
  Future<SocialAccount?> getById(String id);
  Future<void> save(SocialAccount account);

  /// Deletes the account and (cascade) its posts.
  Future<void> delete(String id);
}

abstract interface class ContentItemRepository {
  Stream<List<ContentItem>> watchAll();
  Future<List<ContentItem>> getAll();
  Stream<ContentItem?> watchById(String id);
  Future<ContentItem?> getById(String id);

  /// Insert or update (pending photos like [NoteRepository.save]). Records the
  /// device-only `stageReachedAt` for newly reached stages.
  Future<void> save(ContentItem item);

  /// Deletes the item, its posts (cascade) and pending files; notes with
  /// `linkedContentId` = it get null.
  Future<void> delete(String id);
}

abstract interface class ContentPostRepository {
  Stream<List<ContentPost>> watchAll();
  Future<List<ContentPost>> getAll({String? contentId});
  Stream<ContentPost?> watchById(String id);
  Future<ContentPost?> getById(String id);
  Future<void> save(ContentPost post);
  Future<void> delete(String id);
}

abstract interface class ContentPillarRepository {
  /// Sorted by `sortOrder`, then name.
  Stream<List<ContentPillar>> watchAll();
  Future<List<ContentPillar>> getAll();
  Future<ContentPillar?> getById(String id);
  Future<void> save(ContentPillar pillar);
  Future<void> delete(String id);
}

/// Whether the server already owns seeding the notes/content defaults (a pull
/// from a notes/content-aware server succeeded). Before that, the app may seed
/// them locally as an offline fallback (same deterministic ids).
abstract interface class DefaultsSeedState {
  Future<bool> notesServerSeeded();
  Future<bool> contentServerSeeded();
}

abstract interface class AuthRepository {
  /// Cached user when a token is stored (works offline), else null.
  Future<AppUser?> restoreSession();
  Future<AppUser> signIn({required String email, required String password});
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  });

  /// [idToken] comes from the `google_sign_in` package on the screen.
  Future<AppUser> signInWithGoogle(String idToken);

  /// `GET /me`; refreshes the cached user.
  Future<AppUser> refreshProfile();
  Future<AppUser> updateProfile({String? name, String? currency});

  /// Clears the token and wipes all local data.
  Future<void> signOut();

  /// Fires when the server answers 401 to an authenticated call. The token is
  /// cleared but local data is kept (so pending changes survive a re-login).
  Stream<void> get sessionExpired;
}

/// The background sync engine as seen by the domain.
abstract interface class SyncService {
  /// Begin automatic syncing (start/resume, connectivity, local writes, 60 s timer).
  void start();

  /// Stop automatic syncing (sign-out).
  void stop();

  /// Push then pull now; completes when done. Throws a `Failure` on error.
  Future<void> syncNow();

  Stream<SyncStatus> watchStatus();

  /// Wipe local synced data + outbox and do a full pull.
  Future<void> resetLocalData();
}
