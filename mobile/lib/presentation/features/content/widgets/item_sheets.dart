import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'content_visuals.dart';

/// Add/edit an asset link. Returns the link, or null.
Future<AssetLink?> showAssetLinkSheet(
  BuildContext context, {
  AssetLink? initial,
}) => showChunkyBottomSheet<AssetLink>(
  context,
  title: initial == null ? 'Tambah link aset' : 'Ubah link aset',
  showClose: true,
  builder: (_) => _AssetLinkSheet(initial: initial),
);

class _AssetLinkSheet extends StatefulWidget {
  const _AssetLinkSheet({this.initial});
  final AssetLink? initial;

  @override
  State<_AssetLinkSheet> createState() => _AssetLinkSheetState();
}

class _AssetLinkSheetState extends State<_AssetLinkSheet> {
  late final _url = TextEditingController(text: widget.initial?.url ?? '');
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final u = _url.text.trim();
    if (!isHttpUrl(u)) {
      setState(() => _error = 'Link harus diawali http:// atau https://');
      return;
    }
    final l = _label.text.trim();
    Navigator.of(context).pop(
      AssetLink(
        url: u,
        label: l.isEmpty
            ? null
            : l.substring(0, l.length.clamp(0, assetLabelMax)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChunkyTextField(
        key: const ValueKey('asset-url'),
        controller: _url,
        label: 'Link',
        hint: 'https://drive.google.com/…',
        keyboardType: TextInputType.url,
        textCapitalization: TextCapitalization.none,
        autofocus: widget.initial == null,
        errorText: _error,
      ),
      const SizedBox(height: 12),
      ChunkyTextField(
        key: const ValueKey('asset-label'),
        controller: _label,
        label: 'Nama (opsional)',
        hint: 'Mis. Draft Canva',
        maxLength: assetLabelMax,
      ),
      const SizedBox(height: 16),
      ChunkyButton(
        key: const ValueKey('asset-save'),
        label: 'Simpan link',
        onPressed: _save,
      ),
    ],
  );
}

/// Result of the "Tandai dibayar" sheet: record income into [walletId]
/// (null = just mark paid).
typedef SponsorPaidChoice = ({bool record, String? walletId});

/// "Tandai dibayar": offer to record `Endorse <brand>` as income.
Future<SponsorPaidChoice?> showSponsorPaidSheet(
  BuildContext context, {
  required Sponsor sponsor,
}) => showChunkyBottomSheet<SponsorPaidChoice>(
  context,
  title: 'Sponsor dibayar 🎉',
  showClose: true,
  builder: (_) => _SponsorPaidSheet(sponsor: sponsor),
);

class _SponsorPaidSheet extends ConsumerStatefulWidget {
  const _SponsorPaidSheet({required this.sponsor});
  final Sponsor sponsor;

  @override
  ConsumerState<_SponsorPaidSheet> createState() => _SponsorPaidSheetState();
}

class _SponsorPaidSheetState extends ConsumerState<_SponsorPaidSheet> {
  String? _walletId;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = widget.sponsor;
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    _walletId ??= wallets.firstOrNull?.id;
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final barter = s.amount <= 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          barter
              ? 'Endorse ${s.brand} (barter) ditandai lunas.'
              : 'Catat Endorse ${s.brand} sebagai pemasukan?',
          style: GhinaType.body.copyWith(color: g.textSecondary),
        ),
        if (!barter) ...[
          const SizedBox(height: 12),
          Center(
            child: MoneyText(
              amount: s.amount,
              currency: s.currency,
              tone: MoneyTone.income,
              style: GhinaType.moneyL,
            ),
          ),
          const SizedBox(height: 16),
          PickerField(
            key: const ValueKey('sponsor-wallet'),
            label: 'Masuk ke dompet',
            value: wallet?.name,
            placeholder: 'Pilih dompet',
            errorText: _error,
            leading: wallet == null
                ? null
                : WalletAvatar(wallet: wallet, size: 32),
            onTap: () async {
              final id = await showWalletPickerSheet(
                context,
                wallets: wallets,
                currency: s.currency,
                selectedId: _walletId,
              );
              if (id != null && id.isNotEmpty) {
                setState(() {
                  _walletId = id;
                  _error = null;
                });
              }
            },
          ),
          const SizedBox(height: 20),
          ChunkyButton(
            key: const ValueKey('sponsor-record'),
            label: 'Catat & tandai lunas',
            icon: Icons.savings_rounded,
            color: GhinaColors.green,
            onPressed: () {
              if (_walletId == null) {
                setState(() => _error = 'Pilih dompet dulu');
                return;
              }
              Navigator.of(context).pop((record: true, walletId: _walletId));
            },
          ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 20),
        ChunkyButton(
          key: const ValueKey('sponsor-mark-only'),
          label: barter ? 'Tandai lunas' : 'Tandai lunas saja',
          variant: barter
              ? ChunkyButtonVariant.primary
              : ChunkyButtonVariant.ghost,
          color: barter ? GhinaColors.green : null,
          onPressed: () =>
              Navigator.of(context).pop((record: false, walletId: null)),
        ),
      ],
    );
  }
}

/// Pick an account for a new post (accounts already used are hidden).
/// Returns the account id, or null.
Future<String?> showAddPostAccountSheet(
  BuildContext context, {
  required List<SocialAccount> accounts,
  required Set<String> used,
  required VoidCallback onManage,
}) => showChunkyBottomSheet<String>(
  context,
  title: 'Tayang di akun mana?',
  showClose: true,
  builder: (c) {
    final free = [
      for (final a in accounts)
        if (!used.contains(a.id)) a,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (free.isEmpty)
          EmptyState(
            compact: true,
            mood: MascotMood.thinking,
            title: accounts.isEmpty ? 'Belum ada akun' : 'Semua akun sudah',
            message: accounts.isEmpty
                ? 'Tambahkan akun sosmed kamu dulu.'
                : 'Konten ini sudah punya posting di semua akunmu.',
            actionLabel: 'Kelola akun',
            onAction: () {
              Navigator.of(c).pop();
              onManage();
            },
          ),
        for (final a in free)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              key: ValueKey('add-post-${a.id}'),
              leading: AccountAvatar(account: a, size: 40),
              title: a.atHandle,
              subtitle: a.hasTarget
                  ? '${a.platformLabel} · target ${a.targetPerWeek}/minggu'
                  : a.platformLabel,
              onTap: () => Navigator.of(c).pop(a.id),
            ),
          ),
      ],
    );
  },
);
