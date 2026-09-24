/// Completing a task from any screen (Tugas tab, task page, home): asks about
/// the linked expense ("Catat pengeluaran Rp X?"), completes via
/// `completeTaskProvider`, then toasts the XP (shared rewards) and the next
/// occurrence of a recurring task ("Berikutnya: Kam, 2 Okt").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../state/session_controller.dart';
import '../rewards/rewards.dart';
import '../widgets/widgets.dart';

const _monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

/// `Kam, 2 Okt`.
String taskShortDate(DateTime d) =>
    '${isoWeekdayShort[d.weekday - 1]}, ${d.day} ${_monthsShort[d.month - 1]}';

/// What the user picked in the "Catat pengeluaran?" dialog.
final class ExpenseChoice {
  const ExpenseChoice.record(TaskExpense this.expense);
  const ExpenseChoice.skip() : expense = null;

  /// Null = "Selesai saja".
  final TaskExpense? expense;
}

/// "Catat pengeluaran Rp X?" — Ya, catat / Selesai saja (with a wallet picker
/// when the task has none). Null when dismissed.
Future<ExpenseChoice?> showTaskExpenseDialog(
  BuildContext context,
  Task task,
) async {
  final draft = expenseDraftFor(task);
  if (draft == null) return const ExpenseChoice.skip();
  return showChunkyDialog<ExpenseChoice>(
    context,
    builder: (_) => _ExpenseDialog(draft: draft),
  );
}

class _ExpenseDialog extends ConsumerStatefulWidget {
  const _ExpenseDialog({required this.draft});
  final TaskExpense draft;

  @override
  ConsumerState<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<_ExpenseDialog> {
  late String? _walletId = widget.draft.walletId;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final currency = ref.watch(currencyProvider);
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    _walletId ??= wallets.firstOrNull?.id;
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final money = GhinaMoney.format(widget.draft.amount, currency: currency);
    return ChunkyDialog(
      title: 'Catat pengeluaran $money?',
      message: 'Biar saldo dompetmu tetap pas.',
      mood: MascotMood.thinking,
      content: wallets.isEmpty
          ? Text(
              'Belum ada dompet. Bikin dompet dulu buat mencatat, ya.',
              textAlign: TextAlign.center,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            )
          : ChunkyTile(
              key: const ValueKey('expense-wallet'),
              dense: true,
              leading: wallet == null
                  ? null
                  : WalletAvatar(wallet: wallet, size: 36),
              title: wallet?.name ?? 'Pilih dompet',
              subtitle: 'Dibayar pakai',
              showChevron: true,
              onTap: () async {
                final id = await showWalletPickerSheet(
                  context,
                  wallets: wallets,
                  currency: currency,
                  selectedId: _walletId,
                  title: 'Dibayar pakai',
                );
                if (id != null && id.isNotEmpty) {
                  setState(() => _walletId = id);
                }
              },
            ),
      actions: [
        ChunkyButton(
          label: 'Ya, catat',
          icon: Icons.receipt_long_rounded,
          onPressed: wallet == null
              ? null
              : () => Navigator.of(context).pop(
                  ExpenseChoice.record(
                    widget.draft.copyWith(walletId: wallet.id),
                  ),
                ),
        ),
        ChunkyButton(
          label: 'Selesai saja',
          variant: ChunkyButtonVariant.ghost,
          color: GhinaColors.blue,
          onPressed: () =>
              Navigator.of(context).pop(const ExpenseChoice.skip()),
        ),
      ],
    );
  }
}

/// Completes [task]: asks about the linked expense first (dismiss = cancel),
/// then toasts the XP via [RewardTracker] plus "Rp X tercatat" / "Berikutnya:
/// Kam, 2 Okt". Pass a context that outlives the row being completed (the
/// page's). Returns whether the task was completed.
///
/// With [goalHint] the toast also shows the daily goal progress (Beranda).
Future<bool> completeTaskFlow(
  BuildContext context,
  WidgetRef ref,
  Task task, {
  bool goalHint = false,
}) async {
  TaskExpense? expense;
  if (task.hasMoneyLink && task.transactionId == null) {
    final choice = await showTaskExpenseDialog(context, task);
    if (choice == null || !context.mounted) return false;
    expense = choice.expense;
  }
  // The "before" XP snapshot must be loaded, or the toast can't show +XP.
  final rewards = await RewardTracker.startLoaded(ref);
  if (!context.mounted) {
    rewards.cancel();
    return false;
  }
  final complete = ref.read(completeTaskProvider);
  final currency = ref.read(currencyProvider);
  final r = await complete(task.id, expense: expense);
  if (!context.mounted) {
    rewards.cancel();
    return r is Ok;
  }
  switch (r) {
    case Ok(:final value):
      final tx = value.transaction;
      final nextDay = value.next?.dueDay;
      final extras = <String>[
        if (tx != null)
          '${GhinaMoney.format(tx.amount, currency: currency)} tercatat',
        if (nextDay != null) 'Berikutnya: ${taskShortDate(nextDay)}',
      ];
      final suffix = extras.isEmpty ? '' : ' · ${extras.join(' · ')}';
      await rewards.finish(
        context,
        xpToast: (xp) => '${task.bucket.emoji} Beres! +$xp XP$suffix',
        doneToast: 'Beres! ✅$suffix',
        goalHint: goalHint,
      );
      return true;
    case Err(:final failure):
      rewards.cancel();
      showFailureToast(context, failure);
      return false;
  }
}

/// Marks a done task as undone again (keeps the next occurrence and expense).
Future<bool> uncompleteTaskFlow(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final r = await ref.read(uncompleteTaskProvider)(task.id);
  if (!context.mounted) return r is Ok;
  switch (r) {
    case Ok():
      showToastBadge(
        context,
        message: 'Dibuka lagi: ${task.title}',
        icon: Icons.undo_rounded,
        color: GhinaColors.blue,
      );
      return true;
    case Err(:final failure):
      showFailureToast(context, failure);
      return false;
  }
}
