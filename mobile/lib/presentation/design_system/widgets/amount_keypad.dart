import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format/money_format.dart';
import '../motion/motion.dart';
import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'chunky_button.dart';
import 'chunky_surface.dart';

/// Holds the amount typed on an [AmountKeypad] as a digit string so it can
/// represent "12." while typing. Read [amount] for the numeric value.
///
/// ```dart
/// final amount = AmountController(currency: 'IDR');   // IDR: whole numbers
/// ...
/// AmountDisplay(controller: amount, color: GhinaColors.red),
/// AmountKeypad(controller: amount, onSubmit: save),
/// ...
/// createTx(amount: amount.amount);
/// ```
class AmountController extends ValueNotifier<String> {
  AmountController({
    String currency = 'IDR',
    num? initial,
    this.maxIntegerDigits = 12,
  }) : decimals = GhinaMoney.decimalsFor(currency),
       currency = currency,
       super(_initial(initial, GhinaMoney.decimalsFor(currency)));

  static String _initial(num? v, int decimals) {
    if (v == null || v == 0) return '';
    if (decimals == 0) return v.round().toString();
    final s = v.toStringAsFixed(decimals);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  final int decimals;
  final int maxIntegerDigits;
  final String currency;

  /// Numeric amount (0 when empty).
  num get amount {
    if (value.isEmpty || value == '.') return 0;
    return decimals == 0 ? int.parse(value) : double.parse(value);
  }

  bool get isEmpty => amount == 0;

  set amount(num v) => value = _initial(v, decimals);

  /// Formatted with symbol, e.g. `Rp 25.000`.
  String get formatted => GhinaMoney.format(amount, currency: currency);

  /// Returns false (and doesn't change) if the input would be invalid.
  bool input(String key) {
    final v = value;
    switch (key) {
      case '⌫':
        if (v.isNotEmpty) value = v.substring(0, v.length - 1);
        return true;
      case 'C':
        value = '';
        return true;
      case '.':
        if (decimals == 0 || v.contains('.')) return false;
        value = v.isEmpty ? '0.' : '$v.';
        return true;
    }
    if (!RegExp(r'^\d+$').hasMatch(key)) return false;
    var next = v + key;
    if (next.startsWith('0') && !next.startsWith('0.')) {
      next = next.replaceFirst(RegExp(r'^0+'), '');
      if (next.isEmpty || next.startsWith('.')) next = '0$next';
      if (next == '0') next = '';
    }
    final parts = next.split('.');
    if (parts[0].length > maxIntegerDigits) return false;
    if (parts.length > 1 && parts[1].length > decimals) return false;
    value = next;
    return true;
  }
}

/// Big amount readout for amount entry screens, with a blinking caret.
/// Colors by [color] (red for expense, green
/// for income, blue for transfer).
class AmountDisplay extends StatefulWidget {
  const AmountDisplay({
    super.key,
    required this.controller,
    this.color,
    this.label,
  });

  final AmountController controller;
  final ChunkySwatch? color;

  /// Small overline above the number, e.g. 'PENGELUARAN'.
  final String? label;

