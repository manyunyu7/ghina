import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

void main() {
  group('GhinaIcons', () {
    test('every web category icon has a real mapping', () {
      for (final n in GhinaIcons.categoryNames) {
        expect(GhinaIcons.byName.containsKey(n), isTrue, reason: n);
      }
    });

    test('normalizes PascalCase / snake_case and falls back', () {
      expect(GhinaIcons.of('HeartPulse'), Icons.monitor_heart_rounded);
      expect(GhinaIcons.of('shopping_cart'), Icons.shopping_cart_rounded);
      expect(GhinaIcons.of('Gamepad2'), Icons.sports_esports_rounded);
      expect(GhinaIcons.of('LayoutDashboard'), Icons.dashboard_rounded);
      expect(GhinaIcons.of('nope'), GhinaIcons.fallback);
      expect(GhinaIcons.of(null), GhinaIcons.fallback);
      expect(GhinaIcons.nameOf(Icons.pets_rounded), 'dog');
      expect(GhinaIcons.walletType('ewallet'), Icons.smartphone_rounded);
    });
  });

  group('CategoryColors', () {
    test('parses and round-trips hex', () {
      expect(CategoryColors.parse('#f97316'), const Color(0xFFF97316));
      expect(CategoryColors.parse('fff'), const Color(0xFFFFFFFF));
      expect(CategoryColors.parse('garbage'), CategoryColors.fallback);
      expect(CategoryColors.toHex(const Color(0xFFF97316)), '#f97316');
    });

    test('derived swatch has a darker edge', () {
      final s = CategoryColors.swatch('#3b82f6');
      expect(s.edge.computeLuminance(), lessThan(s.base.computeLuminance()));
    });
  });

  group('GhinaMoney', () {
    test('formats IDR', () {
      expect(GhinaMoney.format(25000), 'Rp 25.000');
      expect(GhinaMoney.format(-25000), '-Rp 25.000');
      expect(GhinaMoney.format(25000, showSign: true), '+Rp 25.000');
      expect(GhinaMoney.format(1250000, compact: true), 'Rp 1,3 jt');
      expect(GhinaMoney.format(15000, compact: true), 'Rp 15 rb');
    });

    test('formats other currencies with decimals', () {
      expect(GhinaMoney.format(12.5, currency: 'USD'), r'$12.50');
      expect(GhinaMoney.decimalsFor('IDR'), 0);
    });
  });

  group('AmountController', () {
    test('IDR whole numbers, 000 key, backspace, leading zeros', () {
      final c = AmountController();
      expect(c.input('0'), isTrue);
      expect(c.value, '');
      c.input('1');
      c.input('000');
      expect(c.amount, 1000);
      expect(c.input('.'), isFalse);
      c.input('⌫');
      expect(c.amount, 100);
      c.input('C');
      expect(c.isEmpty, isTrue);
    });

    test('USD decimals are limited to 2 places', () {
      final c = AmountController(currency: 'USD');
      c.input('.');
      expect(c.value, '0.');
      c.input('5');
      c.input('0');
      expect(c.input('1'), isFalse);
      expect(c.amount, 0.5);
    });

    test('max digits and initial value', () {
      final c = AmountController(initial: 25000, maxIntegerDigits: 6);
      expect(c.value, '25000');
      c.input('1');
      expect(c.input('2'), isFalse);
      expect(c.amount, 250001);
    });
  });

  test('themes build with extensions', () {
    for (final t in [GhinaTheme.light(), GhinaTheme.dark()]) {
      expect(t.extension<GhinaTokens>(), isNotNull);
      expect(t.textTheme.bodyMedium!.fontFamily, 'Nunito');
      expect(t.textTheme.bodyMedium!.fontVariations, isNotEmpty);
    }
    expect(
      GhinaTheme.dark().scaffoldBackgroundColor,
      GhinaColors.darkBackground,
    );
  });

  test('TextStyle.w keeps variable weight axis in sync', () {
    final s = GhinaType.body.w(900);
    expect(s.fontWeight, FontWeight.w900);
    expect(s.fontVariations!.single.value, 900);
  });
}
