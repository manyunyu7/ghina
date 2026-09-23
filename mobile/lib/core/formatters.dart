import 'dart:math' as math;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Money & date formatting (Indonesian locale by default).
///
/// Date formatting needs locale data; it is initialized lazily and
/// synchronously on first use, so calling [initFormatting] is optional.
abstract final class Fmt {
  static bool _ready = false;

  /// Loads `id_ID` date symbols. Safe to call many times.
  static Future<void> initFormatting() async => _ensure();

  static void _ensure() {
    if (_ready) return;
    // The local-data initializer applies synchronously; the Future is a formality.
    initializeDateFormatting('id_ID');
    Intl.defaultLocale ??= 'id_ID';
    _ready = true;
  }

  static const _currencyCfg = <String, (String locale, int decimals)>{
    'IDR': ('id_ID', 0),
    'USD': ('en_US', 2),
    'EUR': ('de_DE', 2),
    'GBP': ('en_GB', 2),
    'JPY': ('ja_JP', 0),
    'SGD': ('en_SG', 2),
    'MYR': ('ms_MY', 2),
  };

  /// Currencies supported by the server (`CURRENCIES` on the web).
  static const currencies = ['IDR', 'USD', 'EUR', 'GBP', 'JPY', 'SGD', 'MYR'];

  /// `Rp 25.000`, `-Rp 1.500`, `$12.50`. [signed] forces a leading `+` for positives.
  static String money(
    num amount, {
    String currency = 'IDR',
    bool signed = false,
  }) {
    final String body;
    if (currency == 'IDR') {
      body =
          'Rp ${NumberFormat.decimalPattern('id_ID').format(amount.abs().round())}';
    } else {
      final cfg = _currencyCfg[currency] ?? ('en_US', 2);
      body = NumberFormat.simpleCurrency(
        locale: cfg.$1,
        name: currency,
        decimalDigits: cfg.$2,
      ).format(amount.abs());
    }
    if (amount < 0 && _roundsToNonZero(amount, currency)) return '-$body';
    if (signed && amount > 0) return '+$body';
    return body;
  }

  static bool _roundsToNonZero(num amount, String currency) {
    final decimals = currency == 'IDR' ? 0 : (_currencyCfg[currency]?.$2 ?? 2);
    return (amount.abs() * math.pow(10, decimals)).round() != 0;
  }

  /// Compact form for charts: `Rp 1,5 jt`, `Rp 250 rb`.
  static String moneyCompact(num amount, {String currency = 'IDR'}) {
    final cfg = _currencyCfg[currency] ?? ('id_ID', 0);
    final n = NumberFormat.compact(locale: cfg.$1).format(amount.abs());
    final prefix = currency == 'IDR'
        ? 'Rp '
        : NumberFormat.simpleCurrency(
            locale: cfg.$1,
            name: currency,
          ).currencySymbol;
    return '${amount < 0 ? '-' : ''}$prefix$n';
  }

  /// Plain grouped number: `25.000`.
  static String number(num n, {int decimals = 0}) =>
      NumberFormat.decimalPatternDigits(
        locale: 'id_ID',
        decimalDigits: decimals,
      ).format(n);

  /// Parses user input like `25.000` / `25000` / `25.000,50` (Indonesian grouping) → 25000.
  static double? parseAmount(String input) {
    var s = input.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (s.isEmpty) return null;
    s = s.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(s);
  }

  static String _fmt(String pattern, DateTime d) {
    _ensure();
    return DateFormat(pattern, 'id_ID').format(d);
  }

  /// `23 Sep 2026`
  static String date(DateTime d) => _fmt('d MMM y', d);

  /// `23 September 2026`
  static String dateLong(DateTime d) => _fmt('d MMMM y', d);

  /// `Rabu, 23 September 2026`
  static String dateFull(DateTime d) => _fmt('EEEE, d MMMM y', d);

  /// `Rab, 23 Sep`
  static String dateShortWeekday(DateTime d) => _fmt('EEE, d MMM', d);

  /// `14.05` (24h, Indonesian separator)
  static String time(DateTime d) => _fmt('HH.mm', d);

  /// `September 2026`
  static String monthYear(DateTime d) => _fmt('MMMM y', d);

  /// `Sep` — short month label for charts.
  static String monthShort(int month) => _fmt('MMM', DateTime(2000, month));

  /// `September`
  static String monthName(int month) => _fmt('MMMM', DateTime(2000, month));

  /// `Hari ini`, `Kemarin`, `Besok`, else [date].
  static String relativeDay(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(n.year, n.month, n.day)).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == -1) return 'Kemarin';
    if (diff == 1) return 'Besok';
    return d.year == n.year ? _fmt('d MMM', d) : date(d);
  }
}
