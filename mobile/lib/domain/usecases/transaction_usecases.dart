import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

/// Form data for a transaction. For [TxType.adjustment] the [amount] is signed
/// (non-zero); every other type needs a positive amount.
final class TransactionInput {
  const TransactionInput({
    required this.type,
    required this.amount,
    required this.walletId,
    this.toWalletId,
    this.categoryId,
    this.note,
    required this.date,
    this.photos,
  });

  final TxType type;
  final double amount;
  final String walletId;

  /// Required for transfers, ignored otherwise.
  final String? toWalletId;

  /// Ignored for transfers.
  final String? categoryId;
  final String? note;
  final DateTime date;

  /// Up to [maxTransactionPhotos]. `TransactionPhoto.local(pickedFile.path)` for
  /// new photos (compress first: `maxWidth: 1600, imageQuality: 80`), kept
  /// `TransactionPhoto.remote` ones from the current list. Null = no photos on
  /// create, unchanged on update.
  final List<TransactionPhoto>? photos;
}

/// ≤ [maxTransactionPhotos], duplicates dropped (first wins), order kept.
List<TransactionPhoto> validatePhotos(List<TransactionPhoto> photos) {
  final out = <TransactionPhoto>[];
  for (final p in photos) {
    if (!out.contains(p)) out.add(p);
  }
  if (out.length > maxTransactionPhotos) {
    throw const ValidationFailure(
      'Maksimal $maxTransactionPhotos foto',
      field: 'photos',
    );
  }
  return List.unmodifiable(out);
}

/// Validates references like the web's `validateRefs` and returns the normalized
/// `(toWalletId, categoryId)`.
Future<({String? toWalletId, String? categoryId})> _validateRefs(
  TransactionInput p,
  WalletRepository wallets,
  CategoryRepository categories,
) async {
  if (p.walletId.isEmpty) {
    throw const ValidationFailure('Pilih dompet dulu', field: 'walletId');
  }
  if (await wallets.getById(p.walletId) == null) {
    throw const NotFoundFailure('Dompet tidak ditemukan');
  }
  if (p.type == TxType.transfer) {
    final to = optionalId(p.toWalletId);
    if (to == null) {
      throw const ValidationFailure('Pilih dompet tujuan', field: 'toWalletId');
    }
    if (to == p.walletId) {
      throw const ValidationFailure(
        'Dompet asal dan tujuan harus berbeda',
        field: 'toWalletId',
      );
    }
    if (await wallets.getById(to) == null) {
      throw const NotFoundFailure('Dompet tujuan tidak ditemukan');
    }
    return (toWalletId: to, categoryId: null); // transfers carry no category
  }
  if (p.type == TxType.adjustment) {
    // Adjustments carry neither a category nor a destination wallet.
    return (toWalletId: null, categoryId: null);
  }
  final cat = optionalId(p.categoryId);
  if (cat != null && await categories.getById(cat) == null) {
    throw const NotFoundFailure('Kategori tidak ditemukan');
  }
  return (toWalletId: null, categoryId: cat);
}

Future<Transaction> _build(
  String id,
  TransactionInput input,
  DateTime createdAt,
  DateTime now,
  WalletRepository wallets,
  CategoryRepository categories, {
  List<TransactionPhoto> photos = const [],
}) async {
  final amount = input.type == TxType.adjustment
      ? requireNonZeroAmount(input.amount)
      : requirePositiveAmount(input.amount);
  final refs = await _validateRefs(input, wallets, categories);
  return Transaction(
    id: id,
    walletId: input.walletId,
    toWalletId: refs.toWalletId,
    categoryId: refs.categoryId,
    type: input.type,
    amount: amount,
    note: optionalText(input.note),
    date: input.date,
    createdAt: createdAt,
    updatedAt: now,
    photos: validatePhotos(input.photos ?? photos),
  );
}

