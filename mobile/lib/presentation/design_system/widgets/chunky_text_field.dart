import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';

/// Rounded, filled text field with a bold label above it. Shakes when
/// [errorText] appears or changes.
///
/// ```dart
/// ChunkyTextField(
///   label: 'Catatan',
///   hint: 'Contoh: makan siang bareng tim',
///   controller: _note,
///   prefixIcon: Icons.edit_note_rounded,
/// );
/// ChunkyTextField(label: 'Email', keyboardType: TextInputType.emailAddress,
///   errorText: state.emailError);
/// ChunkyTextField(label: 'Kata sandi', obscureText: true);
/// ```
///
/// Works inside a [Form] via [validator].
class ChunkyTextField extends StatefulWidget {
  const ChunkyTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.focusNode,
    this.onTap,
    this.textCapitalization = TextCapitalization.sentences,
    this.autofillHints,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  /// Password field. Adds a show/hide eye toggle automatically.
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final FocusNode? focusNode;

  /// For picker-like fields (date, wallet) combine with [readOnly].
  final VoidCallback? onTap;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;

  @override
  State<ChunkyTextField> createState() => _ChunkyTextFieldState();
}

class _ChunkyTextFieldState extends State<ChunkyTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget? suffix = widget.suffix;
    if (widget.obscureText) {
      suffix = IconButton(
        onPressed: () => setState(() => _obscured = !_obscured),
        tooltip: _obscured ? 'Tampilkan' : 'Sembunyikan',
        icon: Icon(
          _obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        ),
      );
    }

    final field = TextFormField(
      controller: widget.controller,
      initialValue: widget.controller == null ? widget.initialValue : null,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      obscureText: _obscured,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      focusNode: widget.focusNode,
      onTap: widget.onTap,
      textCapitalization: widget.obscureText
          ? TextCapitalization.none
          : widget.textCapitalization,
      autofillHints: widget.autofillHints,
      style: GhinaType.bodyL.w(700).copyWith(color: g.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hint,
        errorText: widget.errorText,
        helperText: widget.helperText,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
        suffixIcon: suffix,
      ),
    );

    return Shake(
      trigger: widget.errorText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Text(
              widget.label!,
              style: GhinaType.body
                  .w(800)
                  .copyWith(
                    color: widget.errorText != null
                        ? GhinaColors.red.base
                        : g.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
          ],
          field,
        ],
      ),
    );
  }
}
