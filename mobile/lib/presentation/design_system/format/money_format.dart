import 'package:intl/intl.dart';

/// Self-contained money formatting for design-system widgets (no dependency
/// on `core/`). IDR renders as `Rp 25.000`.
///
/// ```dart
/// GhinaMoney.format(25000);                         // Rp 25.000
/// GhinaMoney.format(-25000, showSign: true);        // -Rp 25.000
/// GhinaMoney.format(1250000, compact: true);        // Rp 1,3 jt
/// GhinaMoney.format(12.5, currency: 'USD');         // $12.50
/// ```
abstract final class GhinaMoney {
  static const _zeroDecimal = {'IDR', 'JPY', 'KRW', 'VND'};

  /// Number of fraction digits shown for [currency].
  static int decimalsFor(String currency) =>
      _zeroDecimal.contains(currency.toUpperCase()) ? 0 : 2;

  /// Currency symbol ("Rp", "$", ...).
  static String symbolFor(String currency) {
    final c = currency.toUpperCase();
    if (c == 'IDR') return 'Rp';
    return NumberFormat.simpleCurrency(name: c).currencySymbol;
  }

  static String format(
    num amount, {
    String currency = 'IDR',
    bool showSign = false,
    bool compact = false,
  }) {
    final c = currency.toUpperCase();
    final abs = amount.abs();
    final String body;
    if (compact && abs >= 1000) {
      body = '${symbolFor(c)} ${_compact(abs, c)}';
    } else if (c == 'IDR') {
      body = NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).format(abs);
    } else {
      body = NumberFormat.simpleCurrency(
        name: c,
        decimalDigits: decimalsFor(c),
      ).format(abs);
    }
    if (amount < 0) return '-$body';
    if (showSign && amount > 0) return '+$body';
    return body;
  }

  /// Plain grouped number without symbol: `25.000` (IDR) / `1,234.50`.
  static String number(num amount, {String currency = 'IDR'}) {
    final c = currency.toUpperCase();
    final locale = c == 'IDR' ? 'id_ID' : 'en_US';
    final d = decimalsFor(c);
    final f = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: d,
    );
    return f.format(amount);
  }

  static String _compact(num abs, String c) {
    if (c == 'IDR') {
      String f(num v, String s) =>
          '${NumberFormat.decimalPatternDigits(locale: 'id_ID', decimalDigits: v < 10 ? 1 : 0).format(v)} $s';
      if (abs >= 1e12) return f(abs / 1e12, 'T');
      if (abs >= 1e9) return f(abs / 1e9, 'M');
      if (abs >= 1e6) return f(abs / 1e6, 'jt');
      return f(abs / 1e3, 'rb');
    }
    return NumberFormat.compact(locale: 'en_US').format(abs);
  }
}
