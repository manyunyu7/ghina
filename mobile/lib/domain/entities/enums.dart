import '../../core/dates.dart';

/// Transaction type. Wire values: `expense | income | transfer | adjustment`.
///
/// `adjustment` (balance adjustment, `docs/balance-adjustment.md`) carries a
/// **signed** amount (new balance − old balance) and is not income or expense.
enum TxType {
  expense('expense', 'Pengeluaran'),
  income('income', 'Pemasukan'),
  transfer('transfer', 'Transfer'),
  adjustment('adjustment', 'Penyesuaian saldo');

  const TxType(this.wire, this.label);
  final String wire;
  final String label;

  /// Types a user picks when logging a transaction (adjustments are made from
  /// the wallet screen).
  static const loggable = [expense, income, transfer];

  /// Unknown values → expense. Prefer [tryFromWire] for data from the server.
  static TxType fromWire(String? v) => tryFromWire(v) ?? TxType.expense;

  /// Null for a type this app version doesn't know (newer server).
  static TxType? tryFromWire(String? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
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

/// Fardhu (the five daily prayers) or a daily sunnah prayer.
enum PrayerKind { fardhu, sunnah }

/// Every tracked prayer (spec `docs/prayer-quality.md`). Wire values are the
/// lowercase ids. Order: the five fardhu, then the daily sunnah.
enum Prayer {
  subuh('subuh', 'Subuh', PrayerKind.fardhu, hasQobliyah: true),
  dzuhur(
    'dzuhur',
    'Dzuhur',
    PrayerKind.fardhu,
    hasQobliyah: true,
    hasBadiyah: true,
  ),
  ashar('ashar', 'Ashar', PrayerKind.fardhu),
  maghrib('maghrib', 'Maghrib', PrayerKind.fardhu, hasBadiyah: true),
  isya('isya', 'Isya', PrayerKind.fardhu, hasBadiyah: true),
  dhuha('dhuha', 'Dhuha', PrayerKind.sunnah),
  tahajud('tahajud', 'Tahajud', PrayerKind.sunnah),
  witir('witir', 'Witir', PrayerKind.sunnah);

  const Prayer(
    this.wire,
    this.label,
    this.kind, {
    this.hasQobliyah = false,
    this.hasBadiyah = false,
  });

  final String wire;
  final String label;
  final PrayerKind kind;

  /// Rawatib muakkad before this fardhu exists (subuh, dzuhur).
  final bool hasQobliyah;

  /// Rawatib muakkad after this fardhu exists (dzuhur, maghrib, isya).
  final bool hasBadiyah;

  bool get isFardhu => kind == PrayerKind.fardhu;
  bool get isSunnah => kind == PrayerKind.sunnah;

  /// Number of rawatib slots of this prayer (0–2).
  int get rawatibSlots => (hasQobliyah ? 1 : 0) + (hasBadiyah ? 1 : 0);

  /// The five fardhu, in order.
  static const fardhu = [subuh, dzuhur, ashar, maghrib, isya];

  /// The daily sunnah, in order.
  static const sunnah = [dhuha, tahajud, witir];

  static Prayer? fromWire(String? v) {
    for (final p in values) {
      if (p.wire == v) return p;
    }
    return null;
  }
}

/// Status of a prayer row (spec "Status"). Fardhu rows use the first seven, in
/// this order everywhere; sunnah rows are always [done].
enum PrayerStatus {
  masjid('masjid', 'Jamaah di masjid', 'Masjid', 10, 0xFF1B7A2E),
  jamaah('jamaah', 'Jamaah', 'Jamaah', 8, 0xFF58CC02),
  ontime('ontime', 'Sendiri, awal waktu', 'Awal waktu', 6, 0xFF1CB0F6),
  late('late', 'Sendiri, telat', 'Telat', 3, 0xFFFFC800),
  qadha('qadha', 'Qadha', 'Qadha', 1, 0xFFFF9600),
  missed('missed', 'Terlewat', 'Terlewat', 0, 0xFFFF4B4B),
  excused(
    'excused',
    'Berhalangan (haid/nifas)',
    'Berhalangan',
    null,
    0xFFCE82FF,
  ),

  /// Sunnah rows only: the row means done.
  done('done', 'Sudah', 'Sudah', null, 0xFF58CC02);

  const PrayerStatus(
    this.wire,
    this.label,
    this.shortLabel,
    this.points,
    this.argb,
  );

  final String wire;

  /// Indonesian label (spec table).
  final String label;

  /// Compact label for chips/legends.
  final String shortLabel;

  /// Quality points (null = not scored: excused / sunnah).
  final int? points;

  /// Spec color as `0xAARRGGBB`.
  final int argb;

  /// Counts as prayed (masjid/jamaah/ontime/late/qadha).
  bool get isPrayed => switch (this) {
    masjid || jamaah || ontime || late || qadha => true,
    _ => false,
  };

  /// Masjid or jamaah.
  bool get isCongregation => this == masjid || this == jamaah;

  /// The seven fardhu statuses in spec order.
  static const fardhu = [masjid, jamaah, ontime, late, qadha, missed, excused];

  /// Default for a quick tap.
  static const quick = jamaah;

  /// "Belum diisi" (no row) colors, light and dark.
  static const emptyArgb = 0xFFE5E5E5;
  static const emptyArgbDark = 0xFF37464F;

  static PrayerStatus? fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }

  /// Tolerant parse for a row of [prayer]: missing/unknown/invalid values fall back
  /// to `ontime` (fardhu, the server default) or `done` (sunnah).
  static PrayerStatus forPrayer(Prayer prayer, String? v) {
    final s = fromWire(v);
    if (prayer.isSunnah) return done;
    return (s == null || s == done) ? ontime : s;
  }
}
