import '../../core/dates.dart';

/// Transaction type. Wire values: `expense | income | transfer`.
enum TxType {
  expense('expense', 'Pengeluaran'),
  income('income', 'Pemasukan'),
  transfer('transfer', 'Transfer');

  const TxType(this.wire, this.label);
  final String wire;
  final String label;

  static TxType fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => TxType.expense);
}

/// Category type. Wire values: `expense | income`.
enum CategoryType {
  expense('expense', 'Pengeluaran'),
  income('income', 'Pemasukan');

  const CategoryType(this.wire, this.label);
  final String wire;
  final String label;

  static CategoryType fromWire(String? v) =>
      v == 'income' ? CategoryType.income : CategoryType.expense;
}

/// Wallet type (web `WALLET_TYPES`). Unknown wire values map to [cash].
enum WalletType {
  cash('cash', 'Tunai'),
  bank('bank', 'Rekening Bank'),
  ewallet('ewallet', 'E-Wallet'),
  credit('credit', 'Kartu Kredit'),
  savings('savings', 'Tabungan'),
  investment('investment', 'Investasi');

  const WalletType(this.wire, this.label);
  final String wire;
  final String label;

  static WalletType fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => WalletType.cash);
}

/// Subscription billing cycle (port of `subscriptions/presets.ts`).
enum BillingCycle {
  weekly('weekly', 'Mingguan', '/mgg'),
  monthly('monthly', 'Bulanan', '/bln'),
  yearly('yearly', 'Tahunan', '/thn');

  const BillingCycle(this.wire, this.label, this.per);
  final String wire;
  final String label;

  /// Short suffix for amounts, e.g. `Rp 50.000/bln`.
  final String per;

  /// Unknown values behave like monthly (as on the web).
  static BillingCycle fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => BillingCycle.monthly);

  /// Advance [date] by exactly one cycle (web `advanceCycle`).
  DateTime advance(DateTime date) => switch (this) {
    BillingCycle.weekly => addWeeks(date, 1),
    BillingCycle.yearly => addYears(date, 1),
    BillingCycle.monthly => addMonths(date, 1),
  };

  /// Normalize an amount to per-month (web `monthlyAmount`).
  double monthlyAmount(double amount) => switch (this) {
    BillingCycle.weekly => amount * 52 / 12,
    BillingCycle.yearly => amount / 12,
    BillingCycle.monthly => amount,
  };

  /// Normalize an amount to per-year (web `yearlyAmount`).
  double yearlyAmount(double amount) => switch (this) {
    BillingCycle.weekly => amount * 52,
    BillingCycle.monthly => amount * 12,
    BillingCycle.yearly => amount,
  };
}

/// Meal of a food log. Wire values: `breakfast | lunch | dinner | snack`.
enum MealType {
  breakfast('breakfast', 'Sarapan', '🌅'),
  lunch('lunch', 'Makan siang', '🍱'),
  dinner('dinner', 'Makan malam', '🌙'),
  snack('snack', 'Camilan', '🍪');

  const MealType(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  static MealType? fromWire(String? v) {
    for (final m in values) {
      if (m.wire == v) return m;
    }
    return null;
  }
}

/// The five daily prayers, in order. Wire values are the lowercase ids.
enum Prayer {
  subuh('subuh', 'Subuh'),
  dzuhur('dzuhur', 'Dzuhur'),
  ashar('ashar', 'Ashar'),
  maghrib('maghrib', 'Maghrib'),
  isya('isya', 'Isya');

  const Prayer(this.wire, this.label);
  final String wire;
  final String label;

  static Prayer? fromWire(String? v) {
    for (final p in values) {
      if (p.wire == v) return p;
    }
    return null;
  }
}
