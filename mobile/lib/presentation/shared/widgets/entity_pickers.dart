import 'package:flutter/material.dart';

import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import 'wallet_avatar.dart';

/// Selection sheet for categories. Returns the id, `''` for "none", null when
/// dismissed.
Future<String?> showCategoryPickerSheet(
  BuildContext context, {
  required List<TxCategory> categories,
  String? selectedId,
  String title = 'Pilih kategori',
  String? noneLabel,
  String Function(TxCategory c)? subtitleOf,
  VoidCallback? onCreateNew,
}) => showChunkyBottomSheet<String>(
  context,
  title: title,
  showClose: true,
  builder: (c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (noneLabel != null)
        _PickRow(
          selected: selectedId == null || selectedId.isEmpty,
          leading: CategoryAvatar(
            iconName: 'circle',
            colorHex: CategoryTotal.uncategorizedColor,
            size: 40,
            soft: true,
          ),
          title: noneLabel,
          onTap: () => Navigator.of(c).pop(''),
        ),
      for (final cat in categories)
        _PickRow(
          selected: cat.id == selectedId,
          leading: CategoryAvatar(
            iconName: cat.icon,
            colorHex: cat.color,
            size: 40,
          ),
          title: cat.name,
          subtitle: subtitleOf?.call(cat),
          onTap: () => Navigator.of(c).pop(cat.id),
        ),
      if (categories.isEmpty && onCreateNew != null)
        EmptyState(
          compact: true,
          title: 'Belum ada kategori',
          message: 'Buat kategori dulu, yuk.',
          actionLabel: 'Buat kategori',
          onAction: () {
            Navigator.of(c).pop();
            onCreateNew();
          },
        ),
    ],
  ),
);

/// Selection sheet for wallets. Returns the id, `''` for "none", null when
/// dismissed.
Future<String?> showWalletPickerSheet(
  BuildContext context, {
  required List<Wallet> wallets,
  required String currency,
  String? selectedId,
  String title = 'Pilih dompet',
  String? noneLabel,
}) => showChunkyBottomSheet<String>(
  context,
  title: title,
  showClose: true,
  builder: (c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (noneLabel != null)
        _PickRow(
          selected: selectedId == null || selectedId.isEmpty,
          leading: CategoryAvatar(
            icon: Icons.block_rounded,
            colorHex: CategoryTotal.uncategorizedColor,
            size: 40,
            soft: true,
          ),
          title: noneLabel,
          onTap: () => Navigator.of(c).pop(''),
        ),
      for (final w in wallets)
        _PickRow(
          selected: w.id == selectedId,
          leading: WalletAvatar(wallet: w, size: 40),
          title: w.name,
          subtitle: GhinaMoney.format(
            w.balance,
            currency: w.currency.isEmpty ? currency : w.currency,
          ),
          onTap: () => Navigator.of(c).pop(w.id),
        ),
    ],
  ),
);

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.selected,
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final bool selected;
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ChunkyTile(
      dense: true,
      tinted: selected ? GhinaColors.blue : null,
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: GhinaColors.blue.base)
          : null,
      onTap: onTap,
    ),
  );
}
