import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/notifications/notification_providers.dart';
import '../../../state/session_controller.dart';
import '../task_actions.dart';
import '../task_draft.dart';
import '../task_format.dart';
import '../widgets/recurrence_builder.dart';
import '../widgets/reminder_settings.dart';
import '../widgets/task_visuals.dart';
import '../widgets/time_picker.dart';

/// `/tasks/new` (optionally pre-filled by a [TaskDraft]) and `/tasks/:id`.
class TaskFormPage extends ConsumerWidget {
  const TaskFormPage({super.key, this.id, this.draft});

  /// Null when creating.
  final String? id;
  final TaskDraft? draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return _TaskForm(existing: null, draft: draft);
    final task = ref.watch(watchTaskProvider(id));
    Scaffold frame(Widget body) => Scaffold(
      appBar: AppBar(title: const Text('Tugas')),
      body: body,
    );
    return task.when(
      skipLoadingOnReload: true,
      loading: () => frame(const LoadingListView(tiles: 4)),
      error: (_, _) => frame(
        ErrorRetry(onRetry: () => ref.invalidate(watchTaskProvider(id))),
      ),
      data: (v) => v == null
          ? frame(
              EmptyState(
                mood: MascotMood.thinking,
                title: 'Tugas nggak ketemu',
                message: 'Mungkin sudah dihapus atau belum tersinkron.',
                actionLabel: 'Kembali',
                onAction: () => popOr(context, '/tasks'),
              ),
            )
          : _TaskForm(key: ValueKey(v.id), existing: v),
    );
  }
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({super.key, required this.existing, this.draft});
  final TaskView? existing;
  final TaskDraft? draft;

  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  TaskView? get e => widget.existing;
  Task? get t => e?.task;
  bool get _isEdit => e != null;

  late final String _currency = ref.read(currencyProvider);
  late final _title = TextEditingController(
    text: t?.title ?? widget.draft?.title ?? '',
  );
  late final _note = TextEditingController(text: t?.note ?? '');
  late final _amount = TextEditingController(
    text: amountToInput(t?.amount, _currency),
  );
  late TaskBucket _bucket =
      t?.bucket ?? widget.draft?.bucket ?? TaskBucket.want;
  late String? _areaId = t?.areaId ?? widget.draft?.areaId;
  late DateTime? _due = t?.dueDay ?? widget.draft?.dueDate;
  late String? _time = t?.dueTime ?? widget.draft?.dueTime;
  late int? _remind = t?.remindBefore;
  late bool _remindTouched = _isEdit && t?.dueTime != null;
  late Recurrence? _recurrence = t?.recurrence;
  late bool _money = t?.hasMoneyLink ?? false;
  late String? _walletId = t?.walletId;
  late String? _categoryId = t?.categoryId;
  final _errors = <String, String>{};
  bool _saving = false;

  DateTime get _today => startOfDay(ref.read(clockProvider).now());

  @override
  void initState() {
    super.initState();
    // Create the lazy controllers now (dispose must not touch `ref`).
    for (final c in [_title, _note, _amount]) {
      c.text;
    }
    if (!_isEdit && _time != null) _applyDefaultRemind();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _applyDefaultRemind() {
    if (_remindTouched) return;
    final s = ref.read(notificationSettingsProvider).value;
    _remind = (s?.enabled ?? true) ? (s?.defaultRemindBefore ?? 10) : null;
  }

  void _clearError(String f) {
    if (_errors.containsKey(f)) setState(() => _errors.remove(f));
  }

  Future<void> _pickDue() async {
    final d = await showGhinaDatePicker(
      context,
      initial: _due ?? _today,
      title: 'Tanggal',
      today: _today,
    );
    if (d != null && mounted) {
      setState(() => _due = startOfDay(d));
      _clearError('recurrence');
    }
  }

  Future<void> _pickTime() async {
    final v = await showChunkyTimePicker(context, initial: _time);
    if (v == null || !mounted) return;
    setState(() {
      _time = v;
      _applyDefaultRemind();
      _errors.remove('dueTime');
    });
  }

  Future<void> _setRemind(int? m) async {
    setState(() {
      _remind = m;
      _remindTouched = true;
    });
    if (m != null) await ensureReminderPermission(context, ref);
  }

  String? _resolveArea(List<TaskArea> areas) {
    if (_areaId != null) return _areaId;
    final focus = ref.read(watchFocusAreasProvider).value;
    return focus?.areas.firstOrNull?.id ?? areas.firstOrNull?.id;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount = _money ? parseAmountInput(_amount.text) : null;
    setState(() {
      _errors.clear();
      if (title.isEmpty) _errors['title'] = 'Tulis judul tugasnya dulu, ya';
      if (_money && (amount == null || amount <= 0)) {
        _errors['amount'] = 'Isi nominalnya, ya';
      }
    });
    if (_errors.isNotEmpty) return;
    final areas = ref.read(watchTaskAreasProvider).value ?? const <TaskArea>[];
    final areaId = _resolveArea(areas);
    if (areaId == null) {
      setState(() => _errors['areaId'] = 'Pilih area dulu, ya');
      return;
    }
    final remind = _due != null && _time != null ? _remind : null;
    setState(() => _saving = true);
    if (remind != null) await ensureReminderPermission(context, ref);
    if (!mounted) return;
    final input = TaskInput(
      areaId: areaId,
      title: title,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      bucket: _bucket,
      dueDate: _due,
      dueTime: _due == null ? null : _time,
      remindBefore: remind,
      recurrence: _due == null ? null : _recurrence,
      amount: amount,
      walletId: _money ? _walletId : null,
      categoryId: _money ? _categoryId : null,
    );
    final r = _isEdit
        ? await ref.read(updateTaskProvider)(e!.id, input)
        : await ref.read(createTaskProvider)(input);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        showToastBadge(
          context,
          message: _isEdit
              ? 'Tugas diperbarui 👍'
              : '${value.bucket.emoji} Tugas ditambah!',
          icon: Icons.task_alt_rounded,
          color: bucketSwatch(value.bucket),
        );
        popOr(context, '/tasks');
      case Err(:final failure):
        if (failure is ValidationFailure && failure.field != null) {
          setState(() => _errors[failure.field!] = failure.message);
        } else {
          showFailureToast(context, failure);
        }
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus tugas ini?',
      message: t!.isRecurring
          ? 'Cuma kejadian ini yang dihapus. Pengeluaran yang sudah tercatat tetap aman.'
          : 'Pengeluaran yang sudah tercatat tetap aman.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteTaskProvider)(t!.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Tugas dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        popOr(context, '/tasks');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _complete() async {
    final ok = await completeTaskFlow(context, ref, t!);
    if (ok && mounted) popOr(context, '/tasks');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final areasAll =
        ref.watch(watchAllTaskAreasProvider).value ?? const <TaskArea>[];
    ref.watch(watchFocusAreasProvider);
    ref.listen(notificationSettingsProvider, (prev, next) {
      if (prev?.value == null && next.value != null && _time != null) {
        setState(_applyDefaultRemind);
      }
    });
    final areaId = _resolveArea(areasAll.where((a) => !a.archived).toList());
    final areas = [
      for (final a in areasAll)
        if (!a.archived || a.id == areaId) a,
    ];
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    final cats =
        ref.watch(watchCategoriesProvider(CategoryType.expense)).value ??
        const <TxCategory>[];
    final wallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final area = areas.where((a) => a.id == areaId).firstOrNull;
    final now = ref.read(clockProvider).now();
    final done = t?.done ?? false;
    final remindOptions = {...remindBeforeOptions, ?_remind}.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah tugas' : 'Tugas baru'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const ValueKey('task-delete'),
              tooltip: 'Hapus',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: GhinaColors.red.base,
              ),
              onPressed: _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(
          children: [
            if (_isEdit) ...[
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('task-toggle-done'),
                  label: done ? 'Buka lagi' : 'Selesai',
                  icon: done ? Icons.undo_rounded : Icons.check_rounded,
                  variant: ChunkyButtonVariant.outline,
                  color: done ? GhinaColors.blue : GhinaColors.green,
                  onPressed: done
                      ? () => uncompleteTaskFlow(context, ref, t!)
                      : _complete,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('task-save'),
                label: _isEdit ? 'Simpan' : 'Tambah',
                loading: _saving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (done)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ChunkyCard(
                tinted: GhinaColors.green,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: GhinaColors.green.base,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t!.transactionId != null
                            ? 'Sudah selesai · pengeluarannya tercatat'
                            : 'Sudah selesai. Mantap! ✅',
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ChunkyTextField(
            key: const ValueKey('task-title'),
            label: 'Judul',
            hint: 'mis. Kirim revisi ke klien',
            controller: _title,
            autofocus: !_isEdit && _title.text.isEmpty,
            errorText: _errors['title'],
            inputFormatters: [LengthLimitingTextInputFormatter(taskTitleMax)],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearError('title'),
          ),
          const SizedBox(height: 10),
          const FieldLabel('Seberapa penting?'),
          ChunkySegmented<TaskBucket>(
            segments: bucketSegments(),
            value: _bucket,
            onChanged: (b) => setState(() => _bucket = b),
          ),
          const SizedBox(height: 6),
          Text(
            '${_bucket.display}: ${_bucket.meaning}',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 18),
          FieldLabel('Area', error: _errors.containsKey('areaId')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in areas)
                ChunkyChip(
                  key: ValueKey('form-area-${a.id}'),
                  label: a.name,
                  icon: GhinaIcons.of(a.icon),
                  color: areaSwatch(a),
                  selected: a.id == areaId,
                  onTap: () => setState(() {
                    _areaId = a.id;
                    _errors.remove('areaId');
                  }),
                ),
            ],
          ),
          if (area != null) ...[
            const SizedBox(height: 6),
            Text(
              'Notifikasi: ${notificationPreview(area.code, _bucket, _title.text.trim().isEmpty ? 'Judul tugas' : _title.text.trim())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: PickerField(
                  key: const ValueKey('task-due'),
                  label: 'Tanggal',
                  placeholder: 'Tanpa tanggal',
                  value: _due == null ? null : dayLabel(_due!, now),
                  leading: Icon(
                    Icons.event_rounded,
                    color: GhinaColors.orange.base,
                  ),
                  trailingIcon: Icons.calendar_month_rounded,
                  onTap: _pickDue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PickerField(
                  key: const ValueKey('task-time'),
                  label: 'Jam',
                  placeholder: 'Kapan saja',
                  value: _time == null ? null : hmDisplay(_time!),
                  leading: Icon(
                    Icons.schedule_rounded,
                    color: GhinaColors.blue.base,
                  ),
                  trailingIcon: Icons.schedule_rounded,
                  enabled: _due != null,
                  errorText: _errors['dueTime'],
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChunkyChip(
                label: 'Hari ini',
                selected: _due != null && isSameDay(_due!, _today),
                color: GhinaColors.orange,
                onTap: () => setState(() => _due = _today),
              ),
              ChunkyChip(
                label: 'Besok',
                selected: _due != null && isSameDay(_due!, addDays(_today, 1)),
                color: GhinaColors.orange,
                onTap: () => setState(() => _due = addDays(_today, 1)),
              ),
              if (_due != null)
                ChunkyChip(
                  key: const ValueKey('task-clear-due'),
                  label: 'Hapus tanggal',
                  icon: Icons.close_rounded,
                  selected: false,
                  color: GhinaColors.gray,
                  onTap: () => setState(() {
                    _due = null;
                    _time = null;
                    _recurrence = null;
                  }),
                ),
              if (_time != null)
                ChunkyChip(
                  label: 'Hapus jam',
                  icon: Icons.close_rounded,
                  selected: false,
                  color: GhinaColors.gray,
                  onTap: () => setState(() => _time = null),
                ),
            ],
          ),
          const SizedBox(height: 18),
          FieldLabel('Pengingat', error: _errors.containsKey('remindBefore')),
          if (_due == null || _time == null)
            Text(
              'Isi tanggal dan jam dulu biar Ghina bisa ngingetin 🔔',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            )
          else
            ChunkyChoiceChips<int>(
              options: [
                const ChunkyChoice(
                  value: -1,
                  label: 'Mati',
                  icon: Icons.notifications_off_rounded,
                ),
                for (final m in remindOptions)
                  ChunkyChoice(value: m, label: remindChip(m)),
              ],
              selected: {_remind ?? -1},
              onChanged: (s) => _setRemind(s.first < 0 ? null : s.first),
            ),
          const SizedBox(height: 22),
          RecurrenceBuilder(
            value: _recurrence,
            dueDay: _due,
            errorText: _errors['recurrence'],
            onChanged: (r) => setState(() {
              _recurrence = r;
              if (r != null) _due ??= _today;
              _errors.remove('recurrence');
            }),
          ),
          const SizedBox(height: 18),
          ChunkyTextField(
            label: 'Catatan',
            hint: 'Opsional',
            controller: _note,
            maxLength: taskNoteMax,
            maxLines: 4,
            minLines: 2,
          ),
          const SizedBox(height: 8),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const ValueKey('task-money'),
                contentPadding: EdgeInsets.zero,
                value: _money,
                onChanged: (v) => setState(() => _money = v),
                title: Text(
                  'Ada biayanya?',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                subtitle: Text(
                  'Pas selesai, Ghina tawarin catat pengeluarannya',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ),
            ),
          ),
          if (_money) ...[
            const SizedBox(height: 14),
            AmountField(
              key: const ValueKey('task-amount'),
              controller: _amount,
              currency: _currency,
              label: 'Perkiraan biaya',
              errorText: _errors['amount'],
              onChanged: (_) => _clearError('amount'),
            ),
            const SizedBox(height: 14),
            PickerField(
              label: 'Dibayar pakai',
              placeholder: 'Pilih nanti',
              value: wallet?.name,
              errorText: _errors['walletId'],
              leading: wallet == null
                  ? null
                  : WalletAvatar(wallet: wallet, size: 34),
              onTap: () async {
                final id = await showWalletPickerSheet(
                  context,
                  wallets: wallets,
                  currency: _currency,
                  selectedId: _walletId,
                  title: 'Dibayar pakai',
                  noneLabel: 'Pilih nanti',
                );
                if (id != null) {
                  setState(() => _walletId = id.isEmpty ? null : id);
                }
              },
            ),
            const SizedBox(height: 14),
            PickerField(
              label: 'Kategori pengeluaran',
              placeholder: 'Tanpa kategori',
              value: cat?.name,
              errorText: _errors['categoryId'],
              leading: cat == null
                  ? null
                  : CategoryAvatar(
                      iconName: cat.icon,
                      colorHex: cat.color,
                      size: 34,
                    ),
              onTap: () async {
                final id = await showCategoryPickerSheet(
                  context,
                  categories: cats,
                  selectedId: _categoryId,
                  noneLabel: 'Tanpa kategori',
                );
                if (id != null) {
                  setState(() => _categoryId = id.isEmpty ? null : id);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
