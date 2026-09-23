import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

/// Popular subscriptions to prefill the form (web `SUBSCRIPTION_PRESETS`).
const subscriptionPresets =
    <({String name, String color, String icon, BillingCycle cycle})>[
      (
        name: 'Netflix',
        color: '#E50914',
        icon: 'tv',
        cycle: BillingCycle.monthly,
      ),
      (
        name: 'Spotify',
        color: '#1DB954',
        icon: 'music',
        cycle: BillingCycle.monthly,
      ),
      (
        name: 'YouTube Premium',
        color: '#FF0000',
        icon: 'tv',
        cycle: BillingCycle.monthly,
      ),
      (
        name: 'Disney+ Hotstar',
        color: '#1F80E0',
        icon: 'tv',
        cycle: BillingCycle.monthly,
      ),
      (
        name: 'Amazon Prime',
        color: '#00A8E1',
        icon: 'shopping-bag',
        cycle: BillingCycle.yearly,
      ),
      (
        name: 'Apple iCloud',
        color: '#555555',
        icon: 'cloud',
        cycle: BillingCycle.monthly,
      ),
      (
        name: 'Google One',
        color: '#4285F4',
        icon: 'cloud',
        cycle: BillingCycle.monthly,
      ),
      (
        name: 'Microsoft 365',
        color: '#D83B01',
        icon: 'briefcase',
        cycle: BillingCycle.yearly,
      ),
      (
        name: 'ChatGPT Plus',
        color: '#10A37F',
        icon: 'sparkles',
        cycle: BillingCycle.monthly,
      ),
      (
        name: 'Gym Membership',
        color: '#f97316',
        icon: 'dumbbell',
        cycle: BillingCycle.monthly,
      ),
    ];

final class SubscriptionInput {
  const SubscriptionInput({
    required this.name,
    required this.amount,
    this.currency = 'IDR',
    this.cycle = BillingCycle.monthly,
    required this.nextBilling,
    this.categoryId,
    this.walletId,
    this.color = '#6366f1',
    this.icon = 'credit-card',
    this.note,
    this.active = true,
  });

  final String name;
  final double amount;
  final String currency;
  final BillingCycle cycle;
  final DateTime nextBilling;
  final String? categoryId;
  final String? walletId;
  final String color;
  final String icon;
  final String? note;
  final bool active;
}

Future<Subscription> _build(
  String id,
  SubscriptionInput i,
  DateTime createdAt,
  DateTime now,
  WalletRepository wallets,
  CategoryRepository categories,
) async {
  final categoryId = optionalId(i.categoryId);
  final walletId = optionalId(i.walletId);
  if (categoryId != null && await categories.getById(categoryId) == null) {
    throw const NotFoundFailure('Kategori tidak ditemukan');
  }
  if (walletId != null && await wallets.getById(walletId) == null) {
    throw const NotFoundFailure('Dompet tidak ditemukan');
  }
  final currency = i.currency.trim();
  if (currency.isEmpty || currency.length > 8) {
    throw const ValidationFailure('Mata uang tidak valid', field: 'currency');
  }
  return Subscription(
    id: id,
    name: requireName(i.name, max: 80),
    amount: requirePositiveAmount(i.amount),
    currency: currency,
    cycle: i.cycle,
    nextBilling: i.nextBilling,
    categoryId: categoryId,
    walletId: walletId,
    color: requireColor(i.color),
    icon: i.icon.trim().isEmpty ? 'credit-card' : i.icon.trim(),
    note: optionalText(i.note, max: 200),
    active: i.active,
    createdAt: createdAt,
    updatedAt: now,
  );
}

/// First non-archived wallet by creation date (web fallback for quick pay / convert).
Future<String?> firstActiveWalletId(WalletRepository wallets) async {
  final all = await wallets.getAll(includeArchived: false);
  return all.isEmpty ? null : all.first.id;
}

