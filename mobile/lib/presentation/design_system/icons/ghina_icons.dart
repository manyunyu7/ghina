import 'package:flutter/material.dart';

/// Icon registry: maps the web's lucide icon names (stored on categories as
/// strings, e.g. `"shopping-cart"`) to rounded Material icons, and back.
///
/// ```dart
/// Icon(GhinaIcons.of(category.icon));          // 'utensils' -> restaurant
/// GhinaIcons.nameOf(Icons.pets_rounded);        // 'dog'
/// GhinaIcons.walletType('ewallet');             // smartphone
/// ```
///
/// Accepts kebab-case (`heart-pulse`), PascalCase (`HeartPulse`) and
/// snake_case. Unknown names fall back to [fallback].
abstract final class GhinaIcons {
  static const IconData fallback = Icons.category_rounded;

  /// lucide name -> Material icon.
  static const Map<String, IconData> byName = {
    // --- category icons (web CATEGORY_ICONS) ---
    'utensils': Icons.restaurant_rounded,
    'shopping-cart': Icons.shopping_cart_rounded,
    'shopping-bag': Icons.shopping_bag_rounded,
    'car': Icons.directions_car_rounded,
    'bus': Icons.directions_bus_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'home': Icons.home_rounded,
    'zap': Icons.bolt_rounded,
    'wifi': Icons.wifi_rounded,
    'phone': Icons.phone_rounded,
    'heart-pulse': Icons.monitor_heart_rounded,
    'pill': Icons.medication_rounded,
    'graduation-cap': Icons.school_rounded,
    'book-open': Icons.menu_book_rounded,
    'gamepad-2': Icons.sports_esports_rounded,
    'film': Icons.movie_rounded,
    'music': Icons.music_note_rounded,
    'plane': Icons.flight_rounded,
    'gift': Icons.card_giftcard_rounded,
    'coffee': Icons.coffee_rounded,
    'dumbbell': Icons.fitness_center_rounded,
    'shirt': Icons.checkroom_rounded,
    'baby': Icons.child_friendly_rounded,
    'dog': Icons.pets_rounded,
    'briefcase': Icons.work_rounded,
    'landmark': Icons.account_balance_rounded,
    'piggy-bank': Icons.savings_rounded,
    'trending-up': Icons.trending_up_rounded,
    'wallet': Icons.account_balance_wallet_rounded,
    'banknote': Icons.payments_rounded,
    'credit-card': Icons.credit_card_rounded,
    'circle-dollar-sign': Icons.monetization_on_rounded,
    'receipt': Icons.receipt_long_rounded,
    'circle': Icons.circle_rounded,
    // --- wallet types & nav ---
    'smartphone': Icons.smartphone_rounded,
    'layout-dashboard': Icons.dashboard_rounded,
    'arrow-left-right': Icons.swap_horiz_rounded,
    'target': Icons.track_changes_rounded,
    'repeat': Icons.repeat_rounded,
    'moon': Icons.nightlight_round,
    'tags': Icons.sell_rounded,
    'tag': Icons.sell_rounded,
    'pie-chart': Icons.pie_chart_rounded,
    'settings': Icons.settings_rounded,
    // --- common extras ---
    'house': Icons.home_rounded,
    'trending-down': Icons.trending_down_rounded,
    'star': Icons.star_rounded,
    'sparkles': Icons.auto_awesome_rounded,
    'flame': Icons.local_fire_department_rounded,
    'trophy': Icons.emoji_events_rounded,
    'heart': Icons.favorite_rounded,
    'calendar': Icons.calendar_month_rounded,
    'clock': Icons.schedule_rounded,
    'bell': Icons.notifications_rounded,
    'user': Icons.person_rounded,
    'users': Icons.group_rounded,
    'scale': Icons.monitor_weight_rounded,
    'activity': Icons.show_chart_rounded,
    'apple': Icons.apple_rounded,
    'salad': Icons.lunch_dining_rounded,
    'pizza': Icons.local_pizza_rounded,
    'bike': Icons.pedal_bike_rounded,
    'train': Icons.train_rounded,
    'bed': Icons.hotel_rounded,
    'wrench': Icons.build_rounded,
    'tv': Icons.tv_rounded,
    'laptop': Icons.laptop_rounded,
    'cat': Icons.pets_rounded,
    'hand-coins': Icons.volunteer_activism_rounded,
    'handshake': Icons.handshake_rounded,
    'building': Icons.apartment_rounded,
    'store': Icons.storefront_rounded,
    'cloud': Icons.cloud_rounded,
    'droplet': Icons.water_drop_rounded,
    'umbrella': Icons.umbrella_rounded,
    'shield': Icons.shield_rounded,
    'lightbulb': Icons.lightbulb_rounded,
    'sun': Icons.wb_sunny_rounded,
    'mosque': Icons.mosque_rounded,
    'more-horizontal': Icons.more_horiz_rounded,
  };

  /// The curated category icon names, same order as the web picker.
  static const List<String> categoryNames = [
    'utensils',
    'shopping-cart',
    'shopping-bag',
    'car',
    'bus',
    'fuel',
    'home',
    'zap',
    'wifi',
    'phone',
    'heart-pulse',
    'pill',
    'graduation-cap',
    'book-open',
    'gamepad-2',
    'film',
    'music',
    'plane',
    'gift',
    'coffee',
    'dumbbell',
    'shirt',
    'baby',
    'dog',
    'briefcase',
    'landmark',
    'piggy-bank',
    'trending-up',
    'wallet',
    'banknote',
    'credit-card',
    'circle-dollar-sign',
    'receipt',
    'circle',
  ];

  /// Web wallet types -> icon (`WALLET_TYPES`).
  static const Map<String, IconData> walletTypes = {
    'cash': Icons.payments_rounded,
    'bank': Icons.account_balance_wallet_rounded,
    'ewallet': Icons.smartphone_rounded,
    'credit': Icons.credit_card_rounded,
    'savings': Icons.savings_rounded,
    'investment': Icons.trending_up_rounded,
  };

  /// Indonesian labels for wallet types.
  static const Map<String, String> walletTypeLabels = {
    'cash': 'Tunai',
    'bank': 'Rekening Bank',
    'ewallet': 'E-Wallet',
    'credit': 'Kartu Kredit',
    'savings': 'Tabungan',
    'investment': 'Investasi',
  };

  /// Normalizes `HeartPulse`, `heart_pulse`, `Heart Pulse` -> `heart-pulse`.
  static String normalize(String name) {
    final withDashes = name
        .trim()
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z0-9])'),
          (m) => '${m[1]}-${m[2]}',
        )
        .replaceAll(RegExp(r'[\s_]+'), '-');
    return withDashes.toLowerCase();
  }

  /// Icon for a stored name; [fallback] if unknown or null.
  static IconData of(String? name, {IconData fallback = GhinaIcons.fallback}) {
    if (name == null || name.isEmpty) return fallback;
    return byName[name] ?? byName[normalize(name)] ?? fallback;
  }

  /// Reverse lookup (first matching name), e.g. to persist a picked icon.
  static String? nameOf(IconData icon) {
    for (final e in byName.entries) {
      if (e.value == icon) return e.key;
    }
    return null;
  }

  /// Wallet type (`cash`, `bank`, ...) -> icon.
  static IconData walletType(String? type) =>
      walletTypes[type] ?? Icons.account_balance_wallet_rounded;
}
