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
  Future<void> save(Transaction transaction);
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
