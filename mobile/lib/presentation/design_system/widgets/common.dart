import 'package:flutter/material.dart';

import '../format/money_format.dart';
import '../icons/ghina_icons.dart';
import '../mascot/mascot_view.dart';
import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_button.dart';

/// Friendly empty state: mascot, title, message, optional CTA.
///
/// ```dart
/// EmptyState(
///   mood: MascotMood.sleeping,
///   title: 'Belum ada transaksi',
///   message: 'Catat pengeluaran pertamamu, biar Ghina bangun! 😴',
///   actionLabel: 'Catat sekarang',
///   onAction: () => context.push('/transactions/new'),
/// );
/// ```
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.mood = MascotMood.sleeping,
    this.actionLabel,
    this.onAction,
    this.mascotSize = 140,
    this.compact = false,
  });

  final String title;
  final String? message;
  final MascotMood mood;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double mascotSize;

  /// Smaller version for inside cards/sections.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final size = compact ? mascotSize * 0.6 : mascotSize;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 28,
          vertical: compact ? 12 : 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MascotView(mood: mood, size: size),
            SizedBox(height: compact ? 8 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (compact ? GhinaType.h3 : GhinaType.h2)
                  .w(900)
                  .copyWith(color: g.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: GhinaType.body.copyWith(color: g.textSecondary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 14 : 22),
              ChunkyButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                size: compact
                    ? ChunkyButtonSize.medium
                    : ChunkyButtonSize.large,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section title with optional action on the right ("Lihat semua").
///
/// ```dart
/// SectionHeader(title: 'Transaksi terbaru', actionLabel: 'Lihat semua', onAction: openAll);
/// ```
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 8, bottom: 12),
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (actionLabel != null && onAction != null)
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    actionLabel!.toUpperCase(),
                    style: GhinaType.button.copyWith(
                      color: GhinaColors.blue.base,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How [MoneyText] colors itself.
enum MoneyTone {
  /// Negative red, positive green, zero neutral.
  auto,

  /// Always red with a leading "-" (expense rows, amount stored positive).
  expense,

  /// Always green with a leading "+".
  income,

  /// Blue, no sign (transfers).
  transfer,

  /// Theme text color, no sign (balances).
  neutral,
}

/// Formatted money, colored by sign/type, with optional count-up animation.
/// Either pass [amount] (+ [currency]) or a preformatted [text].
///
/// ```dart
/// MoneyText(amount: 25000, tone: MoneyTone.expense);            // -Rp 25.000 (red)
/// MoneyText(amount: balance, style: GhinaType.moneyXL, countUp: true); // hero balance
/// MoneyText(amount: 12.5, currency: 'USD', tone: MoneyTone.income);
/// MoneyText(text: 'Rp 1,2 jt', tone: MoneyTone.neutral);
/// ```
class MoneyText extends StatelessWidget {
  const MoneyText({
    super.key,
    this.amount,
    this.text,
    this.currency = 'IDR',
    this.tone = MoneyTone.auto,
    this.style,
    this.countUp = false,
    this.compact = false,
    this.textAlign,
    this.color,
  }) : assert(amount != null || text != null);

  /// Overrides the tone color (e.g. white on a colored card).
  final Color? color;

  final num? amount;
  final String? text;
  final String currency;
  final MoneyTone tone;

  /// Defaults to [GhinaType.moneyM].
  final TextStyle? style;

  /// Animate from 0 (or the previous value) to [amount].
  final bool countUp;

  /// `Rp 1,2 jt` style.
  final bool compact;
  final TextAlign? textAlign;

  Color _color(GhinaTokens g, num v) =>
      color ??
      switch (tone) {
        MoneyTone.expense => GhinaColors.red.base,
        MoneyTone.income => GhinaColors.green.base,
        MoneyTone.transfer => GhinaColors.blue.base,
        MoneyTone.neutral => g.textPrimary,
        MoneyTone.auto =>
          v < 0
              ? GhinaColors.red.base
              : v > 0
              ? GhinaColors.green.base
              : g.textPrimary,
      };

  String _format(num v) {
    final abs = v.abs();
    final body = GhinaMoney.format(abs, currency: currency, compact: compact);
    return switch (tone) {
      MoneyTone.expense => '-$body',
      MoneyTone.income => '+$body',
      MoneyTone.auto => v < 0 ? '-$body' : (v > 0 ? '+$body' : body),
      _ => v < 0 ? '-$body' : body,
    };
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final base = style ?? GhinaType.moneyM;
    if (amount == null) {
      return Text(
        text!,
        textAlign: textAlign,
        style: base.copyWith(color: _color(g, 0)),
      );
    }
    Widget build(num v) => Text(
      _format(v),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: base.copyWith(color: _color(g, amount!)),
    );
    if (!countUp) return build(amount!);
    final isInt = GhinaMoney.decimalsFor(currency) == 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: amount!.toDouble()),
      duration: GhinaMotion.countUp,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => build(isInt ? v.round() : v),
    );
  }
}

/// Category / wallet avatar: rounded square in the category color with a
/// white icon and a darker bottom edge.
///
/// ```dart
/// CategoryAvatar(iconName: category.icon, colorHex: category.color);
/// CategoryAvatar(icon: GhinaIcons.walletType('ewallet'), color: Colors.teal, size: 36);
/// CategoryAvatar(iconName: 'utensils', colorHex: '#f97316', soft: true);  // pale variant
/// ```
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    this.iconName,
    this.icon,
    this.colorHex,
    this.color,
    this.size = 44,
    this.soft = false,
  });

  final String? iconName;
  final IconData? icon;
  final String? colorHex;
  final Color? color;
  final double size;

  /// Pale tint background with colored icon.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = color ?? CategoryColors.parse(colorHex);
    final sw = ChunkySwatch.fromColor(c);
    final ic = icon ?? GhinaIcons.of(iconName);
    final radius = BorderRadius.circular(size * 0.3);
    final depth = size * 0.07;
    if (soft) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: sw.tint(g.brightness),
          borderRadius: radius,
        ),
        child: Icon(ic, color: c, size: size * 0.55),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: sw.edge, borderRadius: radius),
        child: Padding(
          padding: EdgeInsets.only(bottom: depth),
          child: DecoratedBox(
            decoration: BoxDecoration(color: c, borderRadius: radius),
            child: Center(
              child: Icon(ic, color: sw.on, size: size * 0.52),
            ),
          ),
        ),
      ),
    );
  }
}
