import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/tx_visuals.dart';

/// The Transaksi tab: month selector, month summary, filters, search, and the
/// list grouped by day.
class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  late YearMonth _month;
  TxType? _type;
  String? _walletId;
  String? _categoryId;
  String _search = '';
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _month = YearMonth.of(ref.read(clockProvider).now());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _type != null ||
      _walletId != null ||
      _categoryId != null ||
      _search.trim().isNotEmpty;

  TransactionFilter get _filter => TransactionFilter(
    month: _month,
    type: _type,
    walletId: _walletId,
    categoryId: _categoryId,
    search: _search.trim().isEmpty ? null : _search.trim(),
  );

  void _resetFilters() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _type = null;
      _walletId = null;
      _categoryId = null;
      _search = '';
    });
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = v);
    });
  }

  Future<void> _pickWallet(List<Wallet> wallets) async {
    final picked = await showChunkyBottomSheet<String>(
      context,
      title: 'Filter dompet',
      builder: (c) => _PickList(
        allLabel: 'Semua dompet',
        selectedId: _walletId,
        items: [
          for (final w in wallets)
            (
              id: w.id,
              label: w.name,
              leading: WalletAvatar(wallet: w, size: 36),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _walletId = picked.isEmpty ? null : picked);
  }

  Future<void> _pickCategory(List<TxCategory> categories) async {
    final picked = await showChunkyBottomSheet<String>(
      context,
      title: 'Filter kategori',
      builder: (c) => _PickList(
        allLabel: 'Semua kategori',
        selectedId: _categoryId,
        items: [
          for (final cat in categories)
            (
              id: cat.id,
              label: cat.name,
              leading: CategoryAvatar(
                iconName: cat.icon,
                colorHex: cat.color,
                size: 36,
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked.isEmpty ? null : picked);
  }

  Future<void> _confirmDelete(TransactionView v) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus transaksi?',
      message: '"${v.title}" akan dihapus dan saldo dompet disesuaikan lagi.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteTransactionProvider)(v.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Transaksi dihapus', icon: Icons.delete_rounded);
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _actions(TransactionView v, String currency) async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: v.title,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: MoneyText(
              amount: v.amount,
              currency: v.wallet?.currency ?? currency,
              tone: txTone(v.type),
              style: GhinaType.moneyL,
            ),
          ),
          Center(
            child: Text(
              Fmt.dateFull(v.date),
              style: GhinaType.bodyS.copyWith(color: c.ghina.textSecondary),
            ),
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyButton(
            label: 'Edit',
            icon: Icons.edit_rounded,
            variant: ChunkyButtonVariant.secondary,
            onPressed: () => Navigator.of(c).pop('edit'),
          ),
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            label: 'Catat lagi',
            icon: Icons.content_copy_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: () => Navigator.of(c).pop('again'),
          ),
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            label: 'Hapus',
            icon: Icons.delete_rounded,
            variant: ChunkyButtonVariant.danger,
            onPressed: () => Navigator.of(c).pop('delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        context.push('/transactions/${v.id}');
      case 'again':
        ref
            .read(txFormPresetProvider.notifier)
            .set(
              TxFormPreset(
                type: v.type,
                walletId: v.transaction.walletId,
                categoryId: v.transaction.categoryId,
              ),
            );
        context.push('/transactions/new');
      case 'delete':
        await _confirmDelete(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final wallets = ref.watch(watchAllWalletsProvider);
    final categories =
        ref.watch(watchCategoriesProvider(null)).value ?? const [];
    final monthAll = ref.watch(
      watchTransactionsByDayProvider(TransactionFilter(month: _month)),
    );
    final groups = ref.watch(watchTransactionsByDayProvider(_filter));

    final walletList = wallets.value ?? const <Wallet>[];
    final selWallet = walletList.where((w) => w.id == _walletId).firstOrNull;
    final selCat = categories.where((c) => c.id == _categoryId).firstOrNull;
    final now = ref.read(clockProvider).now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        centerTitle: false,
        actions: [
          IconButton(
            key: const ValueKey('tx-search-toggle'),
            tooltip: 'Cari',
            icon: Icon(
              _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() => _searchOpen = !_searchOpen);
              if (!_searchOpen && _search.isNotEmpty) {
                _searchCtrl.clear();
                setState(() => _search = '');
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.md,
                GhinaSpace.page,
                0,
              ),
              sliver: SliverList.list(
                children: [
                  MonthSwitcher(
                    value: _month,
                    current: YearMonth.of(now),
                    onChanged: (m) => setState(() => _month = m),
                  ),
                  const SizedBox(height: GhinaSpace.md),
                  _MonthSummary(groups: monthAll, currency: currency),
                  const SizedBox(height: GhinaSpace.md),
                  if (_searchOpen) ...[
                    ChunkyTextField(
                      key: const ValueKey('tx-search'),
                      controller: _searchCtrl,
                      hint: 'Cari catatan, kategori, dompet…',
                      prefixIcon: Icons.search_rounded,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearch,
                      onSubmitted: (v) {
                        _debounce?.cancel();
                        setState(() => _search = v);
                      },
                    ),
                    const SizedBox(height: GhinaSpace.md),
                  ],
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        for (final t in [null, ...TxType.values])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChunkyChip(
                              label: t?.label ?? 'Semua',
                              selected: _type == t,
                              color: t == null ? GhinaColors.blue : txSwatch(t),
                              onTap: () => setState(() => _type = t),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChunkyChip(
                            label: selWallet?.name ?? 'Dompet',
                            icon: Icons.account_balance_wallet_rounded,
                            selected: selWallet != null,
                            color: GhinaColors.purple,
                            onTap: () => _pickWallet(walletList),
                          ),
                        ),
                        ChunkyChip(
                          label: selCat?.name ?? 'Kategori',
                          icon: Icons.sell_rounded,
                          selected: selCat != null,
                          color: GhinaColors.orange,
                          onTap: () => _pickCategory(categories),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: GhinaSpace.sm),
                ],
              ),
            ),
            ..._listSlivers(groups, wallets, currency, now),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  List<Widget> _listSlivers(
    AsyncValue<List<DayGroup>> groups,
    AsyncValue<List<Wallet>> wallets,
    String currency,
    DateTime now,
  ) {
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);

    if (groups.hasError && !groups.hasValue) {
      return [
        fill(
          ErrorRetry(
            onRetry: () =>
                ref.invalidate(watchTransactionsByDayProvider(_filter)),
          ),
        ),
      ];
    }
    final data = groups.value;
    if (data == null) {
      return [
        const SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: GhinaSpace.page,
            vertical: GhinaSpace.sm,
          ),
          sliver: SliverToBoxAdapter(child: SkeletonList(count: 5)),
        ),
      ];
    }
    if (data.isEmpty) {
      if (wallets.value?.isEmpty ?? false) {
        return [
          fill(
            EmptyState(
              mood: MascotMood.waving,
              title: 'Bikin dompet dulu, yuk!',
              message: 'Semua transaksi dicatat ke dompet. Mulai dari "Tunai".',
              actionLabel: 'Tambah dompet',
              onAction: () => context.push('/wallets/new'),
            ),
          ),
        ];
      }
      if (_hasFilters) {
        return [
          fill(
            EmptyState(
              mood: MascotMood.thinking,
              title: 'Nggak ketemu',
              message: 'Nggak ada transaksi yang cocok sama filter ini.',
              actionLabel: 'Reset filter',
              onAction: _resetFilters,
            ),
          ),
        ];
      }
      return [
        fill(
          EmptyState(
            title: 'Belum ada transaksi',
            message:
                'Bulan ${Fmt.monthYear(_month.start)} masih kosong. Catat yang pertama, yuk!',
            actionLabel: 'Catat transaksi',
            onAction: () => context.push('/transactions/new'),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
        sliver: SliverList.builder(
          itemCount: data.length,
          itemBuilder: (context, i) => PopIn(
            delay: Duration(milliseconds: 40 * (i < 6 ? i : 6)),
            fromScale: 0.96,
            slideY: 12,
            child: _DayCard(
              group: data[i],
              currency: currency,
              now: now,
              onTap: (v) => context.push('/transactions/${v.id}'),
              onLongPress: (v) => _actions(v, currency),
              onDismiss: _confirmDeleteDismiss,
            ),
          ),
        ),
      ),
    ];
  }

  Future<bool> _confirmDeleteDismiss(TransactionView v) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus transaksi?',
      message: '"${v.title}" akan dihapus dan saldo dompet disesuaikan lagi.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return false;
    final r = await ref.read(deleteTransactionProvider)(v.id);
    if (!mounted) return false;
    switch (r) {
      case Ok():
        showOkToast(context, 'Transaksi dihapus', icon: Icons.delete_rounded);
        return true;
      case Err(:final failure):
        showFailureToast(context, failure);
        return false;
    }
  }
}

// ---------------------------------------------------------------- pieces

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.groups, required this.currency});

  final AsyncValue<List<DayGroup>> groups;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final data = groups.value;
    if (data == null) return const Skeleton(height: 96);
    final income = data.fold<double>(0, (s, d) => s + d.income);
    final expense = data.fold<double>(0, (s, d) => s + d.expense);
    final net = income - expense;
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryBlock(
                  label: 'Pemasukan',
                  icon: Icons.south_west_rounded,
                  color: GhinaColors.income,
                  child: MoneyText(
                    amount: income,
                    currency: currency,
                    tone: MoneyTone.income,
                    compact: income >= 100000000,
                    style: GhinaType.moneyM.copyWith(fontSize: 18),
                  ),
                ),
              ),
              Container(width: 2, height: 44, color: g.border),
              const SizedBox(width: 14),
              Expanded(
                child: _SummaryBlock(
                  label: 'Pengeluaran',
                  icon: Icons.north_east_rounded,
                  color: GhinaColors.expense,
                  child: MoneyText(
                    amount: expense,
                    currency: currency,
                    tone: MoneyTone.expense,
                    compact: expense >= 100000000,
                    style: GhinaType.moneyM.copyWith(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: g.surfaceAlt,
              borderRadius: GhinaRadii.rMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Selisih bulan ini',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MoneyText(
                      key: const ValueKey('month-net'),
                      amount: net,
                      currency: currency,
                      style: GhinaType.moneyS.copyWith(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.label,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String label;
  final IconData icon;
  final ChunkySwatch color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color.tint(g.brightness),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: color.base),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.group,
    required this.currency,
    required this.now,
    required this.onTap,
    required this.onLongPress,
    required this.onDismiss,
  });

  final DayGroup group;
  final String currency;
  final DateTime now;
  final ValueChanged<TransactionView> onTap;
  final ValueChanged<TransactionView> onLongPress;
  final Future<bool> Function(TransactionView) onDismiss;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rel = Fmt.relativeDay(group.day, now: now);
    final isNear = rel == 'Hari ini' || rel == 'Kemarin';
    final title = isNear
        ? '$rel · ${Fmt.dateShortWeekday(group.day)}'
        : Fmt.dateShortWeekday(group.day);
    return Padding(
      padding: const EdgeInsets.only(top: GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.overline.copyWith(
                      color: isNear ? GhinaColors.blue.base : g.textSecondary,
                    ),
                  ),
                ),
                if (group.income > 0 || group.expense > 0)
                  MoneyText(
                    amount: group.net,
                    currency: currency,
                    style: GhinaType.moneyS,
                  ),
              ],
            ),
          ),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  if (i > 0) Divider(height: 2, thickness: 2, color: g.border),
                  _SwipeRow(
                    view: group.items[i],
                    currency: currency,
                    onTap: onTap,
                    onLongPress: onLongPress,
                    onDismiss: onDismiss,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeRow extends StatelessWidget {
  const _SwipeRow({
    required this.view,
    required this.currency,
    required this.onTap,
    required this.onLongPress,
    required this.onDismiss,
  });

  final TransactionView view;
  final String currency;
  final ValueChanged<TransactionView> onTap;
  final ValueChanged<TransactionView> onLongPress;
  final Future<bool> Function(TransactionView) onDismiss;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('tx-${view.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDismiss(view),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: GhinaColors.red.base,
          borderRadius: GhinaRadii.rLg,
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: TransactionRow(
        view: view,
        currency: currency,
        onTap: () => onTap(view),
        onLongPress: () => onLongPress(view),
      ),
    );
  }
}

typedef _PickItem = ({String id, String label, Widget leading});

/// Sheet list for the wallet/category filters. Pops `''` for "all".
class _PickList extends StatelessWidget {
  const _PickList({
    required this.allLabel,
    required this.selectedId,
    required this.items,
  });

  final String allLabel;
  final String? selectedId;
  final List<_PickItem> items;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTile(
          title: allLabel,
          dense: true,
          leading: CategoryAvatar(
            icon: Icons.apps_rounded,
            color: g.textMuted,
            size: 36,
            soft: true,
          ),
          tinted: selectedId == null ? GhinaColors.blue : null,
          onTap: () => Navigator.of(context).pop(''),
        ),
        for (final it in items) ...[
          const SizedBox(height: GhinaSpace.sm),
          ChunkyTile(
            title: it.label,
            dense: true,
            leading: it.leading,
            tinted: it.id == selectedId ? GhinaColors.blue : null,
            onTap: () => Navigator.of(context).pop(it.id),
          ),
        ],
      ],
    );
  }
}
