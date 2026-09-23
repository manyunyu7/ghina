import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../state/session_controller.dart';
import '../../categories/widgets/category_presets.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/rewards/rewards.dart';
import '../widgets/tx_visuals.dart';

/// Fast add/edit transaction screen (also opened by the center "+").
///
/// Big amount + keypad first; type segmented; category grid (recently used first);
/// wallet / date / note chips. After saving a new transaction the user gets an XP
/// toast or a full celebration.
class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  ConsumerState<TransactionFormPage> createState() =>
      _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage> {
  bool get _isEdit => widget.id != null;

  late AmountController _amount;
  TxType _type = TxType.expense;
  String? _walletId;
  String? _toWalletId;
  String? _categoryId;
  late DateTime _date;
  String _note = '';

  bool _loaded = false;
  bool _saving = false;
  bool _deleted = false;
  int _walletShake = 0;
  int _toWalletShake = 0;

  @override
  void initState() {
    super.initState();
    _amount = AmountController(currency: ref.read(currencyProvider));
    _date = ref.read(clockProvider).now();
    if (!_isEdit) {
      _loaded = true;
      final preset = ref.read(txFormPresetProvider);
      if (preset != null) {
        _type = preset.type ?? _type;
        _walletId = preset.walletId;
        _categoryId = preset.categoryId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(txFormPresetProvider.notifier).set(null);
        });
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _loadFrom(TransactionView v) {
    final t = v.transaction;
    _type = t.type;
    _walletId = t.walletId;
    _toWalletId = t.toWalletId;
    _categoryId = t.categoryId;
    _date = t.date;
    _note = t.note ?? '';
    _setCurrency(v.wallet?.currency ?? _amount.currency, amount: t.amount);
    _loaded = true;
  }

  void _setCurrency(String currency, {num? amount}) {
    if (currency == _amount.currency && amount == null) return;
    final keep = amount ?? _amount.amount;
    final old = _amount;
    _amount = AmountController(currency: currency, initial: keep);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  // ------------------------------------------------------------------ derived

  String? _defaultWalletId(List<Wallet> active, List<TransactionView> recent) {
    final ids = active.map((w) => w.id).toSet();
    final last = ref.read(lastUsedWalletProvider);
    if (last != null && ids.contains(last)) return last;
    for (final r in recent) {
      if (ids.contains(r.transaction.walletId)) return r.transaction.walletId;
    }
    return active.isEmpty ? null : active.first.id;
  }

  List<TxCategory> _orderedCategories(
    List<TxCategory> all,
    List<TransactionView> recent,
  ) {
    final type = _type == TxType.income
        ? CategoryType.income
        : CategoryType.expense;
    final ofType = all.where((c) => c.type == type).toList();
    final rank = <String, int>{};
    for (final r in recent) {
      final id = r.transaction.categoryId;
      if (id != null) rank.putIfAbsent(id, () => rank.length);
    }
    ofType.sort((a, b) {
      final ra = rank[a.id], rb = rank[b.id];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return ofType;
  }

  // ------------------------------------------------------------------ actions

  void _setType(TxType t, List<TxCategory> categories) {
    setState(() {
      _type = t;
      if (t == TxType.transfer) {
        _categoryId = null;
      } else if (_categoryId != null) {
        final want = t == TxType.income
            ? CategoryType.income
            : CategoryType.expense;
        final c = categories.where((c) => c.id == _categoryId).firstOrNull;
        if (c == null || c.type != want) _categoryId = null;
      }
    });
  }

  Future<void> _pickWallet(
    List<Wallet> wallets, {
    required bool destination,
    String? current,
  }) async {
    final picked = await showChunkyBottomSheet<String>(
      context,
      title: destination ? 'Ke dompet mana?' : 'Pilih dompet',
      builder: (c) => _WalletSheet(
        wallets: wallets,
        selectedId: current,
        disabledId: destination ? _walletId : null,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == _newWalletKey) {
      context.push('/wallets/new');
      return;
    }
    setState(() {
      if (destination) {
        _toWalletId = picked;
      } else {
        _walletId = picked;
        if (_toWalletId == picked) _toWalletId = null;
        final w = wallets.where((w) => w.id == picked).firstOrNull;
        if (w != null) _setCurrency(w.currency);
      }
    });
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).now();
    final d = await showGhinaDatePicker(
      context,
      initial: _date,
      title: 'Tanggal transaksi',
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      today: now,
    );
    if (d == null || !mounted) return;
    setState(
      () => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute),
    );
  }

  Future<void> _editNote() async {
    final ctrl = TextEditingController(text: _note);
    final r = await showChunkyBottomSheet<String>(
      context,
      title: 'Catatan',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyTextField(
            controller: ctrl,
            hint: 'Contoh: makan siang bareng tim',
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(c).pop(v),
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyButton(
            label: 'Simpan catatan',
            onPressed: () => Navigator.of(c).pop(ctrl.text),
          ),
          SizedBox(height: MediaQuery.viewInsetsOf(c).bottom),
        ],
      ),
    );
    ctrl.dispose();
    if (r != null && mounted) setState(() => _note = r.trim());
  }

  Future<void> _save(String? walletId) async {
    if (_saving) return;
    if (walletId == null) {
      setState(() => _walletShake++);
      showErrorToast(context, 'Pilih dompet dulu, ya');
      return;
    }
    if (_type == TxType.transfer) {
      if (_toWalletId == null) {
        setState(() => _toWalletShake++);
        showErrorToast(context, 'Pilih dompet tujuan dulu');
        return;
      }
      if (_toWalletId == walletId) {
        setState(() => _toWalletShake++);
        showErrorToast(context, 'Dompet asal dan tujuan harus beda');
        return;
      }
    }
    final input = TransactionInput(
      type: _type,
      amount: _amount.amount.toDouble(),
      walletId: walletId,
      toWalletId: _type == TxType.transfer ? _toWalletId : null,
      categoryId: _type == TxType.transfer ? null : _categoryId,
      note: _note,
      date: _date,
    );
    setState(() => _saving = true);
    final rewards = RewardTracker.start(ref);
    final r = _isEdit
        ? await ref.read(updateTransactionProvider)(widget.id!, input)
        : await ref.read(createTransactionProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Err(:final failure):
        setState(() => _saving = false);
        showFailureToast(context, failure);
        return;
      case Ok():
    }
    ref.read(lastUsedWalletProvider.notifier).set(walletId);
    if (_isEdit) {
      showOkToast(context, 'Perubahan disimpan 👍');
    } else {
      await rewards.finish(
        context,
        xpToast: (xp) => '+$xp XP',
        doneToast: 'Tercatat! 👍',
        goalHint: true,
      );
    }
    if (mounted) popOr(context, '/transactions');
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus transaksi?',
      message: 'Saldo dompet akan disesuaikan lagi. Ini nggak bisa dibatalkan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleted = true);
    final r = await ref.read(deleteTransactionProvider)(widget.id!);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Transaksi dihapus', icon: Icons.delete_rounded);
        popOr(context, '/transactions');
      case Err(:final failure):
        setState(() => _deleted = false);
        showFailureToast(context, failure);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // Keep the game summary alive so the reward can compare XP before/after.
    ref.watch(gameSummaryProvider);

    if (_isEdit && !_loaded) {
      final tx = ref.watch(watchTransactionProvider(widget.id!));
      switch (tx) {
        case AsyncData(:final value?):
          _loadFrom(value);
        case AsyncData():
          return _scaffold(
            const EmptyState(
              mood: MascotMood.thinking,
              title: 'Transaksinya nggak ketemu',
              message: 'Mungkin sudah dihapus di perangkat lain.',
            ),
          );
        case AsyncError():
          return _scaffold(
            ErrorRetry(
              onRetry: () =>
                  ref.invalidate(watchTransactionProvider(widget.id!)),
            ),
          );
        default:
          return _scaffold(const _FormSkeleton());
      }
    }
    if (_isEdit && _deleted) return _scaffold(const _FormSkeleton());

    final walletsAsync = ref.watch(watchAllWalletsProvider);
    final catsAsync = ref.watch(watchCategoriesProvider(null));
    final recent =
        ref
            .watch(
              watchTransactionsProvider(const TransactionFilter(limit: 60)),
            )
            .value ??
        const <TransactionView>[];

    if (walletsAsync.hasError && !walletsAsync.hasValue) {
      return _scaffold(
        ErrorRetry(onRetry: () => ref.invalidate(watchAllWalletsProvider)),
      );
    }
    final allWallets = walletsAsync.value;
    if (allWallets == null) return _scaffold(const _FormSkeleton());

    final wallets = [
      for (final w in allWallets)
        if (!w.archived || w.id == _walletId || w.id == _toWalletId) w,
    ];
    if (wallets.isEmpty) {
      return _scaffold(
        EmptyState(
          mood: MascotMood.waving,
          title: 'Bikin dompet dulu, yuk!',
          message:
              'Transaksi dicatat ke dompet. Tambah dompet pertamamu (misal: Tunai).',
          actionLabel: 'Tambah dompet',
          onAction: () => context.push('/wallets/new'),
        ),
      );
    }

    final active = wallets.where((w) => !w.archived).toList();
    final walletId = _walletId ?? _defaultWalletId(active, recent);
    final wallet = wallets.where((w) => w.id == walletId).firstOrNull;
    final toWallet = wallets.where((w) => w.id == _toWalletId).firstOrNull;
    if (wallet != null && wallet.currency != _amount.currency) {
      _setCurrency(wallet.currency);
    }
    final allCats = catsAsync.value ?? const <TxCategory>[];
    final cats = _orderedCategories(allCats, recent);
    final sw = txSwatch(_type);

    final height = MediaQuery.sizeOf(context).height;
    final small = height < 720;
    final keyHeight = height < 680 ? 40.0 : (small ? 46.0 : 52.0);

    return _scaffold(
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.md,
              GhinaSpace.page,
              0,
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.1,
              child: ChunkySegmented<TxType>(
                value: _type,
                height: small ? 42 : 46,
                onChanged: (t) => _setType(t, allCats),
                segments: [
                  for (final t in TxType.values)
                    ChunkySegment(value: t, label: t.label, color: txSwatch(t)),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.md,
                GhinaSpace.page,
                GhinaSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AmountDisplay(controller: _amount, color: sw),
                  const SizedBox(height: GhinaSpace.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      spacing: GhinaSpace.sm,
                      children: [
                        if (_type != TxType.transfer)
                          Shake(
                            trigger: _walletShake == 0 ? null : _walletShake,
                            child: _InfoChip(
                              key: const ValueKey('tx-wallet-chip'),
                              leading: wallet == null
                                  ? const Icon(
                                      Icons.account_balance_wallet_rounded,
                                      size: 20,
                                    )
                                  : WalletAvatar(wallet: wallet, size: 24),
                              label: wallet?.name ?? 'Pilih dompet',
                              onTap: () => _pickWallet(
                                active,
                                destination: false,
                                current: walletId,
                              ),
                            ),
                          ),
                        _InfoChip(
                          key: const ValueKey('tx-date-chip'),
                          leading: const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                          ),
                          label: _dateLabel(_date),
                          onTap: _pickDate,
                        ),
                        _InfoChip(
                          key: const ValueKey('tx-note-chip'),
                          leading: const Icon(
                            Icons.edit_note_rounded,
                            size: 22,
                          ),
                          label: _note.isEmpty ? 'Tambah catatan' : _note,
                          muted: _note.isEmpty,
                          onTap: _editNote,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: small ? GhinaSpace.md : GhinaSpace.lg),
                  if (_type == TxType.transfer)
                    _TransferWallets(
                      from: wallet,
                      to: toWallet,
                      fromShake: _walletShake,
                      toShake: _toWalletShake,
                      onFrom: () => _pickWallet(
                        active,
                        destination: false,
                        current: walletId,
                      ),
                      onTo: () => _pickWallet(
                        active,
                        destination: true,
                        current: _toWalletId,
                      ),
                    )
                  else
                    _CategoryGrid(
                      categories: cats,
                      loading: !catsAsync.hasValue,
                      selectedId: _categoryId,
                      type: _type,
                      rows: small ? 1 : 2,
                      onSelect: (id) => setState(
                        () => _categoryId = _categoryId == id ? null : id,
                      ),
                    ),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.ghina.surfaceAlt,
              border: Border(
                top: BorderSide(
                  color: context.ghina.border,
                  width: GhinaDepth.border,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 8, 15, 10),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1,
                  child: AmountKeypad(
                    controller: _amount,
                    keyHeight: keyHeight,
                    submitLabel: _saving
                        ? 'Menyimpan…'
                        : (_isEdit ? 'Simpan perubahan' : 'Simpan'),
                    submitColor: sw,
                    quickAmounts:
                        height >= 860 && _amount.currency == 'IDR' && !_isEdit
                        ? const [10000, 20000, 50000, 100000]
                        : const [],
                    onSubmit: _saving ? null : () => _save(walletId),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime d) {
    final now = ref.read(clockProvider).now();
    final rel = Fmt.relativeDay(d, now: now);
    return isSameDay(d, now) ? rel : Fmt.dateShortWeekday(d);
  }

  Widget _scaffold(Widget body) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Tutup',
        onPressed: () => popOr(context, '/transactions'),
      ),
      title: Text(_isEdit ? 'Edit transaksi' : 'Catat transaksi'),
      actions: [
        if (_isEdit && _loaded && !_deleted)
          IconButton(
            key: const ValueKey('tx-delete'),
            tooltip: 'Hapus',
            icon: Icon(
              Icons.delete_outline_rounded,
              color: GhinaColors.red.base,
            ),
            onPressed: _delete,
          ),
      ],
    ),
    body: body,
  );
}

const _newWalletKey = '__new_wallet__';

// ---------------------------------------------------------------- pieces

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(GhinaSpace.page),
    child: Column(
      children: [
        Skeleton(height: 46),
        SizedBox(height: 24),
        Skeleton(width: 200, height: 52),
        SizedBox(height: 24),
        SkeletonList(count: 3),
      ],
    ),
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - GhinaSpace.page * 2,
      ),
      child: ChunkySurface(
        color: g.surface,
        edgeColor: g.borderEdge,
        borderColor: g.border,
        depth: GhinaDepth.sm,
        borderRadius: GhinaRadii.rPill,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: onTap,
        semanticLabel: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: g.textSecondary),
              child: leading,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.body
                    .w(800)
                    .copyWith(color: muted ? g.textMuted : g.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two rows of category avatars, scrolling sideways; recently used first.
class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({
    required this.categories,
    required this.loading,
    required this.selectedId,
    required this.type,
    required this.onSelect,
    this.rows = 2,
  });

  final int rows;

  final List<TxCategory> categories;
  final bool loading;
  final String? selectedId;
  final TxType type;
  final ValueChanged<String> onSelect;

  CategoryType get _catType =>
      type == TxType.income ? CategoryType.income : CategoryType.expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    if (loading) return const Skeleton(height: 150);
    if (categories.isEmpty) {
      return ChunkyCard(
        tinted: GhinaColors.blue,
        child: Column(
          children: [
            Text(
              'Belum ada kategori ${_catType.label.toLowerCase()}.',
              textAlign: TextAlign.center,
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            const SizedBox(height: GhinaSpace.md),
            ChunkyButton(
              label: 'Pakai kategori bawaan',
              size: ChunkyButtonSize.medium,
              color: GhinaColors.blue,
              onPressed: () async {
                final r = await ref.read(seedDefaultCategoriesProvider)();
                if (r case Err(:final failure) when context.mounted) {
                  showFailureToast(context, failure);
                }
              },
            ),
            const SizedBox(height: GhinaSpace.sm),
            Text(
              'Kategori itu opsional, kok. Boleh langsung simpan.',
              textAlign: TextAlign.center,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ],
        ),
      );
    }
    final selected = categories.where((c) => c.id == selectedId).firstOrNull;
    final cells = <Widget>[
      for (final c in categories)
        _CatCell(
          key: ValueKey('cat-${c.id}'),
          label: c.name,
          selected: c.id == selectedId,
          color: CategoryColors.parse(c.color),
          avatar: CategoryAvatar(iconName: c.icon, colorHex: c.color, size: 46),
          onTap: () => onSelect(c.id),
        ),
      _CatCell(
        label: 'Baru',
        selected: false,
        color: g.textMuted,
        avatar: CategoryAvatar(
          icon: Icons.add_rounded,
          color: g.textMuted,
          size: 46,
          soft: true,
        ),
        onTap: () {
          ref.read(categoryTypePresetProvider.notifier).set(_catType);
          context.push('/categories/new');
        },
      ),
    ];
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'KATEGORI',
                style: GhinaType.overline.copyWith(color: g.textSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected?.name ?? 'opsional',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(
                        color: selected == null
                            ? g.textMuted
                            : CategoryColors.parse(selected.color),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GhinaSpace.sm),
          SizedBox(
            height: rows > 1 && cells.length > 4 ? 176 : 88,
            child: GridView.count(
              scrollDirection: Axis.horizontal,
              crossAxisCount: rows > 1 && cells.length > 4 ? 2 : 1,
              mainAxisSpacing: 4,
              crossAxisSpacing: 0,
              childAspectRatio: 88 / 74,
              padding: EdgeInsets.zero,
              children: cells,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatCell extends StatelessWidget {
  const _CatCell({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.avatar,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final Widget avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: GhinaMotion.fast,
              curve: GhinaMotion.pop,
              child: AnimatedContainer(
                duration: GhinaMotion.fast,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? color : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: avatar,
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GhinaType.caption.copyWith(
                  color: selected ? color : g.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferWallets extends StatelessWidget {
  const _TransferWallets({
    required this.from,
    required this.to,
    required this.fromShake,
    required this.toShake,
    required this.onFrom,
    required this.onTo,
  });

  final Wallet? from;
  final Wallet? to;
  final int fromShake;
  final int toShake;
  final VoidCallback onFrom;
  final VoidCallback onTo;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Shake(
              trigger: fromShake == 0 ? null : fromShake,
              child: _WalletBox(
                key: const ValueKey('tx-from-wallet'),
                caption: 'DARI',
                wallet: from,
                onTap: onFrom,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: GhinaColors.transfer.base,
              size: 28,
            ),
          ),
          Expanded(
            child: Shake(
              trigger: toShake == 0 ? null : toShake,
              child: _WalletBox(
                key: const ValueKey('tx-to-wallet'),
                caption: 'KE',
                wallet: to,
                onTap: onTo,
                placeholderColor: g.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletBox extends StatelessWidget {
  const _WalletBox({
    super.key,
    required this.caption,
    required this.wallet,
    required this.onTap,
    this.placeholderColor,
  });

  final String caption;
  final Wallet? wallet;
  final VoidCallback onTap;
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final w = wallet;
    return ChunkyCard(
      onTap: onTap,
      tinted: w == null ? null : CategoryColors.swatch(w.color),
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            caption,
            style: GhinaType.overline.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 6),
          if (w == null)
            CategoryAvatar(
              icon: Icons.add_rounded,
              color: g.textMuted,
              size: 44,
              soft: true,
            )
          else
            WalletAvatar(wallet: w, size: 44),
          const SizedBox(height: 6),
          Text(
            w?.name ?? 'Pilih dompet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.body
                .w(800)
                .copyWith(color: w == null ? g.textMuted : g.textPrimary),
          ),
          if (w != null)
            MoneyText(
              amount: w.balance,
              currency: w.currency,
              tone: MoneyTone.neutral,
              style: GhinaType.moneyS.copyWith(color: g.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _WalletSheet extends StatelessWidget {
  const _WalletSheet({
    required this.wallets,
    required this.selectedId,
    this.disabledId,
  });

  final List<Wallet> wallets;
  final String? selectedId;
  final String? disabledId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in wallets)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
            child: Opacity(
              opacity: w.id == disabledId ? 0.4 : 1,
              child: ChunkyTile(
                key: ValueKey('wallet-option-${w.id}'),
                leading: WalletAvatar(wallet: w, size: 40),
                title: w.name,
                subtitle: w.type.label,
                dense: true,
                tinted: w.id == selectedId
                    ? CategoryColors.swatch(w.color)
                    : null,
                trailing: MoneyText(
                  amount: w.balance,
                  currency: w.currency,
                  tone: MoneyTone.neutral,
                ),
                onTap: w.id == disabledId
                    ? null
                    : () => Navigator.of(context).pop(w.id),
              ),
            ),
          ),
        const SizedBox(height: GhinaSpace.xs),
        ChunkyButton(
          label: 'Tambah dompet',
          icon: Icons.add_rounded,
          variant: ChunkyButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(_newWalletKey),
        ),
      ],
    );
  }
}
