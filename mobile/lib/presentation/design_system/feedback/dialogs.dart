import 'package:flutter/material.dart';

import '../mascot/mascot_view.dart';
import '../theme/ghina_tokens.dart';
import '../theme/typography.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import '../widgets/chunky_button.dart';

/// Chunky dialog body: optional mascot on top, title, message, stacked
/// buttons. Usually shown via [showChunkyConfirm] / [showChunkyDialog].
class ChunkyDialog extends StatelessWidget {
  const ChunkyDialog({
    super.key,
    required this.title,
    this.message,
    this.mood,
    this.content,
    this.actions = const [],
  });

  final String title;
  final String? message;

  /// Shows the mascot above the title.
  final MascotMood? mood;

  /// Extra content under the message.
  final Widget? content;

  /// Buttons, stacked vertically (primary first).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mood != null) ...[
              MascotView(mood: mood!, size: 104),
              const SizedBox(height: 8),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: GhinaType.body.copyWith(color: g.textSecondary),
              ),
            ],
            if (content != null) ...[const SizedBox(height: 14), content!],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                actions[i],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows any widget as a pop-in dialog with Ghina's scrim & motion.
Future<T?> showChunkyDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: GhinaMotion.medium,
    pageBuilder: (c, _, _) => builder(c),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.85,
          end: 1.0,
        ).animate(CurvedAnimation(parent: a, curve: GhinaMotion.pop)),
        child: child,
      ),
    ),
  );
}

/// Confirm dialog. Returns `true` when confirmed, `false` otherwise.
///
/// ```dart
/// final ok = await showChunkyConfirm(
///   context,
///   title: 'Hapus transaksi?',
///   message: 'Transaksi ini akan dihapus permanen.',
///   confirmLabel: 'Hapus',
///   destructive: true,
/// );
/// if (ok) deleteTx();
/// ```
Future<bool> showChunkyConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Ya, lanjut',
  String cancelLabel = 'Batal',
  bool destructive = false,
  MascotMood? mood,
}) async {
  final r = await showChunkyDialog<bool>(
    context,
    builder: (c) => ChunkyDialog(
      title: title,
      message: message,
      mood: mood ?? (destructive ? MascotMood.sad : null),
      actions: [
        ChunkyButton(
          label: confirmLabel,
          variant: destructive
              ? ChunkyButtonVariant.danger
              : ChunkyButtonVariant.primary,
          onPressed: () => Navigator.of(c).pop(true),
        ),
        ChunkyButton(
          label: cancelLabel,
          variant: ChunkyButtonVariant.ghost,
          color: destructive ? null : GhinaColors.blue,
          onPressed: () => Navigator.of(c).pop(false),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Rounded modal bottom sheet with a title row and Ghina styling.
/// Content scrolls if tall; keyboard-safe.
///
/// ```dart
/// final wallet = await showChunkyBottomSheet<Wallet>(
///   context,
///   title: 'Pilih dompet',
///   builder: (c) => Column(children: [
///     for (final w in wallets)
///       ChunkyTile(title: w.name, onTap: () => Navigator.pop(c, w)),
///   ]),
/// );
/// ```
Future<T?> showChunkyBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = true,
  bool showClose = false,
  EdgeInsets padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (c) => ChunkyBottomSheet(
      title: title,
      showClose: showClose,
      padding: padding,
      child: builder(c),
    ),
  );
}

/// The sheet body used by [showChunkyBottomSheet]; use directly for
/// custom sheets.
class ChunkyBottomSheet extends StatelessWidget {
  const ChunkyBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.showClose = false,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
  });

  final Widget child;
  final String? title;
  final bool showClose;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        style: GhinaType.h2
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (showClose)
                      ChunkyIconButton(
                        icon: Icons.close_rounded,
                        size: 38,
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}