/// Creates a transaction. Wallet balances update immediately (pending effect) and
/// on the server after sync.
final class CreateTransaction {
  const CreateTransaction(
    this._tx,
    this._wallets,
    this._categories,
    this._clock,
  );
  final TransactionRepository _tx;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<Transaction>> call(TransactionInput input) => guard(() async {
    final now = _clock.now();
    final t = await _build(newId(), input, now, now, _wallets, _categories);
    await _tx.save(t);
    return t;
  });
}

/// Moves money between two wallets (a `transfer` transaction).
final class TransferBetweenWallets {
  const TransferBetweenWallets(this._create);
  final CreateTransaction _create;

  Future<Result<Transaction>> call({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    required DateTime date,
    String? note,
  }) => _create(
    TransactionInput(
      type: TxType.transfer,
      amount: amount,
      walletId: fromWalletId,
      toWalletId: toWalletId,
      note: note,
      date: date,
    ),
  );
}

/// Edits a transaction (old balance effect reversed, new one applied).
final class UpdateTransaction {
  const UpdateTransaction(
    this._tx,
    this._wallets,
    this._categories,
    this._clock,
  );
  final TransactionRepository _tx;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<Transaction>> call(String id, TransactionInput input) =>
      guard(() async {
        final existing = await _tx.getById(id);
        if (existing == null) {
          throw const NotFoundFailure('Transaksi tidak ditemukan');
        }
        final t = await _build(
          id,
          input,
          existing.createdAt,
          _clock.now(),
          _wallets,
          _categories,
          photos: existing.photos,
        );
        await _tx.save(t);
        return t;
      });
}

final class DeleteTransaction {
  const DeleteTransaction(this._tx);
  final TransactionRepository _tx;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _tx.getById(id) == null) {
      throw const NotFoundFailure('Transaksi tidak ditemukan');
    }
    await _tx.delete(id);
  });
}

// ---------------------------------------------------------------- photos

/// Appends picked photos (file paths) to a transaction. They show at once (local
/// file) and upload on the next sync. Fails with a [ValidationFailure] beyond
/// [maxTransactionPhotos].
final class AddTransactionPhotos {
  const AddTransactionPhotos(this._tx, this._clock);
  final TransactionRepository _tx;
  final Clock _clock;

  Future<Result<Transaction>> call(String id, List<String> filePaths) =>
      guard(() async {
        final t = await _tx.getById(id);
        if (t == null) throw const NotFoundFailure('Transaksi tidak ditemukan');
        final u = t.withPhotos(
          validatePhotos([
            ...t.photos,
            for (final p in filePaths) TransactionPhoto.local(p),
          ]),
          updatedAt: _clock.now(),
        );
        await _tx.save(u);
        return u;
      });
}

/// Removes one photo (uploaded or pending). The server deletes the file of a
/// removed upload; a pending local file is deleted right away.
final class RemoveTransactionPhoto {
  const RemoveTransactionPhoto(this._tx, this._clock);
  final TransactionRepository _tx;
  final Clock _clock;

  Future<Result<Transaction>> call(String id, TransactionPhoto photo) =>
      guard(() async {
        final t = await _tx.getById(id);
        if (t == null) throw const NotFoundFailure('Transaksi tidak ditemukan');
        if (!t.photos.contains(photo)) return t;
        final u = t.withPhotos([
          for (final p in t.photos)
            if (p != photo) p,
        ], updatedAt: _clock.now());
        await _tx.save(u);
        return u;
      });
}

/// Replaces the whole photo list (reorder / bulk edit); same rules as the input's
/// `photos`.
final class SetTransactionPhotos {
  const SetTransactionPhotos(this._tx, this._clock);
  final TransactionRepository _tx;
  final Clock _clock;

