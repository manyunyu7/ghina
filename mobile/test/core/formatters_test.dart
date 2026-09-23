import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/formatters.dart';

void main() {
  test('money', () {
    expect(Fmt.money(25000), 'Rp 25.000');
    expect(Fmt.money(-1500), '-Rp 1.500');
    expect(Fmt.money(1234567.6), 'Rp 1.234.568');
    expect(Fmt.money(500, signed: true), '+Rp 500');
    expect(Fmt.money(12.5, currency: 'USD'), r'$12.50');
    expect(Fmt.parseAmount('25.000'), 25000);
    expect(Fmt.parseAmount('Rp 1.250,50'), 1250.5);
  });

  test('indonesian dates', () {
    final d = DateTime(2026, 9, 23, 14, 5);
    expect(Fmt.date(d), '23 Sep 2026');
    expect(Fmt.dateFull(d), 'Rabu, 23 September 2026');
    expect(Fmt.time(d), '14.05');
    expect(Fmt.monthYear(d), 'September 2026');
    expect(Fmt.relativeDay(d, now: DateTime(2026, 9, 24)), 'Kemarin');
  });

  test('calendar helpers', () {
    expect(dateKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(const YearMonth(2026, 12).next, const YearMonth(2027, 1));
    expect(
      const YearMonth(2026, 2).end,
      DateTime(2026, 2, 28, 23, 59, 59, 999),
    );
    expect(daysBetween(DateTime(2026, 10, 1), DateTime(2026, 9, 30, 23)), 1);
  });
}
