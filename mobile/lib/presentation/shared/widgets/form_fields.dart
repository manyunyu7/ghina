import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/formatters.dart';
import '../../design_system/design_system.dart';

/// Bold field label above an input (same look as [ChunkyTextField]'s label).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing, this.error = false});

  final String text;
  final Widget? trailing;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: GhinaType.body
                  .w(800)
                  .copyWith(
                    color: error ? GhinaColors.red.base : g.textPrimary,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A tappable, input-looking field that opens a picker.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.onTap,
    this.leading,
    this.value,
    this.placeholder = 'Pilih',
    this.errorText,
    this.enabled = true,
    this.trailingIcon = Icons.expand_more_rounded,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? leading;
  final String? value;
  final String placeholder;
  final String? errorText;
  final bool enabled;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final hasError = errorText != null;
    return Shake(
      trigger: errorText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FieldLabel(label, error: hasError),
          ChunkySurface(
            color: g.surfaceAlt,
            edgeColor: hasError ? GhinaColors.red.base : g.border,
            borderColor: hasError ? GhinaColors.red.base : g.border,
            depth: 0,
            borderRadius: GhinaRadii.rLg,
            onTap: enabled ? onTap : null,
            enabled: enabled,
            semanticLabel: label,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Text(
                      value ?? placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyL
                          .w(700)
                          .copyWith(
                            color: value == null
                                ? g.textMuted
                                : (enabled ? g.textPrimary : g.textSecondary),
                          ),
                    ),
                  ),
                  if (enabled) Icon(trailingIcon, color: g.textMuted),
                ],
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                errorText!,
                style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Groups digits as you type (`25000` → `25.000`); decimals after a comma for
/// currencies that have them.
class AmountInputFormatter extends TextInputFormatter {
  AmountInputFormatter({this.decimals = 0});
  final int decimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text.replaceAll('.', '');
    String intPart = raw, frac = '';
    final comma = raw.indexOf(',');
    if (decimals > 0 && comma >= 0) {
      intPart = raw.substring(0, comma);
      frac = raw.substring(comma + 1).replaceAll(',', '');
      if (frac.length > decimals) frac = frac.substring(0, decimals);
    }
    intPart = intPart.replaceAll(RegExp(r'[^0-9]'), '');
    frac = frac.replaceAll(RegExp(r'[^0-9]'), '');
    if (intPart.length > 13) return oldValue;
    intPart = intPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final grouped = intPart.isEmpty ? '' : Fmt.number(int.parse(intPart));
    final text = decimals > 0 && comma >= 0
        ? '${grouped.isEmpty ? '0' : grouped},$frac'
        : grouped;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Text for an amount controller (`25.000`).
String amountToInput(num? v, String currency) {
  if (v == null || v == 0) return '';
  final d = GhinaMoney.decimalsFor(currency);
  if (d == 0) return Fmt.number(v.round());
  return Fmt.number(v, decimals: d).replaceFirst(RegExp(r',?0+$'), '');
}

/// Parses what [AmountInputFormatter] produced (null when empty).
double? parseAmountInput(String text) => Fmt.parseAmount(text);

/// Chunky money input: "Rp" prefix, big bold digits, grouped as you type.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    this.label = 'Nominal',
    this.errorText,
    this.onChanged,
    this.autofocus = false,
    this.helperText,
  });

  final TextEditingController controller;
  final String currency;
  final String label;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final decimals = GhinaMoney.decimalsFor(currency);
    return ChunkyTextField(
      label: label,
      hint: '0',
      controller: controller,
      errorText: errorText,
      helperText: helperText,
      autofocus: autofocus,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
      textInputAction: TextInputAction.done,
      inputFormatters: [AmountInputFormatter(decimals: decimals)],
      suffix: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            GhinaMoney.symbolFor(currency),
            style: GhinaType.bodyL.w(900).copyWith(color: g.textMuted),
          ),
        ),
      ),
    );
  }
}