  @override
  State<AmountDisplay> createState() => _AmountDisplayState();
}

class _AmountDisplayState extends State<AmountDisplay>
    with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final color = widget.color?.base ?? g.textPrimary;
    return ValueListenableBuilder<String>(
      valueListenable: widget.controller,
      builder: (context, raw, _) {
        final c = widget.controller;
        final empty = raw.isEmpty;
        final symbol = GhinaMoney.symbolFor(c.currency);
        String numberText;
        if (empty) {
          numberText = '0';
        } else {
          final parts = raw.split('.');
          numberText = GhinaMoney.number(int.parse(parts[0]), currency: 'IDR');
          if (c.currency.toUpperCase() != 'IDR') {
            numberText = numberText.replaceAll('.', ',');
          }
          if (parts.length > 1) {
            numberText +=
                '${c.currency.toUpperCase() == 'IDR' ? ',' : '.'}${parts[1]}';
          }
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null)
              Text(
                widget.label!.toUpperCase(),
                style: GhinaType.overline.copyWith(
                  color: widget.color?.base ?? g.textSecondary,
                ),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '$symbol ',
                    style: GhinaType.moneyL.copyWith(
                      color: empty
                          ? g.textMuted
                          : color.withValues(alpha: 0.75),
                    ),
                  ),
                  Text(
                    numberText,
                    style: GhinaType.moneyXL.copyWith(
                      fontSize: 52,
                      color: empty ? g.textMuted : color,
                    ),
                  ),
                  FadeTransition(
                    opacity: _blink.drive(
                      TweenSequence([
                        TweenSequenceItem(tween: ConstantTween(1.0), weight: 1),
                        TweenSequenceItem(tween: ConstantTween(0.0), weight: 1),
                      ]),
                    ),
                    child: Container(
                      width: 4,
                      height: 46,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: widget.color?.base ?? GhinaColors.blue.base,
                        borderRadius: GhinaRadii.rPill,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Big-key numeric keypad for fast amount entry (1–9, 000, 0, backspace).
/// Long-press backspace clears; rejected input shakes the pad. Optional quick-add chips and a submit CTA.
///
/// ```dart
/// AmountKeypad(
///   controller: amount,
///   quickAmounts: const [10000, 20000, 50000, 100000],
///   submitLabel: 'Simpan',
///   onSubmit: save, // auto-disabled while the amount is 0
/// );
/// ```
class AmountKeypad extends StatefulWidget {
  const AmountKeypad({
    super.key,
    required this.controller,
    this.onSubmit,
    this.submitLabel = 'Lanjut',
    this.submitColor,
    this.quickAmounts = const [],
    this.keyHeight = 60,
  });

  final AmountController controller;

  /// Null hides the submit button.
  final VoidCallback? onSubmit;
  final String submitLabel;
  final ChunkySwatch? submitColor;

  /// Chips that *add* the amount (e.g. +10rb).
  final List<num> quickAmounts;
  final double keyHeight;

  @override
  State<AmountKeypad> createState() => _AmountKeypadState();
}

class _AmountKeypadState extends State<AmountKeypad> {
  int _rejects = 0;

  void _press(String k) {
    final ok = widget.controller.input(k);
    if (!ok) {
      HapticFeedback.heavyImpact();
      setState(() => _rejects++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = widget.controller;
    final keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      c.decimals > 0 ? '.' : '000',
      '0',
      '⌫',
    ];

    Widget key(String k) {
      final isBack = k == '⌫';
      final child = isBack
          ? Icon(Icons.backspace_rounded, color: g.textSecondary, size: 26)
          : Text(
              k == '.' ? ',' : k,
              style: GhinaType.h1
                  .w(900)
                  .copyWith(
                    color: g.textPrimary,
                    fontSize: k == '000' ? 22 : 28,
                  ),
            );
      return Padding(
        padding: const EdgeInsets.all(5),
        child: ChunkySurface(
          color: g.surface,
          edgeColor: g.borderEdge,
          borderColor: g.border,
          depth: GhinaDepth.md,
          borderRadius: GhinaRadii.rLg,
          semanticLabel: isBack ? 'Hapus' : k,
          onTap: () => _press(k),
          onLongPress: isBack ? () => _press('C') : null,
          child: SizedBox(
            height: widget.keyHeight,
            child: Center(child: child),
          ),
        ),
      );
    }

    return Shake(
      trigger: _rejects == 0 ? null : _rejects,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.quickAmounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Row(
                  children: [
                    for (final q in widget.quickAmounts)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChunkySurface(
                          color: GhinaColors.blue.tint(g.brightness),
                          edgeColor: GhinaColors.blue.tintBorder(g.brightness),
                          borderColor: GhinaColors.blue.tintBorder(
                            g.brightness,
                          ),
                          depth: GhinaDepth.sm,
                          borderRadius: GhinaRadii.rMd,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          onTap: () => c.amount = c.amount + q,
                          child: Text(
                            '+${GhinaMoney.format(q, currency: c.currency, compact: true).replaceFirst(RegExp(r'^\S+ '), '')}',
                            style: GhinaType.body
                                .w(900)
                                .copyWith(color: GhinaColors.blue.base),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          for (var r = 0; r < 4; r++)
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(child: key(keys[r * 3 + i])),
              ],
            ),
          if (widget.onSubmit != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: ValueListenableBuilder(
                valueListenable: c,
                builder: (context, _, _) => ChunkyButton(
                  label: widget.submitLabel,
                  color: widget.submitColor,
                  onPressed: c.isEmpty ? null : widget.onSubmit,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
