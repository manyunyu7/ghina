/// Turning a note into action (docs/notes.md → "Convert to action"): → Tugas
/// (area + bucket sheet), → Konten (then offer to open it), → Transaksi (a
/// prefilled confirm sheet). Shared by the editor and the share sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/rewards/rewards.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/session_controller.dart';
import 'widgets/note_visuals.dart';

/// Conversion targets.
enum NoteConvert { task, content, transaction }

ChunkySwatch _bucketSwatch(TaskBucket b) => switch (b) {
  TaskBucket.fire => GhinaColors.red,
  TaskBucket.want => GhinaColors.purple,
  TaskBucket.should => GhinaColors.blue,
};

/// "Jadikan…" menu. Rows of targets the note is already linked to open the
/// linked item instead. Returns the chosen target (null = dismissed or opened).
Future<NoteConvert?> showConvertMenu(BuildContext context, Note note) =>
    showChunkyBottomSheet<NoteConvert>(
      context,
      title: 'Jadikan…',
      showClose: true,
      builder: (c) {
        Widget row({
          required NoteConvert target,
          required IconData icon,
          required ChunkySwatch color,
          required String title,
          required String subtitle,
          String? linkedRoute,
          required String linkedLabel,
        }) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ChunkyTile(
            key: ValueKey('convert-${target.name}'),
            leading: CategoryAvatar(icon: icon, color: color.base, size: 44),
            title: linkedRoute != null ? linkedLabel : title,
            subtitle: linkedRoute != null ? 'Ketuk untuk membuka' : subtitle,
            showChevron: true,
            tinted: linkedRoute != null ? color : null,
            onTap: () {
              Navigator.of(c).pop(linkedRoute != null ? null : target);
              if (linkedRoute != null) context.push(linkedRoute);
            },
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              target: NoteConvert.task,
              icon: Icons.task_alt_rounded,
              color: GhinaColors.red,
              title: 'Tugas',
              subtitle: 'Masuk ke papan FIRE / WANT / SHOULD',
              linkedRoute: note.linkedTaskId == null
                  ? null
                  : taskRoute(note.linkedTaskId!),
              linkedLabel: 'Sudah jadi tugas',
            ),
            row(
              target: NoteConvert.content,
              icon: Icons.movie_creation_rounded,
              color: GhinaColors.purple,
              title: 'Konten',
              subtitle: 'Jadi ide konten di tahap Ide',
              linkedRoute: note.linkedContentId == null
                  ? null
                  : contentItemRoute(note.linkedContentId!),
              linkedLabel: 'Sudah jadi konten',
            ),
            row(
              target: NoteConvert.transaction,
              icon: Icons.receipt_long_rounded,
              color: GhinaColors.green,
              title: 'Transaksi',
              subtitle: 'Catat pengeluaran/pemasukan dari catatan ini',
              linkedRoute: note.linkedTransactionId == null
                  ? null
                  : '/transactions/${note.linkedTransactionId}',
              linkedLabel: 'Sudah jadi transaksi',
            ),
          ],
        );
      },
    );

/// Runs [target] for [note]. Returns the updated note (null = cancelled or
/// failed; failures are toasted).
Future<Note?> runConvert(
  BuildContext context,
  WidgetRef ref,
  Note note,
  NoteConvert target,
) => switch (target) {
  NoteConvert.task => convertToTaskFlow(context, ref, note),
  NoteConvert.content => convertToContentFlow(context, ref, note),
  NoteConvert.transaction => convertToTransactionFlow(context, ref, note),
};

// ---------------------------------------------------------------- → Tugas

Future<Note?> convertToTaskFlow(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final r = await showChunkyBottomSheet<({Note note, Task task})>(
    context,
    title: 'Jadikan tugas',
    showClose: true,
    builder: (_) => _TaskConvertSheet(note: note),
  );
  if (r == null || !context.mounted) return null;
  showToastBadge(
    context,
    message: '${r.task.bucket.emoji} Jadi tugas! Cek di tab Tugas',
    icon: Icons.task_alt_rounded,
    color: _bucketSwatch(r.task.bucket),
  );
  return r.note;
}

class _TaskConvertSheet extends ConsumerStatefulWidget {
  const _TaskConvertSheet({required this.note});
  final Note note;

  @override
  ConsumerState<_TaskConvertSheet> createState() => _TaskConvertSheetState();
}

