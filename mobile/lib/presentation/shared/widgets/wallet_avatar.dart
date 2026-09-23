import 'package:flutter/material.dart';

import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';

/// Icon for a wallet: its custom icon when it is a known name, else its type's
/// icon (the web stores the type id as the icon, e.g. `cash`).
IconData walletIconOf(WalletType type, String? icon) {
  if (icon != null &&
      icon != type.wire &&
      GhinaIcons.byName.containsKey(icon)) {
    return GhinaIcons.of(icon);
  }
  return GhinaIcons.walletType(type.wire);
}

IconData walletIcon(Wallet w) => walletIconOf(w.type, w.icon);

/// Rounded-square avatar in the wallet color with its icon.
class WalletAvatar extends StatelessWidget {
  const WalletAvatar({
    super.key,
    required this.wallet,
    this.size = 44,
    this.soft = false,
  });

  final Wallet wallet;
  final double size;
  final bool soft;

  @override
  Widget build(BuildContext context) => CategoryAvatar(
    icon: walletIcon(wallet),
    colorHex: wallet.color,
    size: size,
    soft: soft,
  );
}