  Future<Result<Transaction>> call(String id, List<TransactionPhoto> photos) =>
      guard(() async {
        final t = await _tx.getById(id);
        if (t == null) throw const NotFoundFailure('Transaksi tidak ditemukan');
        final u = t.withPhotos(validatePhotos(photos), updatedAt: _clock.now());
        await _tx.save(u);
        return u;
      });
}

/// Joins transactions with wallets/categories and applies the text search.
List<TransactionView> joinTransactions(
  List<Transaction> txs,
  List<Wallet> wallets,
  List<TxCategory> categories, {
  String? search,
}) {
  final w = {for (final x in wallets) x.id: x};
  final c = {for (final x in categories) x.id: x};
  final q = search?.trim().toLowerCase();
  final out = <TransactionView>[];
  for (final t in txs) {
    final v = TransactionView(
      transaction: t,
      wallet: w[t.walletId],
      toWallet: t.toWalletId == null ? null : w[t.toWalletId],
      category: t.categoryId == null ? null : c[t.categoryId],
    );
    if (q != null && q.isNotEmpty) {
      final hay = [
        t.note,
        v.category?.name,
        v.wallet?.name,
        v.toWallet?.name,
      ].whereType<String>().join(' ').toLowerCase();
      if (!hay.contains(q)) continue;
    }
    out.add(v);
  }
  return out;
}

/// Groups (already newest-first) transactions by local day, newest day first.
List<DayGroup> groupTransactionsByDay(List<TransactionView> items) {
  final groups = <DateTime, List<TransactionView>>{};
  for (final v in items) {
    groups.putIfAbsent(startOfDay(v.date), () => []).add(v);
  }
  final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days)
      DayGroup(
        day: d,
        items: groups[d]!,
        income: groups[d]!
            .where((v) => v.type == TxType.income)
            .fold(0, (s, v) => s + v.amount),
        expense: groups[d]!
            .where((v) => v.type == TxType.expense)
            .fold(0, (s, v) => s + v.amount),
      ),
  ];
}

/// Filtered, joined transaction list (newest first).
final class WatchTransactions {
  const WatchTransactions(this._tx, this._wallets, this._categories);
  final TransactionRepository _tx;
  final WalletRepository _wallets;
  final CategoryRepository _categories;

  Stream<List<TransactionView>> call([
    TransactionFilter filter = TransactionFilter.all,
  ]) {
    final searching = filter.search != null && filter.search!.trim().isNotEmpty;
    return combineLatest3(
      _tx.watch(
        from: filter.rangeStart,
        to: filter.rangeEnd,
        type: filter.type,
        walletId: filter.walletId,
        categoryId: filter.categoryId,
        // With a search the limit applies after filtering.
        limit: searching ? null : filter.limit,
      ),
      _wallets.watchAll(),
      _categories.watchAll(),
      (List<Transaction> t, List<Wallet> w, List<TxCategory> c) {
        final rows = joinTransactions(t, w, c, search: filter.search);
        final limit = filter.limit;
        return searching && limit != null && rows.length > limit
            ? rows.sublist(0, limit)
            : rows;
      },
    );
  }
}

/// Same as [WatchTransactions] but grouped by day for the list screen.
final class WatchTransactionsByDay {
  const WatchTransactionsByDay(this._watch);
  final WatchTransactions _watch;

  Stream<List<DayGroup>> call([
    TransactionFilter filter = TransactionFilter.all,
  ]) => _watch(filter).map(groupTransactionsByDay);
}

/// One transaction joined with its wallet(s) and category; null when deleted.
final class WatchTransaction {
  const WatchTransaction(this._tx, this._wallets, this._categories);
  final TransactionRepository _tx;
  final WalletRepository _wallets;
  final CategoryRepository _categories;

  Stream<TransactionView?> call(String id) => combineLatest3(
    _tx.watchById(id),
    _wallets.watchAll(),
    _categories.watchAll(),
    (Transaction? t, List<Wallet> w, List<TxCategory> c) =>
        t == null ? null : joinTransactions([t], w, c).first,
  );
}