class _TaskConvertSheetState extends ConsumerState<_TaskConvertSheet> {
  late final _title = TextEditingController(
    text: noteActionTitle(widget.note, max: 200),
  );
  TaskBucket _bucket = TaskBucket.want;
  String? _areaId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String? _resolveArea(List<TaskArea> areas) {
    if (_areaId != null && areas.any((a) => a.id == _areaId)) return _areaId;
    final focus = ref.read(watchFocusAreasProvider).value;
    return focus?.areas.firstOrNull?.id ?? areas.firstOrNull?.id;
  }

  Future<void> _save(List<TaskArea> areas) async {
    final areaId = _resolveArea(areas);
    if (areaId == null) {
      setState(() => _error = 'Belum ada area tugas. Bikin dulu di tab Tugas');
      return;
    }
    setState(() => _saving = true);
    final r = await ref.read(convertNoteToTaskProvider)(
      widget.note.id,
      NoteTaskInput(areaId: areaId, bucket: _bucket, title: _title.text),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final areas = ref.watch(watchTaskAreasProvider).value ?? const <TaskArea>[];
    ref.watch(watchFocusAreasProvider);
    final areaId = _resolveArea(areas);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('convert-task-title'),
          label: 'Judul tugas',
          controller: _title,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
          errorText: _error,
        ),
        const SizedBox(height: 14),
        const FieldLabel('Seberapa penting?'),
        ChunkySegmented<TaskBucket>(
          segments: [
            for (final b in TaskBucket.values)
              ChunkySegment(
                value: b,
                label: b.display,
                color: _bucketSwatch(b),
              ),
          ],
          value: _bucket,
          onChanged: (b) => setState(() => _bucket = b),
        ),
        const SizedBox(height: 6),
        Text(
          '${_bucket.display}: ${_bucket.meaning}',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        if (areas.isNotEmpty) ...[
          const SizedBox(height: 14),
          const FieldLabel('Area'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in areas)
                ChunkyChip(
                  key: ValueKey('convert-area-${a.id}'),
                  label: a.name,
                  icon: GhinaIcons.of(a.icon),
                  color: CategoryColors.swatch(a.color),
                  selected: a.id == areaId,
                  onTap: () => setState(() => _areaId = a.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        ChunkyButton(
          key: const ValueKey('convert-task-save'),
          label: 'Jadikan tugas',
          icon: Icons.task_alt_rounded,
          loading: _saving,
          onPressed: () => _save(areas),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- → Konten

Future<Note?> convertToContentFlow(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final convert = ref.read(convertNoteToContentProvider);
  final r = await convert(note.id);
  if (!context.mounted) return null;
  switch (r) {
    case Err(:final failure):
      showFailureToast(context, failure);
      return null;
    case Ok(:final value):
      final open = await showChunkyDialog<bool>(
        context,
        builder: (c) => ChunkyDialog(
          title: 'Jadi ide konten! 🎬',
          message:
              '"${value.item.title}" masuk ke tahap Ide. Mau lanjut garap sekarang?',
          mood: MascotMood.excited,
          actions: [
            ChunkyButton(
              key: const ValueKey('open-content'),
              label: 'Buka konten',
              onPressed: () => Navigator.of(c).pop(true),
            ),
            ChunkyButton(
              label: 'Nanti saja',
              variant: ChunkyButtonVariant.ghost,
              onPressed: () => Navigator.of(c).pop(false),
            ),
          ],
        ),
      );
      if (open == true && context.mounted) {
        context.push(contentItemRoute(value.item.id));
      }
      return value.note;
  }
}

// ---------------------------------------------------------------- → Transaksi

Future<Note?> convertToTransactionFlow(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final rewards = RewardTracker.start(ref);
  final r = await showChunkyBottomSheet<({Note note, Transaction transaction})>(
    context,
    title: 'Jadikan transaksi',
    showClose: true,
    builder: (_) => _TxConvertSheet(note: note),
  );
  if (r == null) {
    rewards.cancel();
    return null;
  }
  if (context.mounted) {
    await rewards.finish(
      context,
      xpToast: (xp) => 'Tercatat dari catatan! +$xp XP',
      doneToast: 'Transaksi tercatat 👍',
    );
  } else {
    rewards.cancel();
  }
  return r.note;
}

class _TxConvertSheet extends ConsumerStatefulWidget {
  const _TxConvertSheet({required this.note});
  final Note note;

  @override
  ConsumerState<_TxConvertSheet> createState() => _TxConvertSheetState();
}

class _TxConvertSheetState extends ConsumerState<_TxConvertSheet> {
  late final NoteTransactionDraft _draft = noteTransactionDraft(widget.note);
  late final _amount = TextEditingController(
    text: amountToInput(_draft.amount, ref.read(currencyProvider)),
  );
  late final _note = TextEditingController(text: _draft.note);
  TxType _type = TxType.expense;
  String? _walletId;
  String? _categoryId;
  bool _saving = false;
  String? _amountError;
  String? _walletError;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickWallet(List<Wallet> wallets, String currency) async {
    final id = await showWalletPickerSheet(
      context,
      wallets: wallets,
      currency: currency,
      selectedId: _walletId,
    );
    if (id != null && id.isNotEmpty && mounted) {
      setState(() {
        _walletId = id;
        _walletError = null;
      });
    }
  }

  Future<void> _pickCategory(List<TxCategory> cats) async {
    final id = await showCategoryPickerSheet(
      context,
      categories: cats,
      selectedId: _categoryId,
      noneLabel: 'Tanpa kategori',
    );
    if (id != null && mounted) {
      setState(() => _categoryId = id.isEmpty ? null : id);
    }
  }

  Future<void> _save(String? walletId) async {
    final amount = parseAmountInput(_amount.text);
    setState(() {
      _amountError = amount == null || amount <= 0
          ? 'Isi nominalnya dulu, ya'
          : null;
      _walletError = walletId == null ? 'Pilih dompet dulu' : null;
    });
    if (_amountError != null || _walletError != null) return;
    setState(() => _saving = true);
    final r = await ref.read(convertNoteToTransactionProvider)(
      widget.note.id,
      TransactionInput(
        type: _type,
        amount: amount!,
        walletId: walletId!,
        categoryId: _categoryId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        date: ref.read(clockProvider).now(),
        photos: _draft.photos,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final currency = ref.watch(currencyProvider);
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final allCats =
        ref.watch(watchCategoriesProvider(null)).value ?? const <TxCategory>[];
    final want = _type == TxType.income
        ? CategoryType.income
        : CategoryType.expense;
    final cats = [
      for (final c in allCats)
        if (c.type == want) c,
    ];
    final walletId =
        _walletId ?? (wallets.length == 1 ? wallets.first.id : null);
    final wallet = wallets.where((w) => w.id == walletId).firstOrNull;
    final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final photos = _draft.photos;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkySegmented<TxType>(
          segments: const [
            ChunkySegment(
              value: TxType.expense,
              label: 'Pengeluaran',
              color: GhinaColors.red,
            ),
            ChunkySegment(
              value: TxType.income,
              label: 'Pemasukan',
              color: GhinaColors.green,
            ),
          ],
          value: _type,
          onChanged: (t) => setState(() {
            _type = t;
            _categoryId = null;
          }),
        ),
        const SizedBox(height: 14),
        AmountField(
          key: const ValueKey('convert-tx-amount'),
          controller: _amount,
          currency: currency,
          errorText: _amountError,
          helperText: _draft.amount == null
              ? 'Nominal nggak ketemu di catatan, isi manual ya'
              : 'Diambil dari catatan',
        ),
        const SizedBox(height: 12),
        PickerField(
          key: const ValueKey('convert-tx-wallet'),
          label: 'Dompet',
          value: wallet?.name,
          leading: wallet == null
              ? null
              : WalletAvatar(wallet: wallet, size: 32),
          errorText: _walletError,
          onTap: () => _pickWallet(wallets, currency),
        ),
        const SizedBox(height: 12),
        PickerField(
          key: const ValueKey('convert-tx-category'),
          label: 'Kategori',
          value: cat?.name,
          placeholder: 'Tanpa kategori',
          leading: cat == null
              ? null
              : CategoryAvatar(
                  iconName: cat.icon,
                  colorHex: cat.color,
                  size: 32,
                ),
          onTap: () => _pickCategory(cats),
        ),
        const SizedBox(height: 12),
        ChunkyTextField(
          label: 'Catatan transaksi',
          controller: _note,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          FieldLabel('${photos.length} foto ikut dilampirkan'),
          PhotoStrip(
            photos: noteViewerPhotos(photos),
            size: 52,
            heroScope: 'convert-tx',
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Tanggal: hari ini. Ubah detail lain nanti dari daftar transaksi.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          key: const ValueKey('convert-tx-save'),
          label: 'Catat transaksi',
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: () => _save(walletId),
        ),
      ],
    );
  }
}