/// All subscriptions (active first, then by next occurrence) + monthly/yearly totals.
final class WatchSubscriptions {
  const WatchSubscriptions(this._repo, this._clock);
  final SubscriptionRepository _repo;
  final Clock _clock;

  Stream<SubscriptionSummary> call() => _repo.watchAll().map((subs) {
    final now = _clock.now();
    final sorted = [...subs]
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.nextOccurrence(now).compareTo(b.nextOccurrence(now));
      });
    return SubscriptionSummary(items: sorted);
  });
}

final class WatchSubscription {
  const WatchSubscription(this._repo);
  final SubscriptionRepository _repo;

  Stream<Subscription?> call(String id) => _repo.watchById(id);
}

final class CreateSubscription {
  const CreateSubscription(
    this._repo,
    this._wallets,
    this._categories,
    this._clock,
  );
  final SubscriptionRepository _repo;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<Subscription>> call(SubscriptionInput input) => guard(() async {
    final now = _clock.now();
    final s = await _build(newId(), input, now, now, _wallets, _categories);
    await _repo.save(s);
    return s;
  });
}

final class UpdateSubscription {
  const UpdateSubscription(
    this._repo,
    this._wallets,
    this._categories,
    this._clock,
  );
  final SubscriptionRepository _repo;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final Clock _clock;

  Future<Result<Subscription>> call(String id, SubscriptionInput input) =>
      guard(() async {
        final e = await _repo.getById(id);
        if (e == null) throw const NotFoundFailure('Langganan tidak ditemukan');
        final s = await _build(
          id,
          input,
          e.createdAt,
          _clock.now(),
          _wallets,
          _categories,
        );
        await _repo.save(s);
        return s;
      });
}

final class DeleteSubscription {
  const DeleteSubscription(this._repo);
  final SubscriptionRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

/// Flips `active`.
final class ToggleSubscription {
  const ToggleSubscription(this._repo, this._clock);
  final SubscriptionRepository _repo;
  final Clock _clock;

  Future<Result<bool>> call(String id) => guard(() async {
    final e = await _repo.getById(id);
    if (e == null) throw const NotFoundFailure('Langganan tidak ditemukan');
    await _repo.save(e.copyWith(active: !e.active, updatedAt: _clock.now()));
    return !e.active;
  });
}

/// Quick pay (web `markSubscriptionPaid`): creates an expense for today on the
/// subscription's wallet (else the first wallet), and moves `nextBilling` to one cycle
/// after the occurrence being paid. Atomic.
final class PaySubscription {
  const PaySubscription(
    this._subs,
    this._tx,
    this._wallets,
    this._uow,
    this._clock,
  );
  final SubscriptionRepository _subs;
  final TransactionRepository _tx;
  final WalletRepository _wallets;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<Transaction>> call(String id) => guard(
    () => _uow.run(() async {
      final sub = await _subs.getById(id);
      if (sub == null) throw const NotFoundFailure('Langganan tidak ditemukan');

      var walletId = sub.walletId;
      if (walletId != null && await _wallets.getById(walletId) == null) {
        walletId = null;
      }
      walletId ??= await firstActiveWalletId(_wallets);
      if (walletId == null) {
        throw const ValidationFailure(
          'Buat dompet dulu, atau pilih dompet pembayaran untuk langganan ini.',
          field: 'walletId',
        );
      }

      final now = _clock.now();
      final paidOccurrence = sub.nextOccurrence(now);
      final newNext = sub.cycle.advance(paidOccurrence);

      final t = Transaction(
        id: newId(),
        walletId: walletId,
        categoryId: sub.categoryId,
        type: TxType.expense,
        amount: sub.amount,
        note: sub.name,
        date: now,
        createdAt: now,
        updatedAt: now,
      );
      await _tx.save(t);
      await _subs.save(sub.copyWith(nextBilling: newNext, updatedAt: now));
      return t;
    }),
  );
}
